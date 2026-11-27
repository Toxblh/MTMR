# Group: text or icon, close with a tap on free space (2026-11-10)

The user asked for two things: the group button can be either an icon or the current design (text on a light
background), and inside an open group, a tap on a free spot next to the buttons closes it.

Each entry: **Decision** · **Basis** · **Rejected alternative**.

## Decisions

- **Decision:** the new key `"style"` takes `"text"` (default) or `"icon"`. Text keeps the system's titled button of
  `NSPopoverTouchBarItem`. Icon sets the group's `collapsedRepresentation` to a borderless `CustomButtonTouchBarItem`,
  32 pt wide, showing the preset's `image`. Without an image it shows the `folder` icon. The customizer offers it as
  "Show as", and the preview shows icon groups without their title.
  **Basis:** the user's request. The icon button looks and reacts like the other icon buttons.
  **Rejected:** deciding by whether an `image` is set. A text group with an image would change its look without
  being asked.
  **Assumption:** the folder icon as the default fits a group, the place where things are kept together. It can be
  replaced with any icon.
- **Decision:** the open group is a single item (`BasicView`, like the main bar): left items, the scrolling centre,
  an empty view that takes the free width, then right items.
  **Basis:** separate items leave gaps that belong to no view, so a tap there reaches nothing. In the first device
  test the centre scroll area stretched over the free space. The log shows the layout after the fix: stack 1004 pt,
  two buttons of 72 pt, empty view from x=207, 797 pt wide.
  **Rejected:** a tap recognizer on the scroll view. A scroll view handles touches itself for scrolling.
- **Decision:** the tap on free space is detected by a small recognizer of its own (`TouchTapRecognizer`): one finger,
  less than 10 pt movement, fires on lift-off. Touches on items are filtered out in `shouldReceive`, so the items'
  own taps, long presses and slider drags are unchanged.
  **Basis:** second device test. The log showed every touch arriving and classified as free space, but
  `NSClickGestureRecognizer` never fired for Touch Bar touches. MTMR's own button recognizers do their work in
  `touchesEnded` for the same reason. Third test: "tap on free space: closing", and the user confirmed that it works.
- **Decision:** closing shows the main bar's existing view again (`TouchBarController.closeGroup()`: the delegate and
  identifiers are put back). The preset is not reloaded.
  **Basis:** a group only replaces the delegate and the identifiers of the shared bar. Reloading would rebuild every
  widget, which the "close" button still does.
  **Rejected:** changing the existing "close" button to the same path. It was not part of the request.
- **Decision:** the open and close events are logged with `os_log` and public text ("MTMR group: ..."). The
  per-touch line is at debug level.
  **Basis:** these lines found the cause of the second failure. Debug lines are not stored by default, so
  everyday use does not fill the log.

## Verification

- **Unit tests:** 110 pass, including `testGroupStyleDecodes` (no style, `"icon"`, `"text"`).
- **On the device:** the user's group "Caffeine" opens. A tap next to its buttons closes it ("tap on free space:
  closing" in the log), and the user confirmed that it works.
- **Not tested on the device:** the icon style. The user's group uses the text style.
