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
    "$APP/share/applications" \
    "$APP/share/icons/hicolor/512x512/apps"

cp "$BINARY" "$APP/bin/monocurl"
cp -R "$ROOT/assets" "$APP/assets"
find "$APP/assets" -name .DS_Store -delete
cp "$ROOT/assets/AppIcon.appiconset/monocurl-512.png" \
    "$APP/share/icons/hicolor/512x512/apps/monocurl.png"

cat > "$APP/share/applications/com.enigmadux.monocurl.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Monocurl
Comment=Mathematical animation editor
Exec=monocurl %F
Icon=monocurl
Terminal=false
Categories=Education;
MimeType=text/x-monocurl-scene;text/x-monocurl-library;
EOF

TARBALL="$ROOT/dist/linux/Monocurl-$VERSION-$TARGET.tar.gz"
tar -czf "$TARBALL" -C "$stage" monocurl.app
echo "[ok] $TARBALL"
