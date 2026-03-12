#!/bin/bash
# Tag, build, sign, notarize, and prepare a GitHub release for Cosmodrome.
#
# Usage:
#   ./scripts/release.sh <version> --sign "Developer ID Application: Name (TEAM)"
#   ./scripts/release.sh <version>   # ad-hoc sign (no notarization)
#
# For full notarized release, set environment variables:
#   APPLE_ID       — Apple ID email
#   TEAM_ID        — Apple Developer Team ID
#   APP_PASSWORD   — app-specific password (from appleid.apple.com)
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
SIGN_IDENTITY=""

if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/release.sh <version> [--sign \"Developer ID Application: ...\"]"
    echo "Example: ./scripts/release.sh 1.2.0 --sign \"Developer ID Application: Name (TEAM)\""
    exit 1
fi
shift

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

TAG="v$VERSION"
DMG_PATH="$PROJ_DIR/build/Cosmodrome.dmg"

# Verify clean working tree
if [ -n "$(git -C "$PROJ_DIR" status --porcelain)" ]; then
    echo "Error: Working tree is not clean. Commit or stash changes first."
    exit 1
fi

# Update version in bundle.sh Info.plist
echo "==> Updating version to $VERSION in bundle.sh..."
sed -i '' "s|<string>[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*</string>|<string>${VERSION}</string>|g" "$PROJ_DIR/scripts/bundle.sh"

# Build DMG (pass signing identity and notarization env through)
echo "==> Building DMG..."
BUILD_ARGS=()
if [ -n "$SIGN_IDENTITY" ]; then
    BUILD_ARGS+=(--sign "$SIGN_IDENTITY")

    # Enable notarization if credentials are available
    if [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ]; then
        export NOTARIZE=1
    fi
fi

export CODESIGN_IDENTITY="${SIGN_IDENTITY}"
bash "$PROJ_DIR/scripts/build-dmg.sh" ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}

if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG not found at $DMG_PATH"
    exit 1
fi

# Tag
echo "==> Tagging $TAG..."
git -C "$PROJ_DIR" tag -a "$TAG" -m "Release $VERSION"

echo ""
echo "Release prepared:"
echo "  Tag: $TAG"
echo "  DMG: $DMG_PATH"
echo ""
echo "Next steps:"
echo "  1. Push tag:     git push origin $TAG"
echo "  2. Create release:"
echo "     gh release create $TAG \"$DMG_PATH\" --title \"Cosmodrome $VERSION\" --generate-notes"
