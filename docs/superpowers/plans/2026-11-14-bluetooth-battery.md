# Bluetooth Battery Widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `bluetoothBattery` widget shows one battery value: a Bluetooth device, or the left bud, right bud or
case of AirPods. It is hidden while there is no value.

**Architecture:**
- A model file parses `system_profiler SPBluetoothDataType -json`.
- One shared monitor polls every 60 s off the main thread and notifies all widgets.
- The widget is a `CustomButtonTouchBarItem`.
- The customizer gets a device picker field, like the eject button's drive list.

**Tech Stack:** Swift 5, AppKit, SwiftUI (customizer), XCTest. macOS 12+.

**Spec:** `docs/superpowers/specs/2026-11-14-bluetooth-battery-design.md`

## Global Constraints

- Preset: `{"type": "bluetoothBattery", "device": "<address>", "part": "left" | "right" | "case" | "main"}`.
  `part` defaults to `main`.
- Polling interval: 60 s. A tap refreshes at once. One `system_profiler` run per refresh for all widgets.
- The percentage turns red below 20 %.
- The widget is hidden (`view.isHidden = true`) while the device is not connected or has no value for the part.
- Icons follow the outline set: 24×24 viewBox, `stroke="#000"`, `stroke-width="1.75"`, round caps and joins.
- New model file compiled into the app and the test target, like `VolumeEjector.swift`.

## Review Focus

1. **AirPods with a bud in the case:** that side's key is missing, so its widget hides while the others stay.
   Test: `testMissingSideHasNoLevel`.
2. **Case value only on the second "Pro 2" entry** (the case's own address): `part: case` must still find it.
   Test: `testCaseFallsBackToEntryWithSameName`.
3. **Values with a non-breaking space** ("74\u{a0}%") and odd forms ("100%", "") parse to Int or nil.
   Test: `testParsesPercentStrings`.
4. **`system_profiler` fails or returns garbage:** no crash, all widgets hide. Test: `testGarbageGivesNoDevices`.
5. **The chosen device was unpaired:** it stays in the picker, marked "not paired", and the widget hides.
   Handled by the picker (Task 3), not unit-tested.

---

### Task 1: Model and parser (`BluetoothBattery.swift`)

**Files:**
- Create: `MTMR/BluetoothBattery.swift`, in the app and test targets of `MTMR.xcodeproj/project.pbxproj`.
- Test: `MTMRTests/BluetoothBatteryTests.swift`, in the test target.
- Fixture: the user's JSON from 2026-11-14, inline in the test file.

**Interfaces (produces):**
- `enum BluetoothBattery`
  - `enum Part: String, CaseIterable { case main, left, right, case_ = "case" }`
  - `enum Kind { case headphones, mouse, keyboard, other }`, from `device_minorType`.
  - `struct Device: Equatable { name: String; address: String; kind: Kind; isConnected: Bool; levels: [Part: Int] }`
  - `static func parse(_ data: Data) -> [Device]`. Keys:
    - `device_batteryLevelLeft` / `Right` / `Case`.
    - `device_batteryLevelMain`. Assumed, see the spec.
    - Any other `device_batteryLevel*` maps to `.main`.
  - `static func percent(_ text: String) -> Int?`
  - `static func level(address: String, part: Part, in devices: [Device]) -> Int?`
    - Only connected devices count.
    - For `.case_`, it falls back to a connected device with the same name.
  - `static func pickerDevices(_ devices: [Device]) -> [Device]`
    - Drops entries that have only a case value and share their name with an entry that has a minor type.
    - Connected entries first, then by name.
  - `final class Monitor`
    - `static let shared`
    - `func subscribe(_ owner: AnyObject, _ onChange: @escaping ([Device]) -> Void)` delivers on main.
    - `func refreshNow()`
    - `var devices: [Device]`
    - Polls every 60 s while it has subscribers. Subscribers are held weakly.
    - Runs `/usr/sbin/system_profiler SPBluetoothDataType -json` on a background queue. A refresh already running
      is not started twice.

- [ ] **Step 1: Write the failing tests**
  - `testParsesAirPodsAndMiceFromFixture`
    - Fixture device D0:3E:07:CD:30:F2: levels `[.left: 74, .right: 9, .case_: 53]`, kind `.headphones`, connected.
    - The MX Master 3S is `.mouse` and not connected.
  - `testParsesPercentStrings`
    - `percent("74\u{a0}%") == 74`, `percent("100%") == 100`, `percent("") == nil`.
  - `testMissingSideHasNoLevel`
    - Fixture without `device_batteryLevelLeft` → `level(…, part: .left, …) == nil`, right still 9.
  - `testCaseFallsBackToEntryWithSameName`
    - Main entry without its case key, second "Pro 2" entry with case 53 → `level(main address, .case_) == 53`.
  - `testDisconnectedDeviceHasNoLevel`
    - A mouse in `device_not_connected` with `device_batteryLevelMain` "80 %" → `level(…, .main) == nil`.
  - `testMainLevelOfMouse`
    - Connected mouse with `device_batteryLevelMain` "61 %" → 61.
  - `testPickerHidesCaseOnlyEntry`
    - The fixture gives AirPods, then the two MX devices. The case entry `DD:CB:…` is missing.
  - `testGarbageGivesNoDevices`
    - `parse(Data("x".utf8)).isEmpty`.
- [ ] **Step 2:** Run `xcodebuild test … -only-testing:MTMRTests/BluetoothBatteryTests`. Expected: build fails, the
  type is missing.
- [ ] **Step 3:** Implement the interfaces above.
- [ ] **Step 4:** Run the tests. Expected: all pass.

### Task 2: Widget, preset type and icons

**Files:**
- Create: `MTMR/Widgets/BluetoothBatteryBarItem.swift`, in the app target only.
- Modify:
  - `MTMR/ItemsParsing.swift`: case `bluetoothBattery(device: String, part: String)`, CodingKeys `device` and
    `part`, raw type.
  - `MTMR/TouchBarController.swift`: identifier `"com.toxblh.mtmr.bluetoothBattery."` and creation.
  - `MTMR/IconLibrary.swift`: `all`, and `builtInDefaults["bluetoothBattery"] = "headphones"`.
  - `Resources/Icons/manifest.json`.
- Create: `Resources/Icons/airpod-left.svg`, `airpod-right.svg`, `airpods-case.svg`, `mouse.svg`. The imagesets come
  from `python3 -I Resources/Icons/build-assets.py`.
- Test: `MTMRTests/PresetDocumentTests.swift`, `MTMRTests/IconLibraryTests.swift`.

**Interfaces:**
- Consumes `BluetoothBattery.Monitor.shared`, `level(address:part:in:)` and `Part(rawValue:)`. Unknown `part`
  values fall back to `.main`.
- Icon per part and kind:
  - `.left` → "airpod-left", `.right` → "airpod-right", `.case_` → "airpods-case".
  - `.main`: mouse → "mouse", keyboard → "keyboard", otherwise "headphones".
  - For `.main` the kind comes from the device itself.

- [ ] **Step 1: Tests**
  - `testBluetoothBatteryDecodes`
    - `{"type":"bluetoothBattery","device":"AA"}` → `("AA", "main")`.
    - With `"part":"case"` → `("AA", "case")`.
  - Add `"bluetoothBattery"` to the raw list of `testCatalogCoversDecoderTypes`.
  - Add the four icon names to the list of the icon test in `IconLibraryTests` (line 65).
- [ ] **Step 2:** Implement.
  - Widget: borderless, title = inline icon + " 74%", font 15 like `BatteryInfo`.
  - Red below 20.
  - `view.isHidden = level == nil`.
  - A single tap calls `Monitor.shared.refreshNow()`.
- [ ] **Step 3:** Run all tests. Expected: all pass. Build the app.

### Task 3: Customizer

**Files:**
- Modify:
  - `MTMR/Customizer/ItemCatalog.swift`: `FieldSpec.Kind.bluetoothDevice`, and the catalog entry "Bluetooth
    Battery", category `.widgets`, symbol `"battery.75"`.
    - Fields: `device` (`.bluetoothDevice`).
    - `part`: `.choice(["main","left","right","case"])`, default "main", help "left, right and case are for AirPods".
    - `defaultJSON: obj("bluetoothBattery")` plus `"device": ""`. The decoder needs `device`.
  - `MTMR/Customizer/ItemInspectorView.swift`: `BluetoothDevicePicker`.
    - A `Picker` over `pickerDevices(Monitor.shared.devices)`, labelled "<name> — <Kind>", with "(not connected)"
      for disconnected devices.
    - It keeps an unknown stored address as "<address> (not paired)".
    - It calls `refreshNow()` on appear.
  - `README.md`: a `bluetoothBattery` section next to `eject`.
- [ ] **Step 1:** Implement, run all tests, and build.
- [ ] **Step 2:** Check that `ItemCatalog` default JSON decodes. The existing catalog tests cover that.

### Task 4: Install, check on the device, document

- [ ] Ask the user to connect the MX devices. Read the real key for the main level and adapt the parser if it
  differs. Add a fixture test with that key.
- [ ] Install the Release build (editor check, quit, `mv` the old app to the scratchpad), and add the widgets to the
  preset only if the user asks.
- [ ] Write `docs/decisions/2026-11-14-bluetooth-battery.md`, then commit with commit-craft.
