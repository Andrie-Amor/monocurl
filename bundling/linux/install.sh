#!/usr/bin/env sh
set -eu

# Downloads a Monocurl Linux tarball from GitHub releases and installs it into
# ~/.local, matching the app-local layout produced by post-bundle.sh.

main() {
    platform="${MONOCURL_INSTALL_PLATFORM:-$(uname -s)}"
    arch="${MONOCURL_INSTALL_ARCH:-$(uname -m)}"
    version="${MONOCURL_VERSION:-latest}"

    if [ "$platform" != "Linux" ]; then
        echo "Unsupported platform $platform"
        exit 1
    fi

    case "$arch" in
        x86_64 | amd64)
            target="x86_64-unknown-linux-gnu"
            ;;
        aarch64 | arm64)
            target="aarch64-unknown-linux-gnu"
            ;;
        *)
            echo "Unsupported architecture $arch"
            exit 1
            ;;
    esac

    if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
        temp="$(mktemp -d "$TMPDIR/monocurl-XXXXXX")"
    else
        temp="$(mktemp -d "/tmp/monocurl-XXXXXX")"
    fi

    if command -v curl >/dev/null 2>&1; then
        fetch() {
            command curl -fL "$@"
        }
    elif command -v wget >/dev/null 2>&1; then
        fetch() {
            command wget -O- "$@"
        }
    else
        echo "Could not find 'curl' or 'wget' in your path"
        exit 1
    fi

    bundle="$temp/monocurl-linux-$target.tar.gz"

    if [ -n "${MONOCURL_BUNDLE_PATH:-}" ]; then
        cp "$MONOCURL_BUNDLE_PATH" "$bundle"
    else
        if [ -n "${MONOCURL_BUNDLE_URL:-}" ]; then
            url="$MONOCURL_BUNDLE_URL"
        else
            release_json="$temp/release.json"
            if [ "$version" = "latest" ]; then
                release_api="https://api.github.com/repos/monocurl/monocurl/releases/latest"
            else
                tag="$version"
                case "$tag" in
                    v*) ;;
                    *) tag="v$tag" ;;
                esac
                release_api="https://api.github.com/repos/monocurl/monocurl/releases/tags/$tag"
            fi

            fetch "$release_api" > "$release_json"
            arch="${target%%-*}"
            url="$(sed -n "s|.*\"browser_download_url\":[[:space:]]*\"\([^\"]*Monocurl-$arch\.tar\.gz\)\".*|\1|p" "$release_json" | head -n 1)"
            if [ -z "$url" ]; then
                echo "Could not find a Monocurl Linux bundle for $target in release $version"
                exit 1
            fi
        fi

        echo "Downloading Monocurl version: $version"
        fetch "$url" > "$bundle"
    fi

    tar -xzf "$bundle" -C "$temp"

    if [ ! -f "$temp/monocurl.app/bin/monocurl" ]; then
        echo "Downloaded bundle did not contain monocurl.app/bin/monocurl"
        exit 1
    fi

    install_dir="$HOME/.local/monocurl.app"
    rm -rf "$install_dir"
    mkdir -p "$HOME/.local" "$HOME/.local/bin" "$HOME/.local/share/applications"
    mv "$temp/monocurl.app" "$install_dir"
    ln -sf "$install_dir/bin/monocurl" "$HOME/.local/bin/monocurl"

    desktop_src="$install_dir/share/applications/com.enigmadux.monocurl.desktop"
    desktop_dst="$HOME/.local/share/applications/com.enigmadux.monocurl.desktop"
    if [ -f "$desktop_src" ]; then
        cp "$desktop_src" "$desktop_dst"
        sed -i.bak "s|^Exec=.*|Exec=$install_dir/bin/monocurl %F|" "$desktop_dst"
        sed -i.bak "s|^Icon=.*|Icon=$install_dir/share/icons/hicolor/512x512/apps/monocurl.png|" "$desktop_dst"
        rm -f "$desktop_dst.bak"
    fi

    installed="$(command -v monocurl 2>/dev/null || true)"
    if [ "$installed" = "$HOME/.local/bin/monocurl" ]; then
        echo "Monocurl has been installed."
        echo "Run with 'monocurl'"
    else
        echo "To run Monocurl from your terminal, add ~/.local/bin to your PATH."
        echo "Run Monocurl now with '~/.local/bin/monocurl'"
    fi
}

main "$@"
