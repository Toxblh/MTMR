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

## Addendum: charging indicator

The user asked for a sign that shows when a device is charging.

- **Decision:** charging state from IOKit's accessory power sources (`IOPSCopyPowerSourcesByType`), read with
  every refresh. The levels still come from `system_profiler`.
  **Basis:**
  - The user's choice among three options.
  - `system_profiler` has no charging state. The power sources have `Is Charging` per part ("Part Identifier"
    Left, Right, Case), checked live: the right bud in its case was charging, left and case were not.
  - The function is what `pmset -g accps` uses but is not in the public headers. It is looked up with `dlsym`, and
    without it there is simply no bolt.
  **Rejected:**
  - `pmset -g accps` text: one entry for the AirPods, not per part.
  - Taking the levels from the power sources too: everything would depend on the unpublished function.
- **Decision:** a power source belongs to a device by product ID ("0x2014" = 8212), or by name when either lacks
  one. The case is named "<name> Case".
  **Basis:** the power sources carry no Bluetooth address.
- **Decision:** a bolt (`bolt` icon) before the number of a charging part. A charging part is not red.
- **Decision:** the notify(3) keys `com.apple.system.accpowersources.{source,attach,timeremaining}` trigger a
  refresh, 1 s after the last notification of a burst.
  **Basis:** the user saw the case without a bolt. A screenshot of the Touch Bar a little later showed it, so the
  refresh came too late. A 4-minute listener showed:
  - `IOPSNotificationCreateRunLoopSource` (first used) fired once a minute, for the Mac's own battery.
  - The accessory keys fired with every AirPods change, as bursts within one second.
  The keys are strings in the IOKit binary, not public. If they stop firing, the 60 s timer still refreshes.
  **Rejected:** a shorter timer, which costs a `system_profiler` run every few seconds.
- **Decision:** a part with no power source in a reading keeps its last charging state. A source that is present
  and says "not charging" ends it.
  **Basis:** a 150 s sampler (every 0.25 s) showed the sources of the right bud and the case vanish for about 16 s
  at a time while only the left one stayed. The live monitor showed the bolt dropping out in those moments. Tests:
  `testChargingIsKeptWhileItsSourceIsMissing`, `testChargingEndsWhenTheSourceSaysSo`.
  **Cost if wrong:** after unplugging, the bolt can stay until the source returns.
- **Fixed on the way:** a part missing on the main AirPods entry is taken from the second entry with the same
  name, for every part, not only the case.
  **Basis:** seen live. The right bud and the case came only on the second entry, whose address had changed. Test:
  `testAnyPartFallsBackToEntryWithSameName`.
- **Verified:** 135 unit tests pass. Live, the model read left 65 %, right 73 % (charging) and case 34 % from the
  user's AirPods.

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
