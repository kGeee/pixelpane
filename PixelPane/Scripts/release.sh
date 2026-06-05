#!/usr/bin/env bash
#
# Pixel Pane release pipeline: archive -> Developer ID sign -> notarize ->
# staple -> DMG. Produces dist/PixelPane-<version>.dmg ready for upload.
#
# One-time setup (after Apple Developer Program enrollment):
#   1. Xcode -> Settings -> Accounts -> Manage Certificates -> "+" ->
#      "Developer ID Application".
#   2. Create an app-specific password at appleid.apple.com, then:
#        xcrun notarytool store-credentials pixelpane-notary \
#          --apple-id <your-apple-id> --team-id <TEAM_ID> --password <app-specific-password>
#
# Usage:
#   ./PixelPane/Scripts/release.sh                 # uses the project's team
#   RELEASE_TEAM_ID=ABC123 ./PixelPane/Scripts/release.sh   # override team
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROJECT="${PROJECT_ROOT}/PixelPane/PixelPane.xcodeproj"
SCHEME="PixelPane"
NOTARY_PROFILE="${NOTARY_PROFILE:-pixelpane-notary}"
DIST_DIR="${PROJECT_ROOT}/dist"
BUILD_DIR="${PROJECT_ROOT}/build/release"
ARCHIVE_PATH="${BUILD_DIR}/PixelPane.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

step "Preflight"
TEAM_ID="${RELEASE_TEAM_ID:-$(sed -n 's/.*DEVELOPMENT_TEAM = \([A-Z0-9]*\);.*/\1/p' "${PROJECT}/project.pbxproj" | head -1)}"
[ -n "${TEAM_ID}" ] || fail "No team ID found. Set RELEASE_TEAM_ID or DEVELOPMENT_TEAM in the project."
echo "Team: ${TEAM_ID}"

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || fail "No 'Developer ID Application' certificate in the keychain. Create one in Xcode -> Settings -> Accounts -> Manage Certificates."

xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1 \
  || fail "Notary profile '${NOTARY_PROFILE}' not found. Run: xcrun notarytool store-credentials ${NOTARY_PROFILE} --apple-id <id> --team-id ${TEAM_ID} --password <app-specific-password>"

VERSION="$(sed -n 's/.*MARKETING_VERSION = \([0-9.]*\);.*/\1/p' "${PROJECT}/project.pbxproj" | head -1)"
[ -n "${VERSION}" ] || fail "Could not read MARKETING_VERSION."
echo "Version: ${VERSION}"

step "Clean"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

step "Archive (Release, Developer ID)"
xcodebuild archive \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=macOS" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_STYLE=Automatic \
  | grep -E "error|warning: code sign|ARCHIVE" || true
[ -d "${ARCHIVE_PATH}" ] || fail "Archive failed."

step "Export with Developer ID"
EXPORT_OPTIONS="${BUILD_DIR}/exportOptions.plist"
cat > "${EXPORT_OPTIONS}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>${TEAM_ID}</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}" \
  -exportPath "${EXPORT_PATH}" \
  | grep -E "error|EXPORT" || true
APP_PATH="${EXPORT_PATH}/PixelPane.app"
[ -d "${APP_PATH}" ] || fail "Export failed."

step "Notarize"
NOTARIZE_ZIP="${BUILD_DIR}/PixelPane-notarize.zip"
ditto -c -k --keepParent "${APP_PATH}" "${NOTARIZE_ZIP}"
xcrun notarytool submit "${NOTARIZE_ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait \
  || fail "Notarization failed. Check: xcrun notarytool log <submission-id> --keychain-profile ${NOTARY_PROFILE}"

step "Staple"
xcrun stapler staple "${APP_PATH}"

step "Verify Gatekeeper acceptance"
spctl --assess --type execute --verbose=2 "${APP_PATH}" || fail "Gatekeeper rejected the stapled app."

step "Package DMG"
DMG_PATH="${DIST_DIR}/PixelPane-${VERSION}.dmg"
rm -f "${DMG_PATH}"
DMG_STAGING="${BUILD_DIR}/dmg"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_PATH}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"
hdiutil create -volname "Pixel Pane" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_PATH}"

step "Generate Sparkle appcast"
GENERATE_APPCAST="$(find "${HOME}/Library/Developer/Xcode/DerivedData" -path "*artifacts*parkle*" -name "generate_appcast" 2>/dev/null | head -1)"
if [ -n "${GENERATE_APPCAST}" ]; then
  # Signs with the EdDSA private key in the login keychain (created once via
  # Sparkle's generate_keys). Produces/updates dist/appcast.xml.
  "${GENERATE_APPCAST}" \
    --download-url-prefix "https://github.com/snehith01001110/pixelpane-releases/releases/latest/download/" \
    "${DIST_DIR}"
else
  echo "warning: generate_appcast not found (resolve Swift packages first); skipping appcast."
fi

step "Done"
echo "Release artifact: ${DMG_PATH}"
echo "Publish to the PUBLIC releases repo (source repo is private):"
echo "  gh release create v${VERSION} \"${DMG_PATH}\" \"${DIST_DIR}/appcast.xml\" --repo snehith01001110/pixelpane-releases"
echo "(The app's update feed reads appcast.xml from that repo's latest release.)"
