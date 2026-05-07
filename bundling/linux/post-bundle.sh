#!/usr/bin/env bash
set -euo pipefail

# post-bundle.sh <version> <target>
# Run after: cargo bundle --package monocurl --release --target <target>
# Produces a .deb (from cargo-bundle) and a .tar.gz (for non-Debian distros).

VERSION="${1:?usage: $0 <version> <target>}"
TARGET="${2:?usage: $0 <version> <target>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE_DIR="$ROOT/target/$TARGET/release/bundle"
BINARY="$ROOT/target/$TARGET/release/monocurl"

[[ -f "$BINARY" ]] || { echo "[error] binary not found: $BINARY" >&2; exit 1; }

mkdir -p "$ROOT/dist/linux"

# ---- .deb (from cargo-bundle) -----------------------------------------------
for deb in "$BUNDLE_DIR"/deb/*.deb; do
    [[ -f "$deb" ]] || continue
    dest="$ROOT/dist/linux/Monocurl-$VERSION.deb"
    cp "$deb" "$dest"
    echo "[ok] $dest"
done

# ---- .tar.gz (for non-Debian distros) ---------------------------------------
# assets must sit next to the binary so the runtime path check finds them
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/monocurl"
cp "$BINARY" "$stage/monocurl/monocurl"
cp -R "$ROOT/assets" "$stage/monocurl/assets"

TARBALL="$ROOT/dist/linux/Monocurl-$VERSION-$TARGET.tar.gz"
tar -czf "$TARBALL" -C "$stage" monocurl
echo "[ok] $TARBALL"
