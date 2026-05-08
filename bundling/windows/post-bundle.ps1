param(
  [Parameter(Mandatory = $true)]
  [string]$Version,

  [Parameter(Mandatory = $true)]
  [string]$Target
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$Binary = Join-Path $Root "target/$Target/release/monocurl.exe"
$Assets = Join-Path $Root "assets"
$Dist = Join-Path $Root "dist/windows"

if (-not (Test-Path $Binary)) {
  throw "binary not found: $Binary"
}

if (-not (Test-Path $Assets)) {
  throw "assets directory not found: $Assets"
}

New-Item -ItemType Directory -Force $Dist | Out-Null

$StageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("monocurl-windows-" + [System.Guid]::NewGuid().ToString("N"))
$AppName = "Monocurl-$Version-$Target"
$App = Join-Path $StageRoot $AppName
$Zip = Join-Path $Dist "$AppName.zip"

try {
  New-Item -ItemType Directory -Force $App | Out-Null
  Copy-Item $Binary (Join-Path $App "monocurl.exe")
  Copy-Item $Assets (Join-Path $App "assets") -Recurse

  Get-ChildItem -Path (Join-Path $App "assets") -Recurse -Force -Filter ".DS_Store" |
    Remove-Item -Force

  if (Test-Path $Zip) {
    Remove-Item $Zip -Force
  }

  Compress-Archive -Path $App -DestinationPath $Zip -CompressionLevel Optimal
  Write-Host "[ok] $Zip"
} finally {
  Remove-Item $StageRoot -Recurse -Force -ErrorAction SilentlyContinue
}
