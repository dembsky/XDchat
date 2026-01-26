#!/bin/bash

# XDchat Release Build Script
# Builds, signs, notarizes, and creates DMG

set -e

# Configuration
APP_NAME="XDchat"
TEAM_ID="${TEAM_ID:?Set TEAM_ID environment variable}"
DEVELOPER_ID="${DEVELOPER_ID:?Set DEVELOPER_ID environment variable}"
APPLE_ID="${APPLE_ID:?Set APPLE_ID environment variable}"

# Paths
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/Release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  XDchat Release Build Script${NC}"
echo -e "${GREEN}========================================${NC}"

# Check for app-specific password
if [ -z "$APP_SPECIFIC_PASSWORD" ]; then
    echo -e "${YELLOW}Enter your app-specific password:${NC}"
    read -s APP_SPECIFIC_PASSWORD
    echo ""
fi

# Clean
echo -e "\n${YELLOW}[1/6] Cleaning...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build Release
echo -e "\n${YELLOW}[2/6] Building Release...${NC}"
xcodebuild -project "$PROJECT_DIR/XDchat.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | grep -E "(Compiling|Linking|error:|warning:|\*\*)" || true

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi
echo -e "${GREEN}Build successful${NC}"

# Sign with Developer ID
echo -e "\n${YELLOW}[3/6] Signing with Developer ID...${NC}"
codesign --force --deep --options runtime \
    --sign "$DEVELOPER_ID" \
    --entitlements "$PROJECT_DIR/XDchat/Resources/Entitlements.entitlements" \
    "$APP_PATH"

codesign -vvv --deep --strict "$APP_PATH"
echo -e "${GREEN}Signature valid!${NC}"

# Create ZIP for notarization
echo -e "\n${YELLOW}[4/6] Notarizing...${NC}"
cd "$BUILD_DIR"
ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"

xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait

# Staple
echo -e "\n${YELLOW}[5/6] Stapling...${NC}"
xcrun stapler staple "$APP_PATH"

# Create DMG
echo -e "\n${YELLOW}[6/6] Creating DMG...${NC}"
DMG_TEMP="$BUILD_DIR/dmg_temp"
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

# Cleanup
rm -rf "$DMG_TEMP" "$ZIP_PATH" "$BUILD_DIR/DerivedData"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Build Complete! (Notarized)${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\nDMG: ${GREEN}$DMG_PATH${NC}"
echo -e "Size: $(du -h "$DMG_PATH" | cut -f1)"

open "$BUILD_DIR"
