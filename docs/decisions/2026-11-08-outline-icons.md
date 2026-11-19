# Monochrome outline icon set (2026-11-08)

The Touch Bar used three unrelated icon sources:
- colour emoji (☕️ display sleep, ⚡️ battery, ☀️⛅️☁️🌧 weather, ⏳ placeholders);
- old bitmap PNGs (brightness, keyboard light, DnD, dark mode, Night Shift, CPU);
- Apple's `NSImage.touchBar*` template images (volume, media keys).

The user asked for one set of single-colour outline icons, and for a way to pick icons from a selection.

Each entry: **Decision** · **Basis** · **Rejected alternative**.

## Artwork

- **Decision:** 74 original SVG icons in `Resources/Icons/`. They are drawn on a 24-unit canvas with a 1.75 stroke,
  round caps and joins, black only. `STYLE.md` holds the rules and `manifest.json` the names, titles and picker
  categories.
  **Basis:** `NSImage` loads SVG natively as vector (`_NSSVGImageRep`, verified on macOS 27), and asset catalogs
  accept SVG image sets with `preserves-vector-representation`.
  **Rejected:**
  - PNG exports, which are blurry at other scales and need two sizes per icon.
  - SF Symbols, which the user explicitly did not want ("Standard-Dinger"); they also cannot be redistributed as
    artwork.
  - An icon font, which adds tooling for no gain.
- **Decision:** template rendering, so the Touch Bar tints the icons white and the editor tints them with the
  label colour.
  **Basis:** the same mechanism as Apple's own Touch Bar template images, which the app already used for media
  keys.
- **Decision:** drawn by four designer agents in parallel, one per category.
  - Consistency comes from a written style guide, two reference icons (`brightness-up`, `volume-up`), a shared
    preview renderer (white on black, at 22 pt and enlarged), and a final review of all 74 icons on one sheet.
  - The dark-mode pair was redrawn after that review: hatching read as a pie chart, so it became a contrast circle
    that is distinct from the DnD moon.
  - **Basis:** the user asked for multiple agents. The style checks (root attributes, forbidden elements, size)
    are scripted.

## Notes on individual glyphs
- `weather-clear-day` is close to `brightness-up` (larger disc, shorter rays). They never appear in the same
  context.
- `previous`/`next` use one triangle plus a bar. Two triangles would leave gaps under 1.5 units at 22 pt.
- `app-grid` is 2×2 and `gear` has six teeth, for the same minimum-detail reason.

## Code

- **Decision:** `build-assets.py` compiles the SVGs into a **namespaced** `Icons/` asset folder, loaded as
  `NSImage(named: "Icons/<name>")`.
  **Basis:** legacy imagesets (`cpu`, `dnd-on`, `dark-mode-off`, …) use the same names and stay as fallbacks.
  `--check` and a unit test fail when the catalog is stale.
  **Rejected:** a flat namespace, because of the name collisions.
- **Decision:** presets reference the set as `"image": {"icon": "<name>"}`. The old `base64` and `filePath` forms
  keep working.
- **Decision:** a preset `image` now overrides a built-in's default image.
  **Basis:** `BarItemDefinition.init` used to apply the built-in parameters last, so a custom image on
  `brightnessUp` was silently dropped. Without the fix the picker would do nothing for built-ins.
- **Decision:** every replacement falls back to the previous asset, template or emoji when an icon asset is missing.
  **Basis:** the app should never show an empty key. `testMissingDefaultIconFallsBackToTitleForTextButtons` covers
  this.
- **Decision:** text widgets show icons as inline attachments tinted to the text colour: battery bolt, weather
  conditions, Pomodoro timer and the loading hourglass.
  **Basis:** `NSTextAttachment` images are not tinted by the text colour, so the tinted copy is made up front.
- **Decision:** template images are pre-tinted white before they are handed to a Touch Bar button.
  **Basis:** measured on the M1. Borderless (`.inline`) buttons drew the DnD, Dark Mode and Night Shift icons grey.
  `contentTintColor` had no effect, and pre-tinting made them white.
- **Decision:** a customizer "Icon…" picker: a searchable grid grouped by category that writes `{"icon": …}`.
  Built-ins show their default icon as a placeholder, and the preview chips render the same icons as the Touch
  Bar.

## Verification
- **Unit tests:** 87 pass. They cover the manifest ↔ Swift list ↔ SVG files, asset catalog freshness, the JSON
  `icon` source, default icons, user overrides, fallbacks, inline tinting and the asset script.
- **Real Touch Bar (MacBookPro17,1, macOS 27):** two presets with every built-in that changed, plus custom buttons
  using picker icons.
  - Every icon renders white.
  - An Accessibility read-out of all Touch Bar labels finds no emoji.
- **Not changed:** the weather loading hourglass is shown alone for a few seconds and sits slightly low. This is
  cosmetic and only visible during loading.
- **Kept on purpose:** the legacy PNG imagesets are fallbacks. They can be removed once the set has shipped.
