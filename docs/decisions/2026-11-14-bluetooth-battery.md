# Bluetooth battery widgets (2026-11-14)

The user wanted battery widgets for connected AirPods, mouse and keyboard. Design and its revision:
`docs/superpowers/specs/2026-11-14-bluetooth-battery-design.md`.

Each entry: **Decision** · **Basis** · **Rejected alternative**.

- **Decision:** read the levels from `system_profiler SPBluetoothDataType -json`.
  **Basis:**
  - The user's choice among three approaches.
  - Measured: 0.09 s.
  - It gives left, right and case of AirPods as separate keys.
  **Rejected:**
  - Private IOBluetooth selectors: undocumented.
  - IOKit `BatteryPercent`: only Apple's Magic devices show up there.
- **Decision:** two widget types, `bluetoothBattery` (one device) and `airpodsBattery` (left, right and case in
  one widget), sharing one class with a list of parts.
  **Basis:** the user, mid-implementation: "ein Widget für normale Geräte … und ein Kombi Widget für Airpods". It
  replaced the first design, one widget per part with a `part` key, which was never released.
- **Decision:** AirPods are Apple headphones, `device_minorType` Headphones with vendor 0x004C.
  **Basis (assumption):** Beats buds are vendor Apple and report left, right and case as well. Other makers'
  headphones have one battery.
  **Cost if wrong:** an Apple headset with one battery lands in the AirPods picker.
- **Decision:** the preset stores the Bluetooth address.
  **Basis:** both AirPods entries in the user's output are named "Pro 2".
- **Decision:** one shared monitor polls every 60 s while any battery widget exists, and stops when none is left.
  A tap refreshes at once.
  **Basis:** five widgets would otherwise start five `system_profiler` runs per interval.
- **Decision:** a widget without a value is hidden. In the scrolling centre of the bar the stack is resized by hand
  (`NSView.setShownInBar`).
  **Basis:** found while checking the code. `ScrollViewItem` sizes its stack once, so a widget that appears after
  the bar is built would be clipped. Widgets are centre-aligned by default. Covered by
  `TouchBarVisibilityTests`.
- **Decision:** any `device_batteryLevel…` key other than Left, Right and Case counts as the device's one
  battery.
  **Basis (assumption, unverified):** the key for a mouse or keyboard was not seen, because the user's MX Master 3S
  and MX Keys Mini were not connected during the work. `device_batteryLevelMain` is the expected name.

## Not done

- **If `system_profiler` hangs**, the widgets keep their last value, with no timeout.
- **The customizer preview** shows the type's default icon, not the chosen device's icon.

## Verification

- **Unit tests:** 130 pass.
  - Parsing the user's real output, with the no-break space in "74 %".
  - A bud in its case, the case value on the second entry, a disconnected device, an unknown battery key.
  - Picker filtering, the order of the combined widget's parts, broken input.
  - Decoding both types, and showing a widget in the scrolling centre.
- **Installed on the user's Mac.** The widgets are not in the preset: the user adds them.
- **Not seen on the Touch Bar yet.**
