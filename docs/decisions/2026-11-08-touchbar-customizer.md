# Touch Bar customizer UI (2026-11-08)

Goal: users change their Touch Bar in a native window instead of hand-editing
`~/Library/Application Support/MTMR/items.json`. Built and tested on a MacBook Pro 13" M1 2020, macOS 27.

Each entry: **Decision** · **Basis** · **Rejected alternative**.

## Data model

### Edit an order-preserving JSON tree, not `BarItemDefinition`
- **Decision:** `JSONValue` / `JSONObject` (ordered keys, `int` kept apart from `double`) is the editing model;
  `PresetDocument` wraps the item array, lifting group `items` into `children`.
- **Basis:** `BarItemDefinition` is `Decodable` only, `ItemType` holds closures, and unknown keys are dropped on
  decode, so a decode → encode round trip would lose user data and reorder keys.
- **Rejected:** making `BarItemDefinition` `Encodable` (large change to the parser, still lossy for unknown keys).

### Validate with the app's own decoder before writing
- **Decision:** `validate()` decodes the output with `JSONDecoder` → `[BarItemDefinition]`, and additionally
  decodes each known item with `ItemType`, because `BarItemDefinition` swallows parameter errors with `try?`
  (`ItemsParsing.swift`, e.g. a swipe without `fingers` silently becomes an unknown button).
  Unknown type strings are accepted, as the app accepts them.

### Write in place, never leave an empty file
- **Decision:** save overwrites the existing file in place (old tail padded with spaces, then truncated).
- **Basis:** `AppDelegate.reloadOnDefaultConfigChanged` watches the file descriptor (`O_EVTONLY`), so an atomic
  replace would detach the watcher; and every write event triggers a reload, so a truncate-then-write would
  briefly expose an empty file. The unit tests check that the inode stays the same.
- **Rejected:** `Data.write(options: .atomic)`.

### Comments
- **Decision:** the UI writes strict JSON. If the file on disk contains comments, it is copied once to
  `items.backup.json` before the first save.
- **Basis:** the shipped default preset uses `//` comments; JSON writers cannot preserve them.

### Defaults come from the decoder
- **Decision:** catalog defaults follow `ItemsParsing.swift` where it differs from the README
  (e.g. weather refresh 1800 s, pomodoro rest 600 s). All 38 types the decoder and `TouchBarController` accept are
  listed; a unit test checks that every default item decodes.

## UI

- **Window:** SwiftUI in an `NSWindowController`, opened from the status menu ("Customize Touch Bar…", ⌘,).
  `NSApp.activate` is needed because MTMR is an `LSUIElement` agent. "Edit Preset File…" still opens the JSON.
- **Layout:** Touch Bar preview (left / center / right zones) on top, sidebar list (zones, groups, gestures;
  drag to reorder), inspector with typed controls plus a raw-JSON "Advanced" editor for anything else.
- **Preview chips** show only a configured `title` as text. On the hardware, untitled widgets show live
  values, and type names truncated badly in narrow chips.
- **Save** is explicit (⌘S). The app reloads the Touch Bar directly after saving.
- **Review:** `apple-hig-expert` (`hig_checker.py`) — contrast passes; its 44 pt target rule is iOS-specific.
  macOS-sized controls are kept, and every icon-only button has a tooltip and an accessibility label.

## Robustness fixes found while testing on the M1

1. **Invalid preset no longer crashes the app.** `barItemDefinitions()` used `try!`. It now returns nil, and the
   existing "bad preset" fallback button is shown.
2. **No Touch Bar reload during a modal session.**
   - Saving while an AppleScript "Where is Spotify?" dialog was open crashed AppKit
     (`NSConcretePointerArray was mutated while being enumerated` in `+[NSFunctionRow markActiveFunctionRowsAsDimmed:]`).
   - The dialog surfaces because activating MTMR resumes deferred Apple Events.
   - Reproduced, and confirmed fixed, with the same preset.
3. **Default Spotify button.**
   - A literal `application "Spotify"` triggers that dialog on Macs without Spotify.
   - The script now checks with `pgrep` and addresses Spotify only inside `run script`.
   - Verified: no dialog, and the button stays hidden.
   - Existing user presets keep the old script, which still shows the dialog when MTMR is activated, but no
     longer crashes.

## Code review round

Nine of ten findings from a review of the branch were confirmed against the code and fixed:
- **Number input:** typed `inf`/`nan`/huge numbers trapped in `Int64(_:)`; fields clamped on every keystroke.
- **Required keys:** clearing a field the decoder requires removed it, so Save failed.
- **Loader and validator disagreed:** the app loader's regex `stripComments()` cut strings such as `echo a // b`,
  so a preset the customizer had validated could still load as "bad preset". The loader now uses `JSONValue`.
- **Escape is forced left by the app** (type parameters override `align`). The model and UI now reflect that.
- **Quitting** with unsaved changes discarded them; it now asks Save / Don't Save / Cancel.
- **Palette** added a stale, filtered-out selection.
- **Images** were embedded at full size; they are now stored as PNG of at most 64 px.
- **Reloads:** one save reloaded the Touch Bar two or three times; reloads are now debounced.

**Not changed:** "list editors drop non-string / non-object entries". Such entries already fail the app's
decoder, so no working preset can lose data that way.

## Verification
- 70 unit tests pass (parser, round trips, saving, editing operations, catalog decodes, app loader).
- On the device, a temporary self-test hook that was not committed did the following in the real app:
  - opened the window and loaded the default preset (13 items, validation OK);
  - added a button and saved;
  - confirmed with `screencapture -b` that the new button appears live on the Touch Bar.
- **Not verified interactively:** drag-and-drop reordering, context menus, the add popover, the color and file
  pickers, the close-with-unsaved-changes sheet. There was no UI automation or screen-recording permission on the
  test machine.
- **Not verified on older systems:** the macOS 12 layout. Only macOS 27 was available.
