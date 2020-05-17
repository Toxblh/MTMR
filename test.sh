# INSTALL xcpretty: sudo gem install xcpretty

NAME='MTMR'
killall $NAME

rm -r Release 2>/dev/null

# xcodebuild \
#     -workspace ./MTMR.xcodeproj/project.xcworkspace \
#     -scheme MTMR \
#     -configuration Release CONFIGURATION_BUILD_DIR=./build/Release

xcodebuild archive \
	-scheme "$NAME" \
	-archivePath Release/App.xcarchive | xcpretty

xcodebuild \
	-exportArchive \
	-archivePath Release/App.xcarchive \
	-exportOptionsPlist export-options.plist \
	-exportPath Release | xcpretty

cd Release
rm -r App.xcarchive

# Prerequisite: npm i -g create-dmg
NAME_DMG="${NAME}.app"
echo $NAME_DMG
create-dmg $NAME_DMG

open ./$NAME.app
