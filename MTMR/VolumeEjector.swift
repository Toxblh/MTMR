//
//  VolumeEjector.swift
//  MTMR
//
//  Finds the external volumes an eject button should eject, in an order that works, and ejects them.
//

import Foundation
import DiskArbitration

enum VolumeEjector {
    /// What kind of storage a volume is on. It decides how the volume is ejected.
    enum Kind: Equatable {
        /// A physical drive (USB, Thunderbolt, SD card, ...) and its whole disk, e.g. "disk8".
        case drive(disk: String)
        /// An attached disk image and the image's own disk, e.g. "disk11" (not the synthesized APFS container).
        case diskImage(disk: String)
        /// A network share (SMB, AFP, NFS, WebDAV).
        case network
        /// Not classified (not yet looked up, or diskutil knew nothing about it).
        case unknown

        var disk: String? {
            switch self {
            case let .drive(disk), let .diskImage(disk): return disk
            case .network, .unknown: return nil
            }
        }
    }

    struct Volume: Equatable {
        let name: String
        let path: String
        var kind: Kind = .unknown
    }

    /// How one volume is ejected.
    enum Action: Equatable {
        /// `diskutil eject <disk>`: unmounts every volume of the drive, then ejects it (Finder's eject).
        case ejectDrive(disk: String)
        /// `diskutil eject <image disk>`: detaches the image, which also closes its file.
        case detachImage(disk: String)
        /// `diskutil unmount <path>`: only this volume, because another volume of the same drive or image was not
        /// chosen and stays in use.
        case unmountVolume
        /// `umount <path>`: a network share has no disk to eject.
        case unmountShare
    }

    /// A mounted or attached disk image: where its file lives, its whole-disk device and its mount points.
    struct DiskImage: Equatable {
        let imagePath: String
        let mountPoints: [String]
        /// The image's own device, e.g. "/dev/disk11". The volume of an APFS image sits on a second, synthesized
        /// disk ("/dev/disk12"); ejecting that one leaves the image attached and its file open.
        let device: String?

        init(imagePath: String, mountPoints: [String], device: String? = nil) {
            self.imagePath = imagePath
            self.mountPoints = mountPoints
            self.device = device
        }

        func isStored(on volume: Volume) -> Bool {
            imagePath.hasPrefix(volume.path.hasSuffix("/") ? volume.path : volume.path + "/")
        }
    }

    /// External volumes the user can see in Finder: not the startup disk, not internal, not hidden.
    /// A USB SSD reports "not ejectable" (only removable media is), so that key is not used to filter.
    static func mountedVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsRootFileSystem != true,
                  // Disk images report nil here, external drives false.
                  values.volumeIsInternal != true,
                  let name = values.volumeName
            else { return nil }
            return Volume(name: name, path: url.standardizedFileURL.path)
        }
    }

    /// Looks up what a volume is on. Starts `diskutil`, so it is only called when ejecting, not for the icon state.
    static func classified(_ volume: Volume) -> Volume {
        var result = volume
        let isLocal = (try? URL(fileURLWithPath: volume.path).resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal
        var info: [String: Any]?
        if isLocal != false, let data = try? run("/usr/sbin/diskutil", ["info", "-plist", volume.path]) {
            info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        }
        result.kind = kind(diskutilInfo: info, isLocal: isLocal)
        return result
    }

    /// The kind from `diskutil info -plist` of the volume.
    /// - `BusProtocol` is "Disk Image" for images, otherwise the bus of the drive ("USB", "Thunderbolt", "SD").
    /// - The disk to eject is the physical one: for APFS the whole disk of the container's physical store
    ///   (an APFS volume sits on a synthesized container disk that cannot be ejected on its own), otherwise
    ///   `ParentWholeDisk`.
    static func kind(diskutilInfo info: [String: Any]?, isLocal: Bool?) -> Kind {
        if isLocal == false { return .network }
        guard let info = info else { return .unknown }
        let store = (info["APFSPhysicalStores"] as? [[String: Any]])?.first?["APFSPhysicalStore"] as? String
        guard let disk = (store.map(wholeDisk) ?? (info["ParentWholeDisk"] as? String)), !disk.isEmpty else { return .unknown }
        return (info["BusProtocol"] as? String) == "Disk Image" ? .diskImage(disk: disk) : .drive(disk: disk)
    }

    /// "disk11s2" -> "disk11".
    static func wholeDisk(_ identifier: String) -> String {
        guard let range = identifier.range(of: #"^disk[0-9]+"#, options: .regularExpression) else { return identifier }
        return String(identifier[range])
    }

    /// The action for each planned volume.
    /// - A drive or image is ejected as a whole only if all of its mounted volumes are being ejected; the whole-disk
    ///   eject goes with the last of them, the earlier ones are unmounted. If any of its volumes was not chosen, only the
    ///   chosen volumes are unmounted and the drive or image stays.
    /// - A network share is unmounted. An unknown volume is only unmounted, the safe choice.
    static func actions(for planned: [Volume], mounted: [Volume]) -> [Action] {
        planned.enumerated().map { index, volume in
            switch volume.kind {
            case .network: return .unmountShare
            case .unknown: return .unmountVolume
            case let .drive(disk), let .diskImage(disk):
                let siblings = mounted.filter { $0.kind.disk == disk }
                guard siblings.allSatisfy({ planned.contains($0) }) else { return .unmountVolume }
                let isLast = !planned[(index + 1)...].contains { $0.kind.disk == disk }
                guard isLast else { return .unmountVolume }
                if case .diskImage = volume.kind { return .detachImage(disk: disk) }
                return .ejectDrive(disk: disk)
            }
        }
    }

    /// Attached disk images from `hdiutil info -plist`, the public way to learn which file backs an image.
    static func diskImages() -> [DiskImage] {
        guard let result = try? run("/usr/bin/hdiutil", ["info", "-plist"]) else { return [] }
        return parseDiskImages(plist: result)
    }

    static func parseDiskImages(plist data: Data) -> [DiskImage] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = root["images"] as? [[String: Any]]
        else { return [] }
        return images.compactMap { image in
            guard let path = image["image-path"] as? String else { return nil }
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            let mountPoints = entities.compactMap { $0["mount-point"] as? String }
            // hdiutil lists the whole disk first, then its partitions and synthesized containers.
            let device = entities.compactMap { $0["dev-entry"] as? String }.first
            return DiskImage(imagePath: path, mountPoints: mountPoints, device: device)
        }
    }

    /// The volumes to eject for the names in a preset, in eject order.
    ///
    /// - An empty `names` list means every external volume.
    /// - A disk image whose file lives on a chosen volume is ejected too, before that volume: macOS refuses to
    ///   eject a volume while an image stored on it is attached, and the image is unusable once its drive is gone.
    /// - Names that are not mounted are skipped.
    static func plan(names: [String], mounted: [Volume], images: [DiskImage]) -> [Volume] {
        var targets = names.isEmpty ? mounted : mounted.filter { names.contains($0.name) }

        func hostedImages(on host: Volume) -> [Volume] {
            let mountPoints = images.filter { $0.isStored(on: host) }.flatMap(\.mountPoints)
            return mounted.filter { mountPoints.contains($0.path) }
        }

        var index = 0
        while index < targets.count {
            for volume in hostedImages(on: targets[index]) where !targets.contains(volume) {
                targets.append(volume)
            }
            index += 1
        }

        // Eject a volume only after every chosen image stored on it.
        var ordered: [Volume] = []
        var remaining = targets
        while !remaining.isEmpty {
            let ready = remaining.filter { host in
                hostedImages(on: host).allSatisfy { !remaining.contains($0) || $0 == host }
            }
            // A cycle cannot happen with real images; keep the order given rather than loop forever.
            let next = ready.isEmpty ? remaining : ready
            ordered.append(contentsOf: next)
            remaining.removeAll { next.contains($0) }
        }
        return ordered
    }

    enum Outcome {
        case ejected([String])
        case nothingMounted
        case failed(volume: String, error: Error, ejected: [String])
    }

    /// How often a volume is tried while it is busy, and the pause between tries.
    /// Short pauses find the gaps between the attempts of a tool that keeps attaching an image (measured on nested
    /// test images); the total of about 5 s is how long a truly busy volume makes the user wait for the message.
    static let attempts = 10
    static let retryDelay: TimeInterval = 0.5

    /// Ejects off the main thread (unmounting can take seconds) and reports on the main thread.
    /// Stops at the first failure: if an image on a drive cannot be ejected, the drive cannot be either.
    /// Never forces: a busy volume is reported, not torn away from the app using it.
    static func eject(names: [String], completion: @escaping (Outcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = ejectNow(names: names)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// Synchronous version of `eject`; call it off the main thread.
    static func ejectNow(names: [String]) -> Outcome {
        let images = diskImages()
        let mounted = mountedVolumes().map(classified)
        let volumes = plan(names: names, mounted: mounted, images: images)
        guard !volumes.isEmpty else { return .nothingMounted }
        let steps = actions(for: volumes, mounted: mounted)

        // Something may attach an image from a volume again as soon as it is detached (an auto-mount agent,
        // a backup tool). While images are detached from a volume, new disk-image mounts are refused.
        let hostsImages = volumes.contains { volume in images.contains { $0.isStored(on: volume) } }
        let blocker = hostsImages ? MountBlocker() : nil
        defer { blocker?.stop() }

        var done: [String] = []
        for (volume, action) in zip(volumes, steps) {
            NSLog("MTMR: \"\(volume.name)\" is \(volume.kind), \(action)")
            do {
                try perform(action, on: volume)
                done.append(volume.name)
            } catch {
                return .failed(volume: volume.name, error: error, ejected: done)
            }
        }
        return .ejected(done)
    }

    /// Tries a volume a few times: an image stored on it may have been attached again meanwhile, and indexing
    /// or a closing app can keep it busy for a moment. Each try first detaches the images stored on it again.
    /// Never forces. diskutil names the process that keeps a volume busy; NSWorkspace only says "in use".
    private static func perform(_ action: Action, on volume: Volume) throws {
        var lastError: Error?
        for attempt in 0 ..< attempts {
            if attempt > 0 { Thread.sleep(forTimeInterval: retryDelay) }
            do {
                // Best effort: such an image may be gone already, or be detaching. If it still blocks the volume,
                // the step below fails with the real reason.
                for image in diskImages() where image.isStored(on: volume) {
                    if let device = image.device { _ = try? run("/usr/sbin/diskutil", ["eject", device]) }
                }
                switch action {
                case let .ejectDrive(disk), let .detachImage(disk):
                    try run("/usr/sbin/diskutil", ["eject", disk])
                case .unmountVolume:
                    try run("/usr/sbin/diskutil", ["unmount", volume.path])
                case .unmountShare:
                    try run("/sbin/umount", [volume.path])
                }
                return
            } catch {
                NSLog("MTMR: eject \"\(volume.name)\" try \(attempt + 1) of \(attempts) failed: \(error.localizedDescription)")
                lastError = error
            }
        }
        throw lastError ?? NSError(domain: "MTMR.Eject", code: 1)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: message.isEmpty ? data : message, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "MTMR.Eject", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "\(tool) failed" : text])
        }
        return data
    }
}

/// Refuses to mount disk images while it exists (DiskArbitration mount approval, the mechanism Finder and
/// backup tools use to keep a disk from mounting). An image that cannot mount is not left in use on the drive.
private final class MountBlocker {
    private let session: DASession?
    private let queue = DispatchQueue(label: "MTMR.eject.mountblocker")

    /// A C function pointer: unregistering needs the very same pointer that was registered.
    private static let approval: DADiskMountApprovalCallback = { disk, _ in
        guard let description = DADiskCopyDescription(disk) as? [CFString: Any],
              (description[kDADiskDescriptionDeviceModelKey] as? String) == "Disk Image"
                || (description[kDADiskDescriptionDeviceProtocolKey] as? String) == "Disk Image"
        else { return nil }
        let reason = "MTMR is ejecting the drive this disk image is stored on." as CFString
        return Unmanaged.passRetained(DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnBusy), reason))
    }

    init() {
        session = DASessionCreate(kCFAllocatorDefault)
        guard let session = session else { return }
        DASessionSetDispatchQueue(session, queue)
        DARegisterDiskMountApprovalCallback(session, nil, Self.approval, nil)
    }

    func stop() {
        guard let session = session else { return }
        // On the session's queue, so no approval is still running when this returns.
        queue.sync {
            DAUnregisterCallback(session, unsafeBitCast(Self.approval, to: UnsafeMutableRawPointer.self), nil)
            DASessionSetDispatchQueue(session, nil)
        }
    }
}
