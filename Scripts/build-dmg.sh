#!/bin/bash
# Build Cosmodrome.app and package as a DMG.
#
# Usage:
#   ./scripts/build-dmg.sh                     # ad-hoc sign (local dev)
#   ./scripts/build-dmg.sh --sign "Developer ID Application: Name (TEAM)"
#   ./scripts/build-dmg.sh --skip-build        # skip swift build, just package
#
# Environment variables (for CI):
#   CODESIGN_IDENTITY  — signing identity (overrides --sign)
#   NOTARIZE           — set to "1" to notarize after packaging
#   APPLE_ID           — Apple ID email for notarization
#   TEAM_ID            — Apple Developer Team ID
#   APP_PASSWORD       — app-specific password for notarization
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Cosmodrome"
BUILD_DIR="$PROJ_DIR/build"
BUNDLE_DIR="$BUILD_DIR/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
DMG_TEMP="$BUILD_DIR/dmg-staging"

# Parse arguments
SKIP_BUILD=false
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
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

# Step 1: Build the .app bundle
if [ "$SKIP_BUILD" = false ]; then
    echo "==> Building Cosmodrome.app..."
    bash "$PROJ_DIR/scripts/bundle.sh"
fi

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "Error: $BUNDLE_DIR not found. Run scripts/bundle.sh first."
    exit 1
fi

# Step 2: Code sign the app
# Each binary inside the bundle must be signed individually with
# hardened runtime + timestamp before signing the bundle itself.
if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Signing with Developer ID: $SIGN_IDENTITY"

    # Sign each embedded binary first (inside-out)
    for binary in "$BUNDLE_DIR/Contents/MacOS/"*; do
        echo "    Signing $(basename "$binary")..."
        codesign --force --options runtime --sign "$SIGN_IDENTITY" \
            --timestamp \
            "$binary"
    done

    # Sign the bundle (verifies nested signatures)
    codesign --force --options runtime --sign "$SIGN_IDENTITY" \
        --timestamp \
        "$BUNDLE_DIR"
else
    echo "==> Signing (ad-hoc, local dev only)..."
    codesign --force --deep --sign - "$BUNDLE_DIR"
fi

# Step 3: Create DMG staging area
echo "==> Creating DMG..."
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -R "$BUNDLE_DIR" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

# Step 4: Create DMG
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_TEMP"

# Step 5: Sign the DMG itself (if using Developer ID)
if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Signing DMG..."
    codesign --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

# Step 6: Notarize (if requested)
# Supports two modes:
#   a) Keychain profile (local): NOTARY_PROFILE env var
#   b) Explicit credentials (CI): APPLE_ID + TEAM_ID + APP_PASSWORD env vars
if [ "${NOTARIZE:-}" = "1" ]; then
    echo "==> Submitting for notarization..."
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait
    elif [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ]; then
        xcrun notarytool submit "$DMG_PATH" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APP_PASSWORD" \
            --wait
    else
        echo "Error: NOTARIZE=1 but no credentials provided."
        echo "Set NOTARY_PROFILE for keychain, or APPLE_ID + TEAM_ID + APP_PASSWORD."
        exit 1
    fi

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
fi

echo ""
echo "DMG created: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"

if [ -z "$SIGN_IDENTITY" ]; then
    echo ""
    echo "Note: ad-hoc signed (local dev only). For distribution, use:"
    echo "  ./scripts/build-dmg.sh --sign \"Developer ID Application: Your Name (TEAMID)\""
fi
