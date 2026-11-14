# Bluetooth battery widgets (design, 2026-11-14)

## Intent

The user wants the battery level of their Bluetooth devices on the Touch Bar: AirPods, mouse and keyboard.
Each device gets its own widget. For AirPods, the left bud, the right bud and the case are separate widgets.
At the time of the request the right AirPod was at 9 %. The point is to see at a glance what needs charging.

Devices on the user's Mac:

- AirPods Pro 2, Apple, product 0x2014.
- Logitech MX Master 3S (mouse) and MX Keys Mini (keyboard). They connect over Bluetooth, according to the user.

## Goals

- One widget type that shows one battery value: a device, or one part of AirPods.
- The device is picked in the customizer from the paired devices, like the drives of the eject button.

## Non-goals

- Logitech's Bolt receiver. It needs Logitech's own HID++ protocol. The user connects over Bluetooth.
- Battery history, charge notifications, or the Mac's own battery (`BatteryBarItem` exists).

## Anti-goals

- A widget that shows a stale value as if it were current.
- A widget that takes Touch Bar space while its device is not connected.

## Approaches

1. **`system_profiler SPBluetoothDataType -json`, polled.** *Chosen by the user.*
   - Measured: 0.09 s.
   - Gives `device_batteryLevelLeft`, `device_batteryLevelRight` and `device_batteryLevelCase` for AirPods, under
     `device_connected` and `device_not_connected`, with name, address, minor type and vendor.
   - It is the same data System Settings shows. It is public, a stable tool output.
   - Cost: up to one polling interval of delay.
2. **Private IOBluetooth selectors** (`batteryPercentLeft`, …), as AirBuddy-style apps use.
   - Instant, no helper process.
   - Rejected: undocumented and may change with any macOS update. Probably no Logitech values.
3. **IOKit `BatteryPercent`.**
   - Rejected: only Apple's Magic Mouse and Keyboard appear there. Neither the user's AirPods nor the MX devices do
     (checked with `ioreg`).

## Behaviour

These are Claude's proposals, sent to the user with the approach question. The user picked the approach and did not
object to them.

- **Preset:** `{"type": "bluetoothBattery", "device": "<address>", "part": "left" | "right" | "case" | "main"}`.
  - The address is the device's Bluetooth address. Names are not unique: both AirPods entries are called "Pro 2".
  - `part` defaults to `main`.
- **Look:** a small outline icon in the style of the existing outline icons, then the percentage.
  - Icons: left bud, right bud, case, mouse, keyboard, and a generic one for other devices.
  - Below 20 % the percentage turns red, like the Mac battery widget.
- **Hidden** while the device is not connected, or while macOS reports no value for that part (a bud in its case).
  `BasicView` lays items out in an `NSStackView`, which detaches hidden views, so the space is freed.
- **Refresh:** every 60 s, off the main thread. A tap refreshes at once.
  - One shared poller for all battery widgets, so five widgets start one `system_profiler` per interval, not five.
- **Customizer:**
  - A "Device" picker lists paired devices by name and kind ("MX Master 3S — Mouse"). Connected ones come first.
  - A "Part" choice (left, right, case) applies to AirPods.
  - A device that is not paired any more is kept and marked "not paired".

## Constraints

- Swift and AppKit, in the existing widget and customizer structure: `ItemsParsing`, `TouchBarController`,
  `ItemCatalog`, `ItemInspectorView`, `IconLibrary` with its manifest and imagesets.
- Unit tests for parsing the JSON, using the user's real output as a fixture.

## Open, for the builder

- **Key for single devices.** The JSON key for a mouse or keyboard is assumed to be `device_batteryLevelMain`.
  This is not verified: the MX devices were not connected. Check it once they are connected, and if needed accept
  the key that shows up.
- **AirPods case entry.** The case value also appears on a second entry with its own address (`DD:CB:…`), which
  has only `device_batteryLevelCase`. For `part: case`, use the main entry's case value, and fall back to a
  connected entry with the same name.
- **Picker deduplication.** Hide the case-only entry from the picker.
- **Icon details:** left for the builder.

## Revision (2026-11-14, during implementation): two widget types

The user, mid-implementation: "mach es ein Widget für normale Geräte, wo man das Gerät auswählen kann und ein Kombi
Widget für Airpods wo man die Airpods auswählen kann". This replaces the `part` parameter:

- `{"type": "bluetoothBattery", "device": "<address>"}`: one device with one battery. The picker offers every
  paired device except Apple headphones.
- `{"type": "airpodsBattery", "device": "<address>"}`: left, right and case side by side in one widget.
  - Each part is red below 20 % on its own.
  - A part without a value is left out. With no value at all the widget is hidden.
  - The picker offers only Apple headphones (`device_minorType` Headphones, vendor 0x004C).
- **Claude's call:** "AirPods" means Apple headphones by vendor. Basis: Beats buds are vendor Apple and report
  left, right and case too. Other makers' headphones have one battery and belong to the device widget.
- Both share one widget class (`BluetoothBatteryBarItem` with a list of parts), one monitor and one picker.
