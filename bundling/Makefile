# Bundling entry points
# Usage:
#   make -C bundling package-macos VERSION=<semver>
#   make -C bundling package-windows VERSION=<semver>  (not yet implemented)
#
# macOS signing/notary (all optional — omit for ad-hoc signing):
#   make -C bundling package-macos VERSION=0.1.0 \
#     CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#     APPLE_NOTARY_KEYCHAIN_PROFILE=notarytool-profile
#
#   or with explicit credentials instead of keychain profile:
#     APPLE_NOTARY_APPLE_ID=you@example.com \
#     APPLE_NOTARY_PASSWORD=app-specific-password \
#     APPLE_NOTARY_TEAM_ID=TEAMID

.PHONY: help package-macos package-windows

define require-version
  $(if $(VERSION),,$(error VERSION is required. Example: make -C bundling package-macos VERSION=0.1.0))
endef

help:
	@echo "Monocurl bundling targets:"
	@echo "  make -C bundling package-macos VERSION=<version>"
	@echo "  make -C bundling package-windows VERSION=<version>  (not yet implemented)"
	@echo
	@echo "macOS env vars (all optional):"
	@echo '  CODESIGN_IDENTITY="Developer ID Application: ... (TEAMID)"'
	@echo "  APPLE_NOTARY_KEYCHAIN_PROFILE=..."
	@echo "  APPLE_NOTARY_APPLE_ID=..."
	@echo "  APPLE_NOTARY_PASSWORD=..."
	@echo "  APPLE_NOTARY_TEAM_ID=..."

package-macos:
	$(call require-version)
	bash bundle-macos.sh $(VERSION) ../target/aarch64-apple-darwin/release/monocurl

package-windows:
	@echo "[error] Windows bundling not yet implemented (bundle-windows.sh)" >&2
	@exit 1
