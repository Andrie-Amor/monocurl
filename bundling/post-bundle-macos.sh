#!/usr/bin/env bash
set -euo pipefail

# post-bundle-macos.sh <version> <target>
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
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/target/$TARGET/release/bundle/osx/Monocurl.app"
EXE="$APP/Contents/MacOS/Monocurl"
FWDIR="$APP/Contents/Frameworks"

[[ -d "$APP" ]] || { echo "[error] app bundle not found: $APP" >&2; exit 1; }

# ---- assets -----------------------------------------------------------------
cp -R "$ROOT/assets" "$APP/Contents/Resources/"

# ---- dylibs -----------------------------------------------------------------
# non-system dylibs required by tectonic's XeTeX engine (Homebrew-installed)
mkdir -p "$FWDIR"

SRCS=()
FNAMES=()

bundle_dylib() {
    local name="$1" libdir="$2"
    for src in "$libdir/$name".*.dylib; do
        [[ -f "$src" ]] || continue
        local fname
        fname="$(basename "$src")"
        cp "$src" "$FWDIR/$fname" && chmod u+w "$FWDIR/$fname"
        codesign --remove-signature "$FWDIR/$fname" 2>/dev/null || true
        install_name_tool -id "@loader_path/$fname" "$FWDIR/$fname"
        install_name_tool -change "$src" "@executable_path/../Frameworks/$fname" "$EXE" 2>/dev/null || true
        SRCS+=("$src")
        FNAMES+=("$fname")
    done
}

bundle_dylib libicudata  "$(brew --prefix icu4c)/lib"
bundle_dylib libicuuc    "$(brew --prefix icu4c)/lib"
bundle_dylib libfreetype "$(brew --prefix freetype)/lib"
bundle_dylib libgraphite2 "$(brew --prefix graphite2)/lib"
bundle_dylib libpng16    "$(brew --prefix libpng)/lib"

# fix cross-references between bundled dylibs
for dylib in "$FWDIR"/*.dylib; do
    for i in "${!SRCS[@]}"; do
        install_name_tool -change "${SRCS[$i]}" "@loader_path/${FNAMES[$i]}" "$dylib" 2>/dev/null || true
    done
done

# ---- sign -------------------------------------------------------------------
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    ENTITLEMENTS="${CODESIGN_ENTITLEMENTS:-$ROOT/bundling/templates/macos/Monocurl.entitlements.in}"
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
DMG="$ROOT/dist/macos/Monocurl-$VERSION.dmg"
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
cp -R "$APP" "$stage/"; ln -s /Applications "$stage/Applications"
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
