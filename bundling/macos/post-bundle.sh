#!/usr/bin/env bash
set -euo pipefail

# post-bundle.sh <version> <target>
# Run after: cargo bundle --package monocurl --release --target <target>
# Handles the parts cargo-bundle doesn't: assets, dylibs, signing, DMG, notarization.
#
# Signing (all optional — omit for ad-hoc signing):
#   CODESIGN_IDENTITY               developer id cert identity
#   CODESIGN_ENTITLEMENTS           path to entitlements file
#   APPLE_NOTARY_KEYCHAIN_PROFILE   keychain profile (preferred for local use)
#   APPLE_NOTARY_APPLE_ID       \
#   APPLE_NOTARY_PASSWORD        >  all three required when not using keychain profile
#   APPLE_NOTARY_TEAM_ID        /

VERSION="${1:?usage: $0 <version> <target>}"
TARGET="${2:?usage: $0 <version> <target>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/target/$TARGET/release/bundle/osx/Monocurl.app"
FWDIR="$APP/Contents/Frameworks"

[[ -d "$APP" ]] || { echo "[error] app bundle not found: $APP" >&2; exit 1; }
EXE_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist")"
EXE="$APP/Contents/MacOS/$EXE_NAME"
[[ -f "$EXE" ]] || { echo "[error] app executable not found: $EXE" >&2; exit 1; }

# ---- assets -----------------------------------------------------------------
mkdir -p "$APP/Contents/Resources"
rm -rf "$APP/Contents/Resources/assets"
rsync -a --exclude .DS_Store "$ROOT/assets/" "$APP/Contents/Resources/assets/"

# ---- icns -------------------------------------------------------------------
SRC="$ROOT/assets/AppIcon.appiconset"
ICON_FILE="AppIcon.icns"
ICON="$APP/Contents/Resources/$ICON_FILE"
perl "$ROOT/bundling/macos/make_icns.pl" "$SRC" "$ICON"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $ICON_FILE" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $ICON_FILE" "$APP/Contents/Info.plist"

# ---- dylibs -----------------------------------------------------------------
# graphite2/freetype/libpng are pinned by soname; icu is discovered via otool
# since its version number changes frequently with homebrew updates.
rm -rf "$FWDIR" && mkdir -p "$FWDIR"

SRCS=()
FNAMES=()

bundle_dylib() {
    local src="$1"
    local fname; fname="$(basename "$src")"
    [[ -f "$src" ]] || { echo "[warn] dylib not found: $src" >&2; return; }
    cp "$src" "$FWDIR/$fname" && chmod u+w "$FWDIR/$fname"
    codesign --remove-signature "$FWDIR/$fname" 2>/dev/null || true
    install_name_tool -id "@loader_path/$fname" "$FWDIR/$fname"
    install_name_tool -change "$src" "@executable_path/../Frameworks/$fname" "$EXE" 2>/dev/null || true
    SRCS+=("$src")
    FNAMES+=("$fname")
}

bundle_dylib "$(brew --prefix graphite2)/lib/libgraphite2.3.dylib"
bundle_dylib "$(brew --prefix freetype)/lib/libfreetype.6.dylib"
bundle_dylib "$(brew --prefix libpng)/lib/libpng16.16.dylib"

# icu version varies with homebrew; discover the exact sonames from the linked binary
icu_dylib() { otool -L "$EXE" | awk 'NR>1{print $1}' | grep "$1" | head -1; }
for _icu in libicudata libicuuc libicui18n; do
    _src="$(icu_dylib "$_icu")"
    [[ -n "$_src" ]] && bundle_dylib "$_src"
done
unset _icu _src

# fix cross-references between bundled dylibs
for dylib in "$FWDIR"/*.dylib; do
    for i in "${!SRCS[@]}"; do
        install_name_tool -change "${SRCS[$i]}" "@loader_path/${FNAMES[$i]}" "$dylib" 2>/dev/null || true
    done
done

# ---- sign -------------------------------------------------------------------
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    ENTITLEMENTS="${CODESIGN_ENTITLEMENTS:-$ROOT/bundling/macos/Monocurl.entitlements}"
    if ! security find-identity -v -p codesigning | grep -F "$CODESIGN_IDENTITY" >/dev/null; then
        echo "[error] codesign identity not found in keychain: $CODESIGN_IDENTITY" >&2
        echo "[error] set MACOS_CERTIFICATE_P12 and MACOS_CERTIFICATE_PASSWORD, or clear CODESIGN_IDENTITY" >&2
        security find-identity -v -p codesigning >&2 || true
        exit 1
    fi
    xattr -cr "$APP"
    find "$FWDIR" -name '*.dylib' -print0 \
        | xargs -0 -I{} codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" {}
    codesign --force --timestamp --options runtime \
        --entitlements "$ENTITLEMENTS" --sign "$CODESIGN_IDENTITY" "$APP"
    codesign --verify --strict "$APP"
else
    xattr -cr "$APP" 2>/dev/null || true
    find "$FWDIR" -name '*.dylib' -print0 | xargs -0 -I{} codesign --force --sign - {}
    codesign --force --sign - "$APP"
fi

# ---- DMG --------------------------------------------------------------------
mkdir -p "$ROOT/dist/macos"
DMG="$ROOT/dist/macos/Monocurl-macos-${TARGET%%-*}.dmg"
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
ditto --noextattr --norsrc "$APP" "$stage/Monocurl.app"; ln -s /Applications "$stage/Applications"

hdiutil create -volname Monocurl -srcfolder "$stage" -ov -format UDZO "$DMG"

# ---- notarize ---------------------------------------------------------------
if [[ -n "${APPLE_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --wait --keychain-profile "$APPLE_NOTARY_KEYCHAIN_PROFILE"
    xcrun stapler staple "$DMG"
elif [[ -n "${APPLE_NOTARY_APPLE_ID:-}" && -n "${APPLE_NOTARY_PASSWORD:-}" && -n "${APPLE_NOTARY_TEAM_ID:-}" ]]; then
    xcrun notarytool submit "$DMG" --wait \
        --apple-id "$APPLE_NOTARY_APPLE_ID" \
        --password "$APPLE_NOTARY_PASSWORD" \
        --team-id "$APPLE_NOTARY_TEAM_ID"
    xcrun stapler staple "$DMG"
fi

echo "[ok] $DMG"
