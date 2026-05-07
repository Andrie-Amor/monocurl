#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Monocurl"
APP_IDENTIFIER="${APP_IDENTIFIER:-com.enigmadux.monocurl}"
APP_PUBLISHER="enigmadux"
APP_ID="${APP_ID:-{E7B3B000-E809-4AF3-908E-1EB16A815F36}}"
APP_ICON_NAME="Monocurl"
APP_ICON_FILE_BASENAME="$APP_ICON_NAME"
APP_ICON_FILE="${APP_ICON_NAME}.ico"
BIN_NAME="monocurl"
TEMPLATE_DIR="$ROOT_DIR/bundling/templates"
APP_ICONSET_DIR="$ROOT_DIR/assets/AppIcon.appiconset"
ICON_SCRIPT="$ROOT_DIR/bundling/scripts/make_windows_icon.py"
APP_PATH_ENV="${APP_PATH_ENV:-$PATH}"

MACOS_TARGET_DEFAULT="aarch64-apple-darwin"
WIN_TARGET_DEFAULT="x86_64-pc-windows-msvc"

# macOS signing/notarization options
MACOS_SIGN="${MACOS_SIGN:-0}"
MACOS_SIGN_INSTALLER="${MACOS_SIGN_INSTALLER:-0}"
WINDOWS_SIGN_INSTALLER="${WINDOWS_SIGN_INSTALLER:-$MACOS_SIGN_INSTALLER}"
MACOS_NOTARIZE="${MACOS_NOTARIZE:-0}"
MACOS_CREATE_ZIP="${MACOS_CREATE_ZIP:-1}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
CODESIGN_INSTALLER_IDENTITY="${CODESIGN_INSTALLER_IDENTITY:-$CODESIGN_IDENTITY}"
CODESIGN_ENTITLEMENTS="${CODESIGN_ENTITLEMENTS:-$TEMPLATE_DIR/macos/Monocurl.entitlements.in}"
APPLE_NOTARY_KEYCHAIN_PROFILE="${APPLE_NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_NOTARY_APPLE_ID="${APPLE_NOTARY_APPLE_ID:-}"
APPLE_NOTARY_PASSWORD="${APPLE_NOTARY_PASSWORD:-}"
APPLE_NOTARY_TEAM_ID="${APPLE_NOTARY_TEAM_ID:-}"

is_true() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

  case "$value" in
    1|true|yes|on|enabled)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

render_template() {
  local src="$1"
  local dst="$2"
  sed -e "s|__APP_NAME__|$APP_NAME|g" \
      -e "s|__VERSION__|$VERSION|g" \
      -e "s|__APP_IDENTIFIER__|$APP_IDENTIFIER|g" \
      -e "s|__APP_ID__|$APP_ID|g" \
      -e "s|__APP_PUBLISHER__|$APP_PUBLISHER|g" \
      -e "s|__APP_ICON_FILE__|$APP_ICON_FILE|g" \
      -e "s|__APP_ICON_FILE_BASENAME__|$APP_ICON_FILE_BASENAME|g" \
      -e "s|__PATH__|$APP_PATH_ENV|g" \
      "$src" > "$dst"
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[error] required command '$cmd' not found" >&2
    exit 1
  fi
}

make_macos_icon() {
  local app_dir="$1"
  local icon_source="$APP_ICONSET_DIR/monocurl-1024-1024.png"
  local icon_dest="$app_dir/Contents/Resources/$APP_ICON_FILE_BASENAME.icns"

  if [[ ! -d "$APP_ICONSET_DIR" ]]; then
    echo "[error] expected iconset at $APP_ICONSET_DIR" >&2
    exit 1
  fi

  if [[ ! -f "$icon_source" ]]; then
    echo "[error] expected source icon $icon_source" >&2
    exit 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "[error] python3 is required to generate $APP_ICON_FILE_BASENAME.icns" >&2
    exit 1
  fi

  if [[ ! -f "$ICON_SCRIPT" ]]; then
    echo "[error] expected icon conversion script at $ICON_SCRIPT" >&2
    exit 1
  fi

  python3 "$ICON_SCRIPT" "$icon_source" "$icon_dest"
}

make_windows_icon() {
  local output_dir="$1"
  local icon_source="$APP_ICONSET_DIR/monocurl-1024-1024.png"
  local icon_dest="$output_dir/$APP_ICON_NAME.ico"

  if [[ ! -d "$APP_ICONSET_DIR" ]]; then
    echo "[error] expected iconset at $APP_ICONSET_DIR" >&2
    exit 1
  fi

  if [[ ! -f "$icon_source" ]]; then
    echo "[error] expected source icon $icon_source" >&2
    exit 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "[error] python3 is required to generate Monocurl.ico from $APP_ICONSET_DIR" >&2
    exit 1
  fi

  if [[ ! -f "$ICON_SCRIPT" ]]; then
    echo "[error] expected icon conversion script at $ICON_SCRIPT" >&2
    exit 1
  fi

  python3 "$ICON_SCRIPT" "$icon_source" "$icon_dest"
}

render_macos_entitlements() {
  local output_dir="$1"
  local entitlements_dest="$output_dir/$APP_NAME.entitlements"
  local entitlements_src="$CODESIGN_ENTITLEMENTS"

  if [[ -z "$CODESIGN_ENTITLEMENTS" ]]; then
    return 0
  fi

  if [[ ! -f "$entitlements_src" && -f "$ROOT_DIR/$CODESIGN_ENTITLEMENTS" ]]; then
    entitlements_src="$ROOT_DIR/$CODESIGN_ENTITLEMENTS"
  elif [[ ! -f "$entitlements_src" && -f "$ROOT_DIR/bundling/$CODESIGN_ENTITLEMENTS" ]]; then
    entitlements_src="$ROOT_DIR/bundling/$CODESIGN_ENTITLEMENTS"
  fi

  if [[ ! -f "$entitlements_src" ]]; then
    echo "[error] codesign entitlements file not found: $CODESIGN_ENTITLEMENTS" >&2
    exit 1
  fi

  mkdir -p "$output_dir"
  cp "$entitlements_src" "$entitlements_dest"
  echo "$entitlements_dest"
}

macos_otool_dependencies() {
  local object="$1"
  local skip_id="${2:-0}"
  local first=1
  local line dep

  otool -L "$object" | tail -n +2 | while IFS= read -r line; do
    dep="${line#"${line%%[![:space:]]*}"}"
    dep="${dep%% (*}"
    if [[ "$skip_id" == "1" && "$first" == "1" ]]; then
      first=0
      continue
    fi
    first=0
    if [[ -n "$dep" ]]; then
      printf '%s\n' "$dep"
    fi
  done
}

macos_otool_install_name() {
  local object="$1"
  local line dep

  line="$(otool -L "$object" | sed -n '2p')"
  dep="${line#"${line%%[![:space:]]*}"}"
  dep="${dep%% (*}"
  printf '%s\n' "$dep"
}

resolve_macos_library_path() {
  local dep="$1"
  local object="$2"
  local skip_id="${3:-0}"
  local suffix candidate install_name

  case "$dep" in
    @loader_path/*)
      suffix="${dep#@loader_path/}"
      candidate="$(dirname "$object")/$suffix"
      if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi

      if [[ "$skip_id" == "1" ]]; then
        install_name="$(macos_otool_install_name "$object")"
        if [[ "$install_name" == /* ]]; then
          candidate="$(dirname "$install_name")/$suffix"
          if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
          fi
        fi
      fi
      return 1
      ;;
    /*)
      printf '%s\n' "$dep"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

should_bundle_macos_library() {
  local dep="$1"

  case "$dep" in
    @*|/usr/lib/*|/System/Library/*)
      return 1
      ;;
    /*)
      [[ -f "$dep" ]]
      return
      ;;
    *)
      return 1
      ;;
  esac
}

rewrite_macos_library_refs() {
  local object="$1"
  local frameworks_dir="$2"
  local reference_prefix="$3"
  local skip_id="${4:-0}"
  local dep dep_name

  if [[ "$skip_id" == "1" ]]; then
    install_name_tool -id "$reference_prefix/$(basename "$object")" "$object"
  fi

  while IFS= read -r dep; do
    should_bundle_macos_library "$dep" || continue
    dep_name="$(basename "$dep")"
    if [[ -f "$frameworks_dir/$dep_name" ]]; then
      install_name_tool -change "$dep" "$reference_prefix/$dep_name" "$object"
    fi
  done < <(macos_otool_dependencies "$object" "$skip_id")
}

bundle_macos_dylibs() {
  local app_dir="$1"
  local main_exe="$app_dir/Contents/MacOS/$APP_NAME"
  local frameworks_dir="$app_dir/Contents/Frameworks"
  local current dep resolved_dep dep_name dest skip_id dylib
  local -a scan_queue copied

  require_command otool
  require_command install_name_tool

  scan_queue=("$main_exe")
  copied=()

  while ((${#scan_queue[@]} > 0)); do
    current="${scan_queue[0]}"
    scan_queue=("${scan_queue[@]:1}")

    skip_id=0
    if [[ "$current" == "$frameworks_dir/"*.dylib ]]; then
      skip_id=1
    fi

    while IFS= read -r dep; do
      resolved_dep="$(resolve_macos_library_path "$dep" "$current" "$skip_id")" || continue
      should_bundle_macos_library "$resolved_dep" || continue
      dep_name="$(basename "$dep")"
      dest="$frameworks_dir/$dep_name"

      if [[ ! -f "$dest" ]]; then
        mkdir -p "$frameworks_dir"
        echo "[info] bundling macOS dylib $dep_name"
        cp -L "$resolved_dep" "$dest"
        chmod u+w "$dest"
        if command -v codesign >/dev/null 2>&1; then
          codesign --remove-signature "$dest" >/dev/null 2>&1 || true
        fi
        copied+=("$dest")
        scan_queue+=("$dest")
      fi
    done < <(macos_otool_dependencies "$current" "$skip_id")
  done

  if ((${#copied[@]} == 0)); then
    return 0
  fi

  rewrite_macos_library_refs "$main_exe" "$frameworks_dir" "@executable_path/../Frameworks" 0
  for dylib in "${copied[@]}"; do
    rewrite_macos_library_refs "$dylib" "$frameworks_dir" "@loader_path" 1
  done
}

ad_hoc_sign_macos_app() {
  local app_dir="$1"
  local frameworks_dir="$app_dir/Contents/Frameworks"

  require_command codesign
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$app_dir/Contents/MacOS/$APP_NAME"
    xattr -cr "$app_dir"
  fi

  if [[ -d "$frameworks_dir" ]]; then
    while IFS= read -r dylib; do
      codesign --force --sign - "$dylib"
    done < <(find "$frameworks_dir" -type f -name '*.dylib' | sort)
  fi

  codesign --force --sign - "$app_dir/Contents/MacOS/$APP_NAME"
  codesign --force --sign - "$app_dir"
}

sign_macos_app() {
  local app_dir="$1"
  local entitlements_file="$2"
  local frameworks_dir="$app_dir/Contents/Frameworks"
  local nested_sig_args=(--force --timestamp --options runtime --sign "$CODESIGN_IDENTITY")

  require_command codesign
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$app_dir/Contents/MacOS/$APP_NAME"
    xattr -cr "$app_dir"
  fi

  local sig_args=(--force --timestamp --options runtime --sign "$CODESIGN_IDENTITY")
  if [[ -n "$entitlements_file" ]]; then
    sig_args+=(--entitlements "$entitlements_file")
  fi

  if [[ -d "$frameworks_dir" ]]; then
    while IFS= read -r dylib; do
      codesign "${nested_sig_args[@]}" "$dylib"
    done < <(find "$frameworks_dir" -type f -name '*.dylib' | sort)
  fi

  # Sign all nested libraries, then the executable and app bundle.
  codesign "${sig_args[@]}" "$app_dir/Contents/MacOS/$APP_NAME"
  codesign "${sig_args[@]}" "$app_dir"
  codesign --verify --strict --verbose=2 "$app_dir"
}

create_macos_zip() {
  local app_dir="$1"
  local zip_path="$2"
  local label="${3:-macOS zip}"

  require_command ditto
  rm -f "$zip_path"
  ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$app_dir" "$zip_path"
  echo "[ok] $label created at $zip_path"
}

notarize_macos_artifacts() {
  local app_dir="$1"
  local zip_path="$2"

  require_command xcrun
  require_command codesign

  local submit=(xcrun notarytool submit "$zip_path" --wait)

  if [[ -n "$APPLE_NOTARY_KEYCHAIN_PROFILE" ]]; then
    submit+=(--keychain-profile "$APPLE_NOTARY_KEYCHAIN_PROFILE")
  elif [[ -n "$APPLE_NOTARY_APPLE_ID" && -n "$APPLE_NOTARY_PASSWORD" && -n "$APPLE_NOTARY_TEAM_ID" ]]; then
    submit+=(--apple-id "$APPLE_NOTARY_APPLE_ID" --password "$APPLE_NOTARY_PASSWORD" --team-id "$APPLE_NOTARY_TEAM_ID")
  else
    echo "[error] MACOS_NOTARIZE is enabled but no Apple notarization credentials were supplied." >&2
    echo "[error] Set APPLE_NOTARY_KEYCHAIN_PROFILE, or APPLE_NOTARY_APPLE_ID + APPLE_NOTARY_PASSWORD + APPLE_NOTARY_TEAM_ID" >&2
    exit 1
  fi

  "${submit[@]}"
  xcrun stapler staple "$app_dir"
  xcrun stapler validate "$app_dir"
  codesign --verify --deep --strict --verbose=2 "$app_dir"
}

usage() {
  cat <<'USAGE'
Usage: bundling/package.sh [macos|windows|all] <version>

  macos      Package macOS .app bundle into dist/macos/Monocurl.app
  windows    Package Windows installer via Inno Setup (iscc)
  all        Run all supported host actions (macOS + Windows)

Optional env (macOS):
  MACOS_SIGN=1                      Enable codesigning for .app
  CODESIGN_IDENTITY                Required when MACOS_SIGN=1
  CODESIGN_INSTALLER_IDENTITY      Code signing identity for installer artifacts
  CODESIGN_ENTITLEMENTS            Path to entitlement file (default: bundling/templates/macos/Monocurl.entitlements.in)
  MACOS_NOTARIZE=1                  Run notarytool and staple results
  APP_PATH_ENV                      PATH written into app bundle via LSEnvironment (default: current shell PATH)
  APPLE_NOTARY_KEYCHAIN_PROFILE     Keychain profile for notarytool (preferred)
  APPLE_NOTARY_APPLE_ID             Apple ID for notarytool login flow
  APPLE_NOTARY_PASSWORD             Password / app-specific password
  APPLE_NOTARY_TEAM_ID              Team ID for notarytool login flow

Optional env (windows):
  TARGET=<target>                   Override target triple when building
  APP_IDENTIFIER=<id>               Override CFBundleIdentifier
  APP_ID=<guid>                     Override installer AppId (Inno Setup)
  WINDOWS_SIGN_INSTALLER=1          Enable installer signing (signs generated .exe). Legacy alias: MACOS_SIGN_INSTALLER
  CODESIGN_INSTALLER_IDENTITY      Certificate identity for installer signing
USAGE
}

make_macos() {
  local target="${TARGET:-$MACOS_TARGET_DEFAULT}"
  if [[ "$target" != *apple-darwin ]]; then
    echo "[error] TARGET for macOS packaging must be an apple-darwin target (got: $target)" >&2
    exit 1
  fi

  cargo build --package monocurl --release --target "$target"

  local binary="$ROOT_DIR/target/$target/release/$BIN_NAME"
  if [[ ! -f "$binary" ]]; then
    echo "[error] expected binary at $binary" >&2
    exit 1
  fi

  local app_dir="$DIST_DIR/macos/${APP_NAME}.app"
  local info_plist="$app_dir/Contents/Info.plist"
  rm -rf "$app_dir"
  mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

  cp "$binary" "$app_dir/Contents/MacOS/$APP_NAME"
  chmod +x "$app_dir/Contents/MacOS/$APP_NAME"
  make_macos_icon "$app_dir"
  cp -R "$ROOT_DIR/assets" "$app_dir/Contents/Resources/"
  render_template "$TEMPLATE_DIR/macos/Info.plist.in" "$info_plist"
  bundle_macos_dylibs "$app_dir"

  local dist_macos_dir="$DIST_DIR/macos"
  local entitlements_path=""
  if is_true "$MACOS_SIGN" || is_true "$MACOS_NOTARIZE"; then
    if [[ -z "$CODESIGN_IDENTITY" ]]; then
      echo "[error] MACOS_SIGN or MACOS_NOTARIZE requires CODESIGN_IDENTITY" >&2
      exit 1
    fi
    entitlements_path="$(render_macos_entitlements "$dist_macos_dir")"
    sign_macos_app "$app_dir" "$entitlements_path"
  else
    ad_hoc_sign_macos_app "$app_dir"
  fi

  local zip_path="$dist_macos_dir/${APP_NAME}-${VERSION}.zip"

  if is_true "$MACOS_NOTARIZE"; then
    create_macos_zip "$app_dir" "$zip_path" "macOS notarization submission zip"
    notarize_macos_artifacts "$app_dir" "$zip_path"
    if is_true "$MACOS_CREATE_ZIP"; then
      create_macos_zip "$app_dir" "$zip_path" "macOS stapled zip"
    else
      rm -f "$zip_path"
    fi
  elif is_true "$MACOS_CREATE_ZIP"; then
    create_macos_zip "$app_dir" "$zip_path" "macOS zip"
  fi

  echo "[ok] macOS app created at $app_dir"
}

make_windows() {
  if ! command -v iscc >/dev/null 2>&1; then
    echo "[error] iscc (Inno Setup) was not found. Install Inno Setup and add iscc.exe to PATH." >&2
    exit 1
  fi

  local target="${TARGET:-$WIN_TARGET_DEFAULT}"
  if [[ "$target" != *windows* ]]; then
    echo "[error] TARGET for windows packaging should be a windows target (got: $target)" >&2
    exit 1
  fi

  cargo build --package monocurl --release --target "$target"

  local binary_src="$ROOT_DIR/target/$target/release/${BIN_NAME}.exe"
  if [[ ! -f "$binary_src" ]]; then
    echo "[error] expected binary at $binary_src" >&2
    exit 1
  fi

  local stage_dir="$DIST_DIR/windows/staging"
  local iss_rendered="$stage_dir/Monocurl.iss"
  rm -rf "$stage_dir"
  mkdir -p "$stage_dir/assets"
  cp "$binary_src" "$stage_dir/$APP_NAME.exe"
  cp -R "$ROOT_DIR/assets"/* "$stage_dir/assets/"
  make_windows_icon "$stage_dir"

  render_template "$TEMPLATE_DIR/windows/Monocurl.iss.in" "$iss_rendered"
  (cd "$stage_dir" && iscc "/O$DIST_DIR/windows" "$(basename "$iss_rendered")")

  if is_true "$WINDOWS_SIGN_INSTALLER"; then
    require_command signtool
    if [[ -z "$CODESIGN_INSTALLER_IDENTITY" ]]; then
      echo "[error] WINDOWS_SIGN_INSTALLER requires CODESIGN_INSTALLER_IDENTITY" >&2
      exit 1
    fi
    local installer="$(ls "$DIST_DIR/windows"/*.exe 2>/dev/null | head -n 1)"
    if [[ -z "$installer" ]]; then
      echo "[error] expected installer at $DIST_DIR/windows to sign" >&2
      exit 1
    fi
    signtool sign /fd SHA256 /a /n "$CODESIGN_INSTALLER_IDENTITY" "$installer"
    echo "[ok] signed Windows installer: $installer"
  fi

  echo "[ok] Windows installer created in $DIST_DIR/windows"
}

platform="${1:-}"
VERSION="${2:-}"
if [[ -z "${platform}" || -z "${VERSION}" ]]; then
  usage
  exit 1
fi

case "$platform" in
  macos|osx|darwin)
    make_macos
    ;;
  windows|win)
    make_windows
    ;;
  all)
    if [[ "$(uname -s)" == "Darwin" ]]; then
      make_macos
      echo "[skip] windows packaging requires iscc on Windows host"
    else
      make_windows
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
