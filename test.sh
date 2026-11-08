# xcpretty is no longer required: xcodebuild -quiet prints only warnings/errors.
set -e

NAME='MTMR'
killall $NAME || true

rm -r Release 2>/dev/null

# xcodebuild \
#     -workspace ./MTMR.xcodeproj/project.xcworkspace \
#     -scheme MTMR \
#     -configuration Release CONFIGURATION_BUILD_DIR=./build/Release

xcodebuild archive \
	-scheme "$NAME" \
	-quiet \
	-archivePath Release/App.xcarchive

xcodebuild \
	-exportArchive \
	-archivePath Release/App.xcarchive \
	-exportOptionsPlist export-options.plist \
	-quiet \
	-exportPath Release

cd Release
rm -r App.xcarchive

# Prerequisite: npm i -g create-dmg
NAME_DMG="${NAME}.app"
echo $NAME_DMG
create-dmg $NAME_DMG

open ./$NAME.app
