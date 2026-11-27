# Smooth Touch Bar sliders (2026-11-09)

The user reported that the brightness, volume and keyboard light sliders are not smooth and sometimes hang.

Each entry: **Decision** · **Basis** · **Rejected alternative**.

## Findings (MacBookPro17,1, macOS 27, the user's running MTMR)

- **Piling up instances.** `heap` on the user's MTMR after 1.5 h counted 116 `BrightnessViewController`,
  116 `VolumeViewController`, 116 `WeatherBarItem`, `TimeTouchBarItem`, `UpNextScrubberTouchBarItem` and
  `BatteryInfo` instances, where one of each is shown. `KeyboardBrightnessViewController` and `SidecarBarItem`
  (block timers with a weak capture) had 1.
  - **Why:** `TouchBarController.createItems()` runs on every app launch, quit and activation. It created every
    item again and threw the new ones away when nothing had changed. Items that retain themselves never went
    away: target/selector timers, CoreAudio listener blocks made from method references.
  - **Growth:** 5 hidden launch/quit cycles of Calculator added 11 instances of each.
- **Cost of the piles.** Reading the display brightness takes ~2 ms (median of 40 calls). 116 controllers polling
  twice a second took about 460 ms of main-thread time per second, so the Touch Bar UI was blocked about half of
  the time. This grew with every app switch.
- **Volume set on the main thread.** Measured over 40 calls each:
  - setting the volume takes ~17 ms (median), and the mute flag, written on every movement, ~12 ms;
  - display brightness and keyboard light set in under 0.2 ms.
  - A freshly started old build answered a volume-slider change after a median of 72 ms (p95 195 ms), measured
    as an Accessibility set plus read round trip.
- **Polled values fought the finger.** The brightness timer (every 0.5 s) and the CoreAudio notifications wrote
  the system value into the slider during a drag, so the knob jumped back.

## Decisions

- **Decision:** `createItems()` reuses the existing item for an identifier instead of creating it again.
  **Basis:** the identifiers are new on every preset reload, so reuse only spans app switches. Items hidden by
  `matchAppId` are created again when they reappear. Checked on the device: a `matchAppId` button appears with
  Calculator in front and disappears after it quits.
  **Side effect:** widgets no longer restart on every app switch. Before, weather started a new network request
  and Up Next a new calendar query each time.
  **Rejected:** fixing only the self-retaining widgets. Every app switch would still have rebuilt every item.
  **Update (2026-11-19):** upstream merged the same reuse independently as #477 ("Avoid rebuilding the Touch
  Bar on application activation"), which also skips re-presenting an unchanged bar. When this branch was
  rebased onto upstream master, our own commit for it was dropped in favour of #477's code.
- **Decision:** the brightness controller uses a block timer with a weak capture and invalidates it in `deinit`,
  the same pattern as the keyboard light slider.
- **Decision:** the volume controller stores its CoreAudio listener blocks once, captures `self` weakly, and
  removes them in `deinit`.
  **Basis:** CoreAudio removes a listener only when it gets the same block object back. A method reference
  creates a new block at each call, so the old code could not remove its listeners either.
- **Decision:** the volume is applied on a serial queue. During a drag only the newest value is sent once the
  previous write is done, and the mute flag is written only when it changes.
  **Basis:** the measurements above. The CoreAudio HAL is thread-safe.
  **Rejected:** a time-based throttle, which would drop the final value or add delay.
- **Decision:** `CustomSlider` notes the time of the last user movement (`sendAction`) and ignores system values
  for 1 s after it, as well as values that would not change the slider.
  **Basis (assumption):** 1 s covers the display brightness ramp and the CoreAudio notification delay. It was not
  measured separately.

## Not changed

- `WeatherBarItem`, `TimeTouchBarItem`, `UpNextScrubberTouchBarItem` and `BatteryBarItem` still retain themselves.
  Since the change above they leak only on a preset reload (a save in the customizer), not on every app switch.

## Verification

- **Unit tests:** 92 pass. `SliderTests` checks the drag guard, and that the volume and keyboard light
  controllers are released. Run against the old volume code, the release test fails.
- **Installed build after 10 hidden launch/quit cycles:** every widget still exists once.
- **Test instance:** after 3 preset reloads, one brightness and one volume controller.
- **Volume-slider round trip:** median 0.1 ms (p95 0.1 ms), compared with 72 ms (p95 195 ms) for the old build.
