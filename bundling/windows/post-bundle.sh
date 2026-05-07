#!/usr/bin/env bash
set -euo pipefail

# post-bundle.sh <version> <target>
# Run after: cargo bundle --package monocurl --release --target <target>
# cargo-bundle produces an .msi via the pre-installed WiX toolset.
#
# Signing (optional):
#   CODESIGN_IDENTITY   certificate identity passed to signtool

VERSION="${1:?usage: $0 <version> <target>}"
TARGET="${2:?usage: $0 <version> <target>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE_DIR="$ROOT/target/$TARGET/release/bundle"

mkdir -p "$ROOT/dist/windows"

# ---- .msi (from cargo-bundle via WiX) ---------------------------------------
for msi in "$BUNDLE_DIR"/msi/*.msi; do
    [[ -f "$msi" ]] || continue
    dest="$ROOT/dist/windows/Monocurl-$VERSION-setup.msi"
    cp "$msi" "$dest"

    if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
        signtool sign /fd SHA256 /a /n "$CODESIGN_IDENTITY" "$dest"
    fi

    echo "[ok] $dest"
done
