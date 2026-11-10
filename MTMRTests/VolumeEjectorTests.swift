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
}
