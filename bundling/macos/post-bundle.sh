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
perl -e '
use strict;
use warnings;
my ($src, $out) = @ARGV;
my @entries = (
    ["icp4", "monocurl-16.png"],
    ["ic11", "monocurl-32.png"],
    ["icp5", "monocurl-32.png"],
    ["ic12", "monocurl-64.png"],
    ["ic07", "monocurl-128.png"],
    ["ic13", "monocurl-256.png"],
    ["ic08", "monocurl-256.png"],
    ["ic14", "monocurl-512.png"],
    ["ic09", "monocurl-512.png"],
    ["ic10", "monocurl-1024.png"],
);
my $payload = "";
for my $entry (@entries) {
    open my $fh, "<:raw", "$src/$entry->[1]" or die "open $entry->[1]: $!";
    local $/;
    my $data = <$fh>;
    $payload .= $entry->[0] . pack("N", length($data) + 8) . $data;
}
open my $out_fh, ">:raw", $out or die "open $out: $!";
print {$out_fh} "icns", pack("N", length($payload) + 8), $payload;
' "$SRC" "$ICON"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $ICON_FILE" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $ICON_FILE" "$APP/Contents/Info.plist"

# ---- dylibs -----------------------------------------------------------------
# Homebrew dylibs the binary links against (verified via otool -L).
# Update names here if a major-version bump changes the soname.
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

# fix cross-references between bundled dylibs
for dylib in "$FWDIR"/*.dylib; do
    for i in "${!SRCS[@]}"; do
        install_name_tool -change "${SRCS[$i]}" "@loader_path/${FNAMES[$i]}" "$dylib" 2>/dev/null || true
    done
done

# ---- sign -------------------------------------------------------------------
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    ENTITLEMENTS="${CODESIGN_ENTITLEMENTS:-$ROOT/bundling/macos/Monocurl.entitlements}"
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
