killall MTMR

xcodebuild \
    -workspace ./MTMR.xcodeproj/project.xcworkspace \
    -scheme MTMR \
    -configuration Release CONFIGURATION_BUILD_DIR=./build/Release

open ./build/Release/MTMR.app
