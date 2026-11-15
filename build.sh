#!/bin/bash
# Release build: Developer ID signing + notarization + Sparkle appcast.
#
# Usage: ./build.sh "Release notes (HTML or plain text)"
#
# Prerequisites (one-time):
#   - "Developer ID Application" certificate in the login keychain
#   - notarytool profile:  xcrun notarytool store-credentials MTMR --apple-id <id> --team-id <team>
#   - npm i -g create-dmg
#   - Sparkle 2.x tools (bin/sign_update) at $SPARKLE_BIN, EdDSA key in the keychain (bin/generate_keys)
#   - old DSA key (dsa_priv.pem) at $DSA_KEY: MTMR <= 0.27 ship Sparkle 1.x with only the DSA public key,
#     and Sparkle 1.x rejects an update that drops it, so every release must keep dsa_pub.pem
#     and carry both signatures until no one is left on 0.27.
#
# Environment overrides:
#   TEAM_ID            Apple team ID (default: taken from the Developer ID identity)
#   NOTARY_PROFILE     notarytool keychain profile (default: MTMR)
#   SPARKLE_BIN        Sparkle 2 bin dir (default: ~/Sparkle2/bin)
#   DSA_KEY            old DSA private key (default: ~/Sparkle/bin/dsa_priv.pem)
#   SKIP_NOTARIZE=1    build and sign only (for testing)
set -euo pipefail

NAME='MTMR'
NOTARY_PROFILE="${NOTARY_PROFILE:-MTMR}"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/Sparkle2/bin}"
DSA_KEY="${DSA_KEY:-$HOME/Sparkle/bin/dsa_priv.pem}"
NOTES="${1:-}"

die() { echo "error: $*" >&2; exit 1; }

IDENTITY_LINE=$(security find-identity -v -p codesigning | grep '"Developer ID Application' | head -1 || true)
[ -n "$IDENTITY_LINE" ] || die 'no "Developer ID Application" certificate in the keychain'
IDENTITY=$(echo "$IDENTITY_LINE" | sed -E 's/.*"(.*)".*/\1/')
TEAM_ID="${TEAM_ID:-$(echo "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/')}"
[ -x "$SPARKLE_BIN/sign_update" ] || die "Sparkle 2 sign_update not found at $SPARKLE_BIN"
[ -r "$DSA_KEY" ] || die "DSA private key not found at $DSA_KEY"
/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" MTMR/Info.plist >/dev/null 2>&1 || die "SUPublicEDKey missing in MTMR/Info.plist"
echo "Signing as: $IDENTITY (team $TEAM_ID)"

rm -rf Release
mkdir Release

cat > Release/export-options.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild archive \
	-scheme "$NAME" \
	-configuration Release \
	-archivePath Release/App.xcarchive \
	-quiet \
	ARCHS="arm64 x86_64" \
	DEVELOPMENT_TEAM="$TEAM_ID"

xcodebuild \
	-exportArchive \
	-archivePath Release/App.xcarchive \
	-exportOptionsPlist Release/export-options.plist \
	-quiet \
	-exportPath Release

cd Release
rm -rf App.xcarchive export-options.plist

codesign --verify --deep --strict --verbose=2 "${NAME}.app"

BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${NAME}.app/Contents/Info.plist")
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${NAME}.app/Contents/Info.plist")
MINIMUM=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "${NAME}.app/Contents/Info.plist")
DMG="${NAME} ${VERSION}.dmg"

# create-dmg exits 2 when it could not sign the DMG itself; we sign it below anyway.
create-dmg "${NAME}.app" || [ $? -eq 2 ]
[ -f "$DMG" ] || die "create-dmg did not produce '$DMG'"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
	xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
	xcrun stapler staple "$DMG"
	spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

# Sparkle signatures must be computed on the final (stapled) file.
DSA_SIGN=$(/usr/bin/openssl dgst -sha1 -binary < "$DMG" | /usr/bin/openssl dgst -sha1 -sign "$DSA_KEY" | /usr/bin/openssl enc -base64 -A)
ED_ATTRS=$("$SPARKLE_BIN/sign_update" "$DMG")   # prints: sparkle:edSignature="..." length="..."
echo "$ED_ATTRS" | grep -q 'sparkle:edSignature=' || die "sign_update failed: $ED_ATTRS"
SHA256=$(shasum -a 256 "$DMG" | awk '{print $1}')
DATE=$(LC_ALL=en_US.UTF-8 date +"%a, %d %b %Y %H:%M:%S %z")

cat > appcast.xml <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
		<item>
			<title>${VERSION}</title>
			<pubDate>${DATE}</pubDate>
			<description>
				${NOTES:-More information: https://github.com/Toxblh/MTMR/releases/tag/v${VERSION}}
			</description>
			<sparkle:minimumSystemVersion>${MINIMUM}</sparkle:minimumSystemVersion>
			<enclosure url="https://mtmr.app/MTMR%20${VERSION}.dmg"
				sparkle:version="${BUILD}"
				sparkle:shortVersionString="${VERSION}"
				${ED_ATTRS}
				sparkle:dsaSignature="${DSA_SIGN}"
				type="application/octet-stream"
			/>
		</item>
	</channel>
</rss>
EOF

echo ""
echo "VERSION $VERSION  BUILD $BUILD  MINIMUM $MINIMUM"
echo "DMG     Release/$DMG"
echo "SHA256  $SHA256"
echo ""
echo "Homebrew   https://github.com/Homebrew/homebrew-cask/edit/master/Casks/m/mtmr.rb"
echo "  version \"${VERSION}\""
echo "  sha256 \"${SHA256}\""
echo ""

read -r -p "Upload '$DMG' and appcast.xml to mtmr.app? [y/N] " ANSWER
if [ "$ANSWER" = "y" ]; then
	scp "$DMG" do:/var/www/mtmr
	scp appcast.xml do:/var/www/mtmr
else
	echo "Not uploaded. Files are in Release/."
fi
