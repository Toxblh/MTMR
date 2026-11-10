import XCTest

final class VolumeEjectorTests: XCTestCase {
    private typealias Volume = VolumeEjector.Volume
    private let ssd = Volume(name: "T7", path: "/Volumes/T7")
    private let xcodeData = Volume(name: "XcodeData", path: "/Volumes/XcodeData")
    private let stick = Volume(name: "Stick", path: "/Volumes/Stick")
    /// The real layout on the developer's Mac: XcodeData is a sparse bundle stored on T7.
    private var images: [VolumeEjector.DiskImage] {
        [.init(imagePath: "/Volumes/T7/Developer/Mac-Auslagerung/XcodeData.sparsebundle", mountPoints: ["/Volumes/XcodeData"])]
    }

    private func plan(_ names: [String], mounted: [Volume]? = nil) -> [String] {
        VolumeEjector.plan(names: names, mounted: mounted ?? [ssd, xcodeData, stick], images: images).map(\.name)
    }

    func testImageIsEjectedBeforeTheDriveItLivesOn() {
        XCTAssertEqual(plan(["T7", "XcodeData"]), ["XcodeData", "T7"])
        XCTAssertEqual(plan(["XcodeData", "T7"]), ["XcodeData", "T7"])
    }

    func testChoosingTheDriveAlsoEjectsImagesStoredOnIt() {
        XCTAssertEqual(plan(["T7"]), ["XcodeData", "T7"])
    }

    func testChoosingOnlyTheImageLeavesTheDrive() {
        XCTAssertEqual(plan(["XcodeData"]), ["XcodeData"])
    }

    func testEmptyChoiceEjectsEveryExternalVolume() {
        XCTAssertEqual(Set(plan([])), ["T7", "XcodeData", "Stick"])
        XCTAssertLessThan(plan([]).firstIndex(of: "XcodeData")!, plan([]).firstIndex(of: "T7")!)
    }

    func testNamesThatAreNotMountedAreSkipped() {
        XCTAssertEqual(plan(["T7", "XcodeData"], mounted: [stick]), [])
    }

    func testPathPrefixMustBeAWholeFolder() {
        // "/Volumes/T7 Backup/..." is not on "/Volumes/T7".
        let other = Volume(name: "T7 Backup", path: "/Volumes/T7 Backup")
        let image = VolumeEjector.DiskImage(imagePath: "/Volumes/T7 Backup/x.dmg", mountPoints: ["/Volumes/XcodeData"])
        let result = VolumeEjector.plan(names: ["T7"], mounted: [ssd, other, xcodeData], images: [image]).map(\.name)
        XCTAssertEqual(result, ["T7"])
    }

    func testParsesHdiutilInfo() throws {
        let plist: [String: Any] = ["images": [
            ["image-path": "/Volumes/T7/a.sparsebundle",
             "system-entities": [["dev-entry": "/dev/disk12"], ["dev-entry": "/dev/disk12s1", "mount-point": "/Volumes/XcodeData"]]],
            ["system-entities": []], // no image-path: skipped
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        XCTAssertEqual(VolumeEjector.parseDiskImages(plist: data),
                       [.init(imagePath: "/Volumes/T7/a.sparsebundle", mountPoints: ["/Volumes/XcodeData"], device: "/dev/disk12")])
    }

    // MARK: Kind of volume and how it is ejected

    /// `diskutil info -plist` of the user's volumes, reduced to the keys that are read.
    private let t7Info: [String: Any] = ["DeviceIdentifier": "disk8s1", "ParentWholeDisk": "disk8", "BusProtocol": "USB", "FilesystemType": "exfat"]
    private let xcodeDataInfo: [String: Any] = ["DeviceIdentifier": "disk12s1", "ParentWholeDisk": "disk12", "BusProtocol": "Disk Image",
                                                "APFSPhysicalStores": [["APFSPhysicalStore": "disk11s2"]]]

    func testUSBDriveIsADriveOfItsWholeDisk() {
        XCTAssertEqual(VolumeEjector.kind(diskutilInfo: t7Info, isLocal: true), .drive(disk: "disk8"))
    }

    func testAPFSImageIsEjectedThroughItsOwnDiskNotTheContainer() {
        XCTAssertEqual(VolumeEjector.kind(diskutilInfo: xcodeDataInfo, isLocal: true), .diskImage(disk: "disk11"))
    }

    func testAPFSVolumeOnADriveUsesThePhysicalStore() {
        let info: [String: Any] = ["ParentWholeDisk": "disk9", "BusProtocol": "Thunderbolt", "APFSPhysicalStores": [["APFSPhysicalStore": "disk8s2"]]]
        XCTAssertEqual(VolumeEjector.kind(diskutilInfo: info, isLocal: true), .drive(disk: "disk8"))
    }

    func testNetworkShareAndUnknown() {
        XCTAssertEqual(VolumeEjector.kind(diskutilInfo: nil, isLocal: false), .network)
        XCTAssertEqual(VolumeEjector.kind(diskutilInfo: nil, isLocal: true), .unknown)
        XCTAssertEqual(VolumeEjector.wholeDisk("disk11s2"), "disk11")
        XCTAssertEqual(VolumeEjector.wholeDisk("disk3s3s1"), "disk3")
    }

    func testDriveAndImageOnItGetTheirOwnActions() {
        let t7 = Volume(name: "T7", path: "/Volumes/T7", kind: .drive(disk: "disk8"))
        let data = Volume(name: "XcodeData", path: "/Volumes/XcodeData", kind: .diskImage(disk: "disk11"))
        XCTAssertEqual(VolumeEjector.actions(for: [data, t7], mounted: [t7, data]),
                       [.detachImage(disk: "disk11"), .ejectDrive(disk: "disk8")])
    }

    func testOneOfTwoPartitionsIsOnlyUnmounted() {
        let a = Volume(name: "A", path: "/Volumes/A", kind: .drive(disk: "disk8"))
        let b = Volume(name: "B", path: "/Volumes/B", kind: .drive(disk: "disk8"))
        XCTAssertEqual(VolumeEjector.actions(for: [a], mounted: [a, b]), [.unmountVolume])
        // Both chosen: the drive is ejected with the last one.
        XCTAssertEqual(VolumeEjector.actions(for: [a, b], mounted: [a, b]), [.unmountVolume, .ejectDrive(disk: "disk8")])
    }

    func testShareIsUnmountedAndUnknownIsOnlyUnmounted() {
        let share = Volume(name: "NAS", path: "/Volumes/NAS", kind: .network)
        let odd = Volume(name: "Odd", path: "/Volumes/Odd", kind: .unknown)
        XCTAssertEqual(VolumeEjector.actions(for: [share, odd], mounted: [share, odd]), [.unmountShare, .unmountVolume])
    }

    // MARK: Done is done, whoever did it

    func testMountPointDetection() {
        XCTAssertTrue(VolumeEjector.isMountPoint("/"))
        XCTAssertFalse(VolumeEjector.isMountPoint("/System/Library")) // a folder on a volume, not its mount point
        XCTAssertFalse(VolumeEjector.isMountPoint("/Volumes/MTMR-not-mounted-\(UUID().uuidString)"))
    }

    func testVolumeRemovedBySomeoneElseCountsAsGone() {
        // An auto-mount agent force-detached the image between MTMR's unmount and eject: nothing is mounted at the
        // path and no image with the file is attached, so the step is done, not failed.
        let gone = Volume(name: "XcodeData", path: "/Volumes/MTMR-gone-\(UUID().uuidString)")
        XCTAssertTrue(VolumeEjector.isGone(gone, imagePath: "/nonexistent/\(UUID().uuidString).sparsebundle"))
        XCTAssertFalse(VolumeEjector.isGone(Volume(name: "root", path: "/"), imagePath: nil))
    }

    // MARK: The process that keeps a volume busy

    func testReadsTheBlockerFromDiskutilsImageMessage() throws {
        // Verbatim from the user's alert (diskutil eject of the XcodeData image, 2026-11-10).
        let message = """
        Unmount of disk11 failed: at least one volume could not be unmounted
        Unmount was dissented by PID 60972 (/Users/louitz/.local/bin/uv)
        Dissenter parent PPID 60971 (/Applications/Claude.app/Contents/Helpers/disclaimer)
        """
        let blocker = try XCTUnwrap(VolumeEjector.blocker(in: message))
        XCTAssertEqual(blocker.pid, 60972)
        XCTAssertEqual(blocker.path, "/Users/louitz/.local/bin/uv")
        XCTAssertEqual(blocker.name, "uv")
        XCTAssertEqual(blocker.appName, "Claude")
    }

    func testReadsTheBlockerFromDiskutilsVolumeMessage() throws {
        // Verbatim from `diskutil unmount` of a test image with a shell inside it.
        let message = """
        Volume MTMRBusy on disk14s1 failed to unmount: dissented by PID 62744 (/bin/bash)
        Dissenter parent PPID 62724 (/bin/zsh)
        """
        let blocker = try XCTUnwrap(VolumeEjector.blocker(in: message))
        XCTAssertEqual(blocker.pid, 62744)
        XCTAssertEqual(blocker.name, "bash")
        XCTAssertNil(blocker.appName)
    }

    func testNoBlockerWithoutAPID() {
        XCTAssertNil(VolumeEjector.blocker(in: "umount(/Volumes/Share): Resource busy -- try 'diskutil unmount'"))
    }

    func testSystemAndOtherUsersProcessesAreNotOffered() {
        let me = getuid()
        func blocker(_ path: String, pid: pid_t = 4242) -> VolumeEjector.Blocker {
            .init(pid: pid, path: path, parentPath: nil)
        }
        XCTAssertTrue(VolumeEjector.mayQuit(blocker("/Users/me/.local/bin/uv"), owner: me))
        XCTAssertTrue(VolumeEjector.mayQuit(blocker("/bin/bash"), owner: me))
        XCTAssertFalse(VolumeEjector.mayQuit(blocker("/Users/me/.local/bin/uv"), owner: 0), "root's process")
        XCTAssertFalse(VolumeEjector.mayQuit(blocker("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"), owner: me))
        XCTAssertFalse(VolumeEjector.mayQuit(blocker("/usr/libexec/lsd"), owner: me))
        XCTAssertFalse(VolumeEjector.mayQuit(blocker("/bin/bash", pid: 1), owner: me), "launchd")
        XCTAssertFalse(VolumeEjector.mayQuit(blocker("/x/MTMR", pid: getpid()), owner: me), "MTMR itself")
    }

    func testQuittingEndsTheProcessAndItsChildren() throws {
        // A shell that started a child, like uv starting the tool's Python.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "/bin/sleep 60 & wait"]
        try shell.run()
        Thread.sleep(forTimeInterval: 0.3)
        let children = VolumeEjector.descendants(of: shell.processIdentifier)
        XCTAssertEqual(children.count, 1)

        // /bin/sh runs as /bin/bash; diskutil reports that path, so the test uses the real one too.
        let path = try XCTUnwrap(VolumeEjector.executablePath(of: shell.processIdentifier))
        let blocker = VolumeEjector.Blocker(pid: shell.processIdentifier, path: path, parentPath: nil)
        XCTAssertTrue(VolumeEjector.quit(blocker))
        shell.waitUntilExit()
        XCTAssertTrue(children.allSatisfy { kill($0, 0) != 0 }, "the child is gone too")
    }

    func testQuittingAProcessThatIsGoneIsNotAnError() {
        // The PID diskutil named may have ended by itself before the user answered the alert.
        let blocker = VolumeEjector.Blocker(pid: 99999, path: "/nonexistent/tool", parentPath: nil)
        XCTAssertTrue(VolumeEjector.quit(blocker))
    }
}
