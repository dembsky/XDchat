#!/bin/bash
# Sign Sparkle XPC Services with sandbox entitlements
# This script runs as a post-build phase

set -e

APP_PATH="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"
SPARKLE_PATH="${APP_PATH}/Contents/Frameworks/Sparkle.framework"
ENTITLEMENTS="${SRCROOT}/XDchat/Resources/SparkleXPC.entitlements"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY}}"

# Check if Sparkle exists
if [ ! -d "$SPARKLE_PATH" ]; then
    echo "Sparkle framework not found, skipping..."
    exit 0
fi

echo "Signing Sparkle components with sandbox entitlements..."

# Sign XPC Services
if [ -d "$SPARKLE_PATH/Versions/B/XPCServices/Installer.xpc" ]; then
    echo "Signing Installer.xpc..."
    codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --options runtime "$SPARKLE_PATH/Versions/B/XPCServices/Installer.xpc"
fi

if [ -d "$SPARKLE_PATH/Versions/B/XPCServices/Downloader.xpc" ]; then
    echo "Signing Downloader.xpc..."
    codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --options runtime "$SPARKLE_PATH/Versions/B/XPCServices/Downloader.xpc"
fi

# Sign Updater.app
if [ -d "$SPARKLE_PATH/Versions/B/Updater.app" ]; then
    echo "Signing Updater.app..."
    codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --options runtime "$SPARKLE_PATH/Versions/B/Updater.app"
fi

# Sign Autoupdate
if [ -f "$SPARKLE_PATH/Versions/B/Autoupdate" ]; then
    echo "Signing Autoupdate..."
    codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --options runtime "$SPARKLE_PATH/Versions/B/Autoupdate"
fi

# Re-sign the framework itself
echo "Re-signing Sparkle.framework..."
codesign --force --sign "$IDENTITY" --options runtime "$SPARKLE_PATH"

echo "Sparkle signing complete!"
