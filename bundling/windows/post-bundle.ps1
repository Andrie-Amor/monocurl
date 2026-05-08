param(
  [Parameter(Mandatory = $true)]
  [string]$Version,

  [Parameter(Mandatory = $true)]
  [string]$Target
)

$ErrorActionPreference = "Stop"

$Root     = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$Binary   = Join-Path $Root "target\$Target\release\monocurl.exe"
$Assets   = Join-Path $Root "assets"
$Dist     = Join-Path $Root "dist\windows"
$Arch     = $Target.Split('-')[0]
$OutBase  = "Monocurl-windows-$Arch-installer"

if (-not (Test-Path $Binary)) { throw "binary not found: $Binary" }
if (-not (Test-Path $Assets)) { throw "assets not found: $Assets" }

New-Item -ItemType Directory -Force $Dist | Out-Null

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("monocurl-windows-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $TempDir | Out-Null

try {
    # stage binary + assets
    $StageDir = Join-Path $TempDir "stage"
    New-Item -ItemType Directory -Force $StageDir | Out-Null
    Copy-Item $Binary (Join-Path $StageDir "monocurl.exe")
    Copy-Item $Assets (Join-Path $StageDir "assets") -Recurse
    Get-ChildItem -Path (Join-Path $StageDir "assets") -Recurse -Force -Filter ".DS_Store" | Remove-Item -Force

    # generate .ico from the 256px png
    $IconSrc  = Join-Path $Root "assets\AppIcon.appiconset\monocurl-256.png"
    $IconFile = Join-Path $TempDir "monocurl.ico"
    & magick $IconSrc -define icon:auto-resize="256,128,64,48,32,16" $IconFile
    if ($LASTEXITCODE -ne 0) { throw "icon conversion failed" }

    # fill template (use .Replace() to avoid regex interpretation of paths)
    $Iss = (Get-Content (Join-Path $PSScriptRoot "Monocurl.iss.in") -Raw)
    $Iss = $Iss.Replace('__VERSION__',    $Version)
    $Iss = $Iss.Replace('__SOURCE_DIR__', $StageDir)
    $Iss = $Iss.Replace('__OUTPUT_DIR__', $Dist)
    $Iss = $Iss.Replace('__OUTPUT_BASE__', $OutBase)
    $Iss = $Iss.Replace('__ICON_FILE__',  $IconFile)
    $IssPath = Join-Path $TempDir "Monocurl.iss"
    Set-Content $IssPath $Iss -Encoding UTF8

    # locate iscc
    $Iscc = "C:\Program Files (x86)\Inno Setup 6\iscc.exe"
    if (-not (Test-Path $Iscc)) {
        $Iscc = (Get-Command iscc -ErrorAction SilentlyContinue)?.Source
    }
    if (-not $Iscc) { throw "Inno Setup compiler (iscc.exe) not found" }

    & $Iscc $IssPath
    if ($LASTEXITCODE -ne 0) { throw "iscc failed with exit code $LASTEXITCODE" }

    Write-Host "[ok] $(Join-Path $Dist "$OutBase.exe")"
} finally {
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
