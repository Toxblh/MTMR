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
- **Decision:** every volume is ejected with `diskutil eject`, never forced, off the main thread. A disk image is
  ejected through its own whole-disk device from `hdiutil info` (`/dev/disk11` for XcodeData), a drive through its
  mount point. The run stops at the first volume that fails.
  **Basis:** the first test on the device (below). `diskutil` names the process that keeps a volume busy;
  `NSWorkspace` only says that it is in use. Forcing would tear files away from apps that have them open.
  **Rejected:** `NSWorkspace.unmountAndEjectDevice` on the image's mount point. It ejects only the synthesized APFS
  disk (`disk12`), and the image stays attached with its file open. `hdiutil detach` works too, but prints a
  deprecation warning on macOS 27.
- **Decision:** each volume is first classified, then ejected the way its kind needs. The kind comes from
  `diskutil info -plist` and the volume's "is local" flag.

  | Kind | Detected by | Action |
  |---|---|---|
  | Drive (USB, Thunderbolt, SD, ...) | `BusProtocol` other than "Disk Image"; the disk is the APFS physical store's whole disk, else `ParentWholeDisk` | `diskutil eject <disk>` |
  | Disk image | `BusProtocol` "Disk Image"; the disk is the image's own disk (`disk11`), not the APFS container (`disk12`) | `diskutil eject <image disk>`, which detaches the image |
  | Network share | not local | `umount <path>` |
  | Unknown | `diskutil` knows nothing about it | `diskutil unmount <path>` only |

  A drive or image is ejected as a whole only if all of its mounted volumes are being ejected. The whole-disk eject
  runs with the last of them. If one of its volumes was not chosen, the chosen ones are only unmounted, and the drive
  or image stays with the others.
  **Basis:** the user asked for the kind of drive to be checked first, then ejected accordingly. Ejecting the whole
  disk of one chosen partition would take partitions with it that were not chosen.
  **Rejected:** a single `diskutil eject <mount point>` for everything. It ejects the synthesized APFS disk of an
  image, which leaves the image attached, and it takes sibling partitions along.
- **Decision:** a volume is tried up to 10 times, 0.5 s apart. Each try first detaches the images stored on it again.
  While a volume that holds images is being ejected, MTMR refuses disk-image mounts (DiskArbitration mount approval).
  Drives and images are handled the same way, because an image can hold further images.
  **Basis:** the user asked for this to work with any connected volume, not only T7. A process that attaches an image
  again as soon as it disappears (here the user's `local.xcodedata.mount` agent, which watches `/Volumes`; elsewhere a
  backup or sync tool) would otherwise make the drive busy again. Measured: the agent opens the image on T7 again
  1.2 s after it is detached.
  **Rejected:**
  - Special handling for the agent, such as a marker file. It works only on this Mac.
  - Racing it without a block: the drive unmount took 0.8 s, longer than the agent needs to start.
  The mount block applies to all disk images, because the approval callback does not learn the image file. It lasts
  only for the eject, a few seconds. 10 tries at 0.5 s replace 5 at 1 s: the same total wait, with more chances to land
  in a gap. A refused attach keeps the image file open for about 0.4 s, then detaches the image again (measured).
- **Decision:** a failure turns the icon red for 4 s and shows an alert with the drive name and the macOS reason.
  **Basis:** a drive that stays mounted must not look ejected, or the cable might be pulled. The Touch Bar alone
  cannot say which drive failed or why.
  **Rejected:** logging only, as most widgets do. The failure would be silent.
- **Decision:** once none of the chosen volumes is mounted, the icon is a checkmark (`eject-done`), in full white. This
  replaces the dimmed eject glyph used before. While ejecting, the eject glyph stays, dimmed; on failure it is red.
  **Basis:** the user asked for a checkmark when the volumes are ejected. The check also shows for drives that were
  unplugged without the button: "nothing chosen is mounted" is the state that matters before pulling a cable.
  **Rejected:** a checkmark only for a few seconds after a tap. It would be gone when you look down to unplug.
- **Decision:** the state is updated from `NSWorkspace` mount, unmount and rename notifications, not polled.
  **Basis:** these notifications also cover drives plugged in or ejected in Finder.

## First test on the device (failed)

The user's tap ejected XcodeData but not T7. From the DiskArbitration log:

- XcodeData was unmounted and its disk ejected at 15:35:05.010.
- The T7 unmount started at 05.066 and failed at 05.876 with status 0x10 (EBUSY).
- At 15:35:14 the agent logged "verwaiste Sitzung /dev/disk11 wird entfernt", so the image itself was still attached.

## Verification

- **Unit tests (first version):** 100 pass. `VolumeEjectorTests` covers:
  - the order, and images that are added to it automatically;
  - the empty list and names that are not mounted;
  - the path prefix ("T7 Backup" is not on "T7");
  - the `hdiutil` parsing, including the image device.

  `testEjectButtonDecodes` covers the preset decoding.
- **Dry run on this Mac (nothing ejected):** the order is XcodeData, then T7, for `["T7","XcodeData"]`, `["T7"]` and `[]`.
- **Dry run on this Mac, classified (nothing ejected):**
  - T7 → drive `disk8` → `ejectDrive(disk8)`.
  - XcodeData → image `disk11` → `detachImage(disk11)`.
- **Test rig, without T7:** a sparse-bundle image in the scratchpad with two partitions, MTMRHost and MTMRSecond.
  MTMRHost holds a further sparse bundle, MTMRInner.
  - Only MTMRSecond: that volume is unmounted. The image, MTMRHost and MTMRInner stay.
  - Only MTMRHost: MTMRInner is detached and MTMRHost unmounted. MTMRSecond stays.
  - Both partitions, with a loop that, like a `WatchPaths=/Volumes` agent but with no delay, attaches MTMRInner after
    every change of /Volumes: 5 of 5 runs succeed in about 2.9 s with no retry. The loop tries once per run and is
    refused. The same 3 runs without the mount block also succeed, but need up to 1 retry (5.5 s).
  - Against a loop that attaches every 0.2 s regardless of changes, 2 of 3 runs succeed. The volume is then busy most
    of the time, which no eject can beat without force, so it is reported, not forced.
  - With a process whose working directory is on MTMRHost: the run fails without force and names the process
    ("Unmount was dissented by PID … (/bin/sleep)"). An image can be mounted again right afterwards.
- **Unit tests:** 107 pass, including kind detection (USB drive, APFS image, APFS volume on a drive, network,
  unknown) and the action rules (drive with an image on it, one of two partitions, both partitions, share).
- **Not tested:**
  - Ejecting a physical drive. That would mean ejecting T7, which holds the repo. The drive path is the same
    `diskutil eject` call as for images, with the drive's whole disk (`disk8`).
  - Unmounting a network share. No share was mounted.
