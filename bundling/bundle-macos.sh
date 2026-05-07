#!/usr/bin/env bash
set -euo pipefail

# usage: bundle-macos.sh <version> <binary>
#        outputs dist/macos/Monocurl-<version>.dmg
#
# signing (all optional — omit for ad-hoc signing):
#   CODESIGN_IDENTITY           developer id cert identity
#   CODESIGN_ENTITLEMENTS       path to entitlements (default: bundling/templates/macos/Monocurl.entitlements.in)
#   APPLE_NOTARY_KEYCHAIN_PROFILE   keychain profile for notarytool (preferred for local use)
#   APPLE_NOTARY_APPLE_ID       \
#   APPLE_NOTARY_PASSWORD        > all three required when not using keychain profile
#   APPLE_NOTARY_TEAM_ID        /

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist/macos"
APP_NAME="Monocurl"
BUNDLE_ID="${APP_IDENTIFIER:-com.enigmadux.monocurl}"

VERSION="${1:?usage: $0 <version> <binary>}"
BINARY="${2:?usage: $0 <version> <binary>}"
[[ -f "$BINARY" ]] || { echo "[error] binary not found: $BINARY" >&2; exit 1; }

APP="$DIST/$APP_NAME.app"
FWDIR="$APP/Contents/Frameworks"
EXE="$APP/Contents/MacOS/$APP_NAME"

# ---- populate bundle --------------------------------------------------------

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$FWDIR"

cp "$BINARY" "$EXE" && chmod +x "$EXE"
cp -R "$ROOT/assets" "$APP/Contents/Resources/"
python3 "$ROOT/bundling/scripts/make_windows_icon.py" \
    "$ROOT/assets/AppIcon.appiconset/monocurl-1024-1024.png" \
    "$APP/Contents/Resources/$APP_NAME.icns"
sed -e "s|__APP_NAME__|$APP_NAME|g" \
    -e "s|__APP_IDENTIFIER__|$BUNDLE_ID|g" \
    -e "s|__APP_ICON_FILE_BASENAME__|$APP_NAME|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__PATH__|/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin|g" \
    "$ROOT/bundling/templates/macos/Info.plist.in" > "$APP/Contents/Info.plist"

# ---- bundle non-system dylibs -----------------------------------------------

_deps()    { otool -L "$1" | tail -n +2 | awk '{print $1}'; }
_resolve() {
    case "$1" in
        @loader_path/*) echo "$(dirname "$2")/${1#@loader_path/}" ;;
        /*)             echo "$1" ;;
    esac
}
_keep()    {
    case "$1" in
        ''|@*|/usr/lib/*|/System/Library/*) return 1 ;;
        /*) [[ -f "$1" ]] ;;
        *) return 1 ;;
    esac
}

declare -a queue=("$EXE") copied=()

while ((${#queue[@]} > 0)); do
    cur="${queue[0]}"; queue=("${queue[@]:1}")
    while IFS= read -r dep; do
        resolved="$(_resolve "$dep" "$cur")"
        _keep "$resolved" || continue
        name="$(basename "$dep")"
        dest="$FWDIR/$name"
        [[ -f "$dest" ]] && continue
        echo "[dylib] bundling $name"
        cp -L "$resolved" "$dest" && chmod u+w "$dest"
        codesign --remove-signature "$dest" 2>/dev/null || true
        copied+=("$dest"); queue+=("$dest")
    done < <(_deps "$cur")
done

if ((${#copied[@]} > 0)); then
    while IFS= read -r dep; do
        _keep "$dep" || continue
        name="$(basename "$dep")"
        [[ -f "$FWDIR/$name" ]] && \
            install_name_tool -change "$dep" "@executable_path/../Frameworks/$name" "$EXE"
    done < <(_deps "$EXE")
    for dylib in "${copied[@]}"; do
        install_name_tool -id "@loader_path/$(basename "$dylib")" "$dylib"
        while IFS= read -r dep; do
            _keep "$dep" || continue
            name="$(basename "$dep")"
            [[ -f "$FWDIR/$name" ]] && \
                install_name_tool -change "$dep" "@loader_path/$name" "$dylib"
        done < <(_deps "$dylib")
    done
fi

# ---- sign -------------------------------------------------------------------

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    ENTITLEMENTS="${CODESIGN_ENTITLEMENTS:-$ROOT/bundling/templates/macos/Monocurl.entitlements.in}"
    xattr -cr "$APP"
    find "$FWDIR" -name '*.dylib' -print0 | xargs -0 -I{} \
        codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" {}
    codesign --force --timestamp --options runtime \
        --entitlements "$ENTITLEMENTS" --sign "$CODESIGN_IDENTITY" "$EXE"
    codesign --force --timestamp --options runtime \
        --entitlements "$ENTITLEMENTS" --sign "$CODESIGN_IDENTITY" "$APP"
    codesign --verify --strict "$APP"
else
    xattr -cr "$APP" 2>/dev/null || true
    find "$FWDIR" -name '*.dylib' -print0 | xargs -0 -I{} codesign --force --sign - {}
    codesign --force --sign - "$APP"
fi

# ---- dmg --------------------------------------------------------------------

DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

# ---- notarize ---------------------------------------------------------------

if [[ -n "${APPLE_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --wait \
        --keychain-profile "$APPLE_NOTARY_KEYCHAIN_PROFILE"
    xcrun stapler staple "$DMG"
elif [[ -n "${APPLE_NOTARY_APPLE_ID:-}" && -n "${APPLE_NOTARY_PASSWORD:-}" && -n "${APPLE_NOTARY_TEAM_ID:-}" ]]; then
    xcrun notarytool submit "$DMG" --wait \
        --apple-id "$APPLE_NOTARY_APPLE_ID" \
        --password "$APPLE_NOTARY_PASSWORD" \
        --team-id "$APPLE_NOTARY_TEAM_ID"
    xcrun stapler staple "$DMG"
fi

echo "[ok] $DMG"
