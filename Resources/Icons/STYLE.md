# MTMR outline icon style

All icons in this folder share one style so the Touch Bar looks like one set.

- **Canvas:** `viewBox="0 0 24 24"`, artwork inside 2.5–21.5 (keep ≥ 2.5 margin), optically centred.
- **Stroke only:** `fill="none" stroke="#000" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"`
  on the root `<svg>` exactly like `brightness-up.svg` / `volume-up.svg`. Small solid dots (r ≤ 1.25,
  `fill="#000" stroke="none"`) are the only filled shapes allowed.
- **Monochrome:** black only — the app renders them as template images (white on the Touch Bar). No colours,
  gradients, opacity, filters, masks, text, `<style>`, `<use>`, transforms or external references.
- **Geometry:** coordinates on 0.25 steps, rectangle corner radius 2 (or 1 for small parts), no detail or gap
  smaller than 1.5 units — icons are shown at ~22 pt.
- **On/off pairs:** the "off" variant is the same glyph plus a diagonal slash from (4,4) to (20,20); parts of the
  glyph under the slash are interrupted by a 1.5-unit gap so the slash reads clearly.
- **Files:** one icon per file, `<name>.svg`, name from `manifest.json`, single line, < 2 KB.
- **Originality:** draw the shapes yourself from simple primitives; do not copy SF Symbols or any icon font.
