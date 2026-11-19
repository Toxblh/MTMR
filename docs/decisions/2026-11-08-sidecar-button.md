# Sidecar button: iPad as external display (2026-11-08)

The user asked for a Touch Bar button that turns their iPad into an external monitor directly.

Each entry: **Decision** · **Basis** · **Rejected alternative**.

## How Sidecar is started

- **Decision:** SidecarCore's private `SidecarDisplayManager` (`+sharedManager`, `-devices`, `-connectedDevices`,
  `-connectToDevice:completion:`, `-disconnectFromDevice:completion:`), resolved at runtime like the keyboard
  backlight (`KeyboardBrightnessClient`) and DisplayServices.
  **Basis:**
  - There is no public API to start Sidecar.
  - The selectors and type encodings were read with `class_copyMethodList` on the MacBookPro17,1 with macOS 27.
  - The same calls are used by the open-source SidecarLauncher (https://github.com/Ocasio-J/SidecarLauncher).
  - A probe on this Mac listed the user's iPad under `devices`, `connectedDevices` and `recentDevices`.
  - If a class or selector is missing, the button is dimmed and logs once; it does not crash.
  **Rejected:**
  - UI scripting Control Center's Screen Mirroring menu: it needs Accessibility for System Events, is slow and
    breaks whenever Apple changes the menu.
  - Opening the Displays settings pane: that is not "direct".
- **Decision:** `SidecarDevice`s with `isRealityDevice` are skipped.
  **Basis:** Apple Vision Pro's Mac Virtual Display goes through the same manager; the user asked for the iPad.

## Behaviour

- **Decision:** one toggle button. Tap connects when nothing is connected and disconnects a connected iPad.
  **Basis:** the same pattern as the Do Not Disturb / Dark Mode / Night Shift buttons.
- **Decision:** optional `deviceName`; without it the first available iPad is used.
  **Basis (assumption):** most users have one iPad. With several, `devices` has no stable order, so a name is the
  only reliable choice. The name is matched exactly, as shown in Control Center.
- **Decision:** state is polled every 2 s; the icon is dimmed while no iPad is reachable or a request is running,
  and taps are ignored during a request.
  **Basis:** Sidecar also starts and stops from Control Center, the iPad itself, or when the iPad leaves. Connecting
  takes a few seconds, and a second tap would start a second request.
  **Rejected:** observing SidecarCore notifications, which are undocumented and have no known names.
- **Decision:** a failed request is only logged.
  **Basis (assumption):** the dimmed or unchanged icon already shows that nothing happened. An alert from a Touch
  Bar agent app would steal focus.

## Icons

- **Decision:** two new outline icons in the set: `sidecar-on` (tablet with an arrow into it) and `sidecar-off`
  (tablet with the slash). The default is `sidecar-off`, like `dnd-off`.
- **Deviation from STYLE.md:** the off variant leaves out the arrow instead of cutting it around the slash.
  **Basis:** the slash would cross both the arrow shaft and its head within 2 units; the cut-up fragments were
  shorter than the 1.5-unit minimum detail. The glyph remains recognisable as the same tablet.

## Verification (MacBookPro17,1, macOS 27, one iPad over Wi-Fi)
- **Unit tests:** 88 pass, including decoding with and without `deviceName` and the new icons in the manifest and
  catalog.
- **Real code path on the Touch Bar:** a diagnostic build, not committed, called `toggle()` from a distributed
  notification.
  - Connect: the iPad was a display after 2.6 s, completion `nil`. Disconnect: immediate, completion `nil`.
  - `screencapture -b` showed the icon go off → on → off.
  - With `"deviceName": "Nope"` the button is dimmed.
- **Why not AXPress:** MTMR buttons have no `NSButton` action and react only to touch gesture recognizers. AXPress
  reports success but runs nothing. This upstream limitation applies to every MTMR button and also explains the
  earlier inconclusive volume-key AXPress test. It is not changed here.
- **Seen once:** a tap on the hardware button during the test failed with
  `SidecarErrorDomain -455 "SidecarErrorDisplayAWDLDegraded"`.
  - This is the Wi-Fi peer-to-peer link (AWDL) reporting a poor connection.
  - The button logged it and stayed usable, and the next requests worked.
