#!/bin/bash
# Builds a universal Notchella release, packages it as a DMG, signs it for Sparkle,
# and updates the website's download + appcast.
#
# Usage: scripts/release.sh <version> [release-notes.html]
#   scripts/release.sh 1.1
#   scripts/release.sh 1.1 notes/1.1.html
#
# Afterwards, commit and deploy the website repo (the script prints the paths it changed).
#
# Env:
#   NOTCHELLA_WEB   path to the website repo (default: ~/Documents/web/notchella_web)
#   NOTARY_PROFILE  `xcrun notarytool store-credentials` profile name (default: notchella).
#   DEVELOPER_ID    SHA-1 of the signing certificate (default: the Developer ID that expires last).
#
# With a "Developer ID Application" certificate in the keychain, the app is signed with it
# and the DMG is notarized and stapled, so users get no Gatekeeper warning. Without one,
# it falls back to the Xcode signing identity (users must click "Open Anyway" once).
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version> [release-notes.html]}"
NOTES="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="${NOTCHELLA_WEB:-$HOME/Documents/web/notchella_web}"
SITE="https://notchella.kellydanielo.com"
PBXPROJ="$ROOT/notchappp.xcodeproj/project.pbxproj"
BUILD="$ROOT/build"
DERIVED="$BUILD/DerivedData"
RELEASES="$WEB/public/downloads/releases"
ENTITLEMENTS="$ROOT/Config/Notchella.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-notchella}"
# Several Developer ID certificates can share a name, so pick the valid one that expires last
# and sign by its SHA-1 hash (signing by name fails when it's ambiguous).
latest_developer_id() {
  local best="" best_end=0 hash end
  for hash in $(security find-identity -v -p codesigning | awk '/"Developer ID Application:/ {print $2}'); do
    end=$(security find-certificate -a -Z -p -c "Developer ID Application" \
      | awk -v h="$hash" '/^SHA-1 hash:/ {on = ($3 == h)} on' \
      | openssl x509 -noout -enddate | cut -d= -f2)
    end=$(date -j -f "%b %e %T %Y %Z" "$end" +%s)
    if (( end > best_end )); then best="$hash"; best_end=$end; fi
  done
  echo "$best"
}
DEVELOPER_ID="${DEVELOPER_ID:-$(latest_developer_id)}"

if [[ -n "$DEVELOPER_ID" ]]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
    echo "Found a Developer ID certificate but no notarytool profile \"$NOTARY_PROFILE\". Run once:"
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <email> --team-id <TEAM> --password <app-specific password>"
    exit 1
  }
else
  echo "⚠︎ No Developer ID Application certificate: building without notarization."
fi

[[ -d "$WEB/public" ]] || { echo "Website repo not found at $WEB (set NOTCHELLA_WEB)"; exit 1; }
[[ -z "$NOTES" || -f "$NOTES" ]] || { echo "Release notes not found: $NOTES"; exit 1; }

# Sparkle compares CFBundleVersion, so it must go up every release.
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$PBXPROJ" | sed -E 's/[^0-9]*([0-9]+).*/\1/')
BUILD_NUMBER=$((CURRENT_BUILD + 1))
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PBXPROJ"
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
echo "▸ Notchella $VERSION (build $BUILD_NUMBER)"

echo "▸ Building universal Release…"
xcodebuild -project "$ROOT/notchappp.xcodeproj" -scheme notchappp -configuration Release \
  -derivedDataPath "$DERIVED" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet

SPARKLE_BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
STAGE="$BUILD/stage"
APP="$STAGE/Notchella.app"
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$DERIVED/Build/Products/Release/notchappp.app" "$APP"
ln -s /Applications "$STAGE/Applications"

if [[ -n "$DEVELOPER_ID" ]]; then
  echo "▸ Signing with Developer ID $DEVELOPER_ID…"
  # Inside-out, as Sparkle's docs describe: every nested helper needs the hardened runtime and a timestamp.
  sign() { codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$@"; }
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  sign "$SPARKLE/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
  sign "$SPARKLE/Autoupdate"
  sign "$SPARKLE/Updater.app"
  sign "$APP/Contents/Frameworks/Sparkle.framework"
  sign --entitlements "$ENTITLEMENTS" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "  $(lipo -archs "$APP/Contents/MacOS/notchappp")"

echo "▸ Packaging DMG…"
mkdir -p "$RELEASES"
DMG="$RELEASES/Notchella-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname Notchella -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null 2>&1

if [[ -n "$DEVELOPER_ID" ]]; then
  echo "▸ Notarizing (usually a few minutes)…"
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

[[ -n "$NOTES" ]] && cp "$NOTES" "$RELEASES/Notchella-$VERSION.${NOTES##*.}"

echo "▸ Signing and writing appcast…"
# Signs with the EdDSA key in the login keychain (created once with Sparkle's generate_keys).
"$SPARKLE_BIN/generate_appcast" "$RELEASES" \
  --download-url-prefix "$SITE/downloads/releases/" \
  --link "$SITE" \
  --maximum-deltas 0 \
  -o "$WEB/public/appcast.xml"

# The site's Download button always points at the latest build.
cp "$DMG" "$WEB/public/downloads/Notchella.dmg"
SIZE_MB=$(du -k "$DMG" | awk '{printf "%.1f", $1 / 1024}')
cat > "$WEB/app/release.json" <<JSON
{ "version": "$VERSION", "build": $BUILD_NUMBER, "sizeMB": "$SIZE_MB" }
JSON

echo
echo "✓ Released Notchella $VERSION ($SIZE_MB MB)"
echo "  Changed in $WEB:"
echo "    public/downloads/Notchella.dmg"
echo "    public/downloads/releases/Notchella-$VERSION.dmg"
echo "    public/appcast.xml"
echo "    app/release.json"
echo "  Next: commit the version bump here, then commit and deploy the website."
