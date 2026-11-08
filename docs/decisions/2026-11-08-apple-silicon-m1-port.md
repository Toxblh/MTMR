# Apple Silicon / M1 port (2026-11-08)

Goal: MTMR builds with current Xcode and runs natively (no Rosetta) on a MacBook Pro 13" M1 2020
(`MacBookPro17,1`). All measurements below were taken on that machine, macOS 27.0.1, Xcode 27.2.

Each entry: **Decision** · **Basis** · **Rejected alternative**.

## Build

### Deployment target 12.0
- **Decision:** `MACOSX_DEPLOYMENT_TARGET = 12.0` (project level; targets inherit; `LSMinimumSystemVersion`
  follows via `$(MACOSX_DEPLOYMENT_TARGET)`).
- **Basis:** Xcode 27.2 refuses 11.0: *"the range of supported deployment target versions is 12.0 to 27.2.x"*.
  With 12.0 Debug (arm64), Release (universal) and the `UnitTests` scheme all succeed.
- **Rejected:** 13.0 — would drop macOS 12 users for no gain.

### Universal binary kept
- **Decision:** keep `ARCHS = "arm64 x86_64"` from #476.
- **Basis:** `lipo -archs MTMR.app/Contents/MacOS/MTMR` → `x86_64 arm64`. Bundled Sparkle 2.1.0 has both slices in
  all five Mach-O binaries (framework, Autoupdate, Updater.app, Downloader.xpc, InstallerLauncher.xpc).
- **Rejected:** arm64-only — would cut off the 2016–2019 Intel Touch Bar MacBooks.

### Build-number Run Script only in Release
- **Decision:** the phase that bumps `CFBundleVersion` in the *source* `Info.plist` now exits early unless
  `CONFIGURATION == Release`, and is marked `alwaysOutOfDate`.
- **Basis:** every Debug/test build dirtied the tracked plist; `build.sh` still needs the bump for the appcast.
- **Rejected:** deleting the phase (release flow depends on it).

### `xcodebuild -quiet` instead of `xcpretty`
- **Basis:** `cmd | xcpretty` hid xcodebuild's exit code in `build.sh`; xcpretty is not guaranteed on runners.
  This is a judgment call, not a measured CI failure.

## Hardware integration

### Display brightness: DisplayServices
- **Decision:** `DisplayServicesGet/SetBrightness` (private framework, resolved via `dlopen`/`dlsym`) on the
  built-in display; CoreDisplay and `IODisplayConnect` remain as fallbacks.
- **Basis:** Apple Silicon has no `IODisplayConnect` service. Measured: `Set(0.95)` → `Get` = 0.95, rc 0, restored.
  The old code passed display ID `0`, which is not a valid `CGDirectDisplayID` (built-in display here is `1`).
- **Rejected:** linking the private framework — a missing framework would crash at launch instead of degrading.

### Keyboard backlight: keep HID aux keys
- **Decision:** no change; `NX_KEYTYPE_ILLUMINATION_UP/DOWN` keep working.
- **Basis:** measured backlight 0.413 → 0.4375 (UP) → 0.375 (DOWN).
- **Rejected:** CoreBrightness `KeyboardBrightnessClient` — also works, but adds a private dependency for no benefit.

### Haptics: discover the actuator at runtime
- **Decision:** enumerate `AppleMultitouchDevice` → `"Multitouch ID"` from the IORegistry; use the first ID whose
  actuator can be created *and* opened; the hardcoded list is a fallback only.
- **Basis:** this M1 reports `0x200000000000027` (Touch Bar digitizer, `MTActuatorCreateFromDeviceID` → NULL) and
  `0x20000000000002B` (trackpad, open + actuate → `kIOReturnSuccess`). The previously hardcoded M1 IDs (`…24`, `…23`)
  return NULL, so haptics never fired. Because NULL really occurs, the function is now declared `_Nullable`.
- **Rejected:** matching on the `Product` string — weaker basis, may differ across models.

### Media keys: CGEvent instead of IOHIDPostEvent
- **Decision:** post the same `NX_SYSDEFINED` aux-control event as `NSEvent` → `CGEventPost(kCGHIDEventTap)`.
- **Basis:** `IOHIDPostEvent`/`IOMasterPort` are deprecated (macOS 11/12). Measured: SOUND_UP/DOWN moved volume
  40 → 44 → 38 (restored). Requires Accessibility permission, which the app already requests.

## Platform APIs

- **Sparkle:** `SUUpdater` (Sparkle 1 shim) → `SPUStandardUpdaterController`, same settings.
  *Open:* `Info.plist` still uses DSA (`SUPublicDSAKeyFile`). Sparkle 2.1.0 still accepts it (per Sparkle docs,
  not tested end-to-end); moving to EdDSA (`SUPublicEDKey`) needs the maintainer's keys and was not attempted.
- **Launch at login:** `SMAppService.mainApp` on macOS 13+, `LaunchAtLoginController` (LSSharedFileList) on 12.
- **Widgets:** CoreAudio `…ElementMaster` → `…ElementMain`; `withMemoryRebound` instead of `unsafeBitCast` in
  `CPU.swift`; NSWorkspace, NSUserNotification, CLLocationManager, Scanner deprecations replaced.
  `NSImage(iconRef:)` is kept (wrapped in ObjC) because on macOS 27 TIS returns no icon URL for keyboard layouts.
- Data sources verified on the M1: volume (VirtualMainVolume 0.51 == `osascript` 51), CPU (19–38 % vs `top`
  21–40 %), battery (13 %, 6:51 to full == `pmset -g batt`), network (`netstat -w1 -l en0` parses).

## Known limits
- Haptic IDs and the Intel fallback paths could not be verified on Intel hardware.
- `NetworkBarItem` hardcodes `en0` (pre-existing).
- `SMAppService.register()` was not exercised against an installed, Developer-ID signed copy.
