#!/usr/bin/env bash
set -euo pipefail

# post-bundle.sh <version> <target>
# Run after: cargo build --package monocurl --release --target <target>
# Produces the installer-ready Linux .tar.gz used by install.sh.

VERSION="${1:?usage: $0 <version> <target>}"
TARGET="${2:?usage: $0 <version> <target>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BINARY="$ROOT/target/$TARGET/release/monocurl"

[[ -f "$BINARY" ]] || { echo "[error] binary not found: $BINARY" >&2; exit 1; }

mkdir -p "$ROOT/dist/linux"

# ---- .tar.gz ----------------------------------------------------------------
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
APP="$stage/monocurl.app"
mkdir -p \
    "$APP/bin" \
    "$APP/lib" \
    "$APP/share/applications" \
    "$APP/share/icons/hicolor/512x512/apps"

cp "$BINARY" "$APP/bin/monocurl"
cp -R "$ROOT/assets" "$APP/assets"
find "$APP/assets" -name .DS_Store -delete
cp "$ROOT/assets/AppIcon.appiconset/monocurl-512.png" \
    "$APP/share/icons/hicolor/512x512/apps/monocurl.png"
cp "$ROOT/bundling/linux/com.enigmadux.monocurl.desktop" \
    "$APP/share/applications/com.enigmadux.monocurl.desktop"

copy_runtime_lib() {
    local name="$1"
    local source
    local dest="$APP/lib/$name"

    source="$(ldconfig -p | awk -v name="$name" '$1 == name { print $NF; exit }')"
    [[ -n "$source" && -f "$source" ]] || { echo "[error] runtime library not found: $name" >&2; exit 1; }
    cp -L "$source" "$dest"
}

# bundled sonames, like the macos homebrew dylib list
copy_runtime_lib libicudata.so.70
copy_runtime_lib libicui18n.so.70
copy_runtime_lib libicuuc.so.70
copy_runtime_lib libfreetype.so.6
copy_runtime_lib libgraphite2.so.3
copy_runtime_lib libpng16.so.16
copy_runtime_lib libfontconfig.so.1
copy_runtime_lib libexpat.so.1
copy_runtime_lib libbrotlidec.so.1
copy_runtime_lib libbrotlicommon.so.1
copy_runtime_lib libxcb.so.1
copy_runtime_lib libxcb-xkb.so.1
copy_runtime_lib libxkbcommon.so.0
copy_runtime_lib libxkbcommon-x11.so.0
copy_runtime_lib libXau.so.6
copy_runtime_lib libXdmcp.so.6
copy_runtime_lib libbsd.so.0
copy_runtime_lib libmd.so.0

if command -v patchelf >/dev/null 2>&1; then
    patchelf --set-rpath '$ORIGIN/../lib' "$APP/bin/monocurl"
    for lib in "$APP/lib"/*.so*; do
        [[ -f "$lib" ]] && patchelf --set-rpath '$ORIGIN' "$lib"
    done
else
    echo "[warn] patchelf not found; bundled Linux libraries may not be discovered at runtime" >&2
fi

TARBALL="$ROOT/dist/linux/Monocurl-${TARGET%%-*}.tar.gz"
tar -czf "$TARBALL" -C "$stage" monocurl.app
echo "[ok] $TARBALL"
