# Eject button (2026-11-10)

The user asked for a button that ejects the drives T7 and XcodeData, where you choose which drives it ejects. It is
only built into the app; the user adds it to their preset themselves.

Each entry: **Decision** · **Basis** · **Rejected alternative**.

## Findings (MacBookPro17,1, macOS 27)

- T7 is a USB SSD (`disk8s1`, exFAT). XcodeData is not a partition: `hdiutil info` shows it as the sparse bundle
  `/Volumes/T7/Developer/Mac-Auslagerung/XcodeData.sparsebundle`, so it is stored on T7.
- `FileManager.mountedVolumeURLs(.skipHiddenVolumes)` returns `/`, T7 and XcodeData. The simulator runtime images
  are hidden. T7 reports `volumeIsEjectable = false` (only removable media is "ejectable") and `volumeIsInternal = false`.
  XcodeData reports `volumeIsInternal = nil`.

## Decisions

- **Decision:** the preset stores volume names (`"volumes": ["T7", "XcodeData"]`), and the customizer shows a checkbox for
  each connected external volume. Chosen names that are not connected stay in the list, marked "not connected".
  **Basis:** the user's request to choose the drives. The name is what Finder shows. Device IDs (`disk8s1`) change
  every time a drive is plugged in.
  **Rejected:** a menu of drives on every tap. The user wants one tap that ejects their set of drives.
- **Decision:** an empty or missing list ejects every external volume.
  **Basis (assumption):** a plain eject button with nothing configured should do the obvious thing. Nothing is
  forced, so a drive in use stays mounted.
  **Rejected:** doing nothing when the list is empty. A newly added button would then seem broken.
- **Decision:** when a drive is chosen, disk images stored on it are ejected too, before the drive. Images always go
  before the drive that holds them.
  **Basis:** macOS refuses to eject T7 while XcodeData is attached. The image path comes from `hdiutil info -plist`,
  the public source for which file backs an image.
  **Rejected:** ejecting exactly the chosen list in the order given. Choosing only T7, or listing T7 first, would fail.
- **Decision:** volumes are ejected with `NSWorkspace.unmountAndEjectDevice(at:)`, never forced, off the main thread. The
  run stops at the first failure.
  **Basis:** forcing would tear files away from apps that have them open. If an image cannot be ejected, the drive
  holding it cannot be either.
- **Decision:** a failure turns the icon red for 4 s and shows an alert with the drive name and the macOS reason.
  **Basis:** a drive that stays mounted must not look ejected, or the cable might be pulled. The Touch Bar alone
  cannot say which drive failed or why.
  **Rejected:** logging only, as most widgets do. The failure would be silent.
- **Decision:** the state is updated from `NSWorkspace` mount, unmount and rename notifications, not polled.
  **Basis:** these notifications also cover drives plugged in or ejected in Finder.

## Verification

- **Unit tests:** 100 pass. `VolumeEjectorTests` covers the order, images added automatically, the empty list,
  unmounted names, the path prefix ("T7 Backup" is not on "T7") and the `hdiutil` parsing.
  `testEjectButtonDecodes` covers the preset decoding.
- **Dry run on this Mac (nothing ejected):** `["T7","XcodeData"]` → XcodeData, T7. `["T7"]` → XcodeData, T7.
  `["XcodeData"]` → XcodeData. `[]` → XcodeData, T7.
- **Not tested on the device:** an actual eject, the customizer checkbox list and the alert. The installed app was
  not replaced, because the user did not ask for an install.
