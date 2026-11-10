//
//  VolumeEjector.swift
//  MTMR
//
//  Finds the external volumes an eject button should eject, in an order that works, and ejects them.
//

import AppKit

enum VolumeEjector {
    struct Volume: Equatable {
        let name: String
        let path: String
    }

    /// A mounted disk image: where its file lives and where its volumes are mounted.
    struct DiskImage: Equatable {
        let imagePath: String
        let mountPoints: [String]
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

    /// Mounted disk images from `hdiutil info -plist`, the public way to learn which file backs an image.
    static func diskImages() -> [DiskImage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parseDiskImages(plist: data)
    }

    static func parseDiskImages(plist data: Data) -> [DiskImage] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = root["images"] as? [[String: Any]]
        else { return [] }
        return images.compactMap { image in
            guard let path = image["image-path"] as? String else { return nil }
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            let mountPoints = entities.compactMap { $0["mount-point"] as? String }
            return DiskImage(imagePath: path, mountPoints: mountPoints)
        }
    }

    /// The volumes to eject for the names in a preset, in eject order.
    ///
    /// - An empty `names` list means every external volume.
    /// - A disk image whose file lives on a chosen volume is ejected too, before that volume: macOS refuses to
    ///   eject a volume while an image stored on it is attached (XcodeData.sparsebundle on T7, for example),
    ///   and the image is unusable once its drive is gone anyway.
    /// - Names that are not mounted are skipped.
    static func plan(names: [String], mounted: [Volume], images: [DiskImage]) -> [Volume] {
        var targets = names.isEmpty ? mounted : mounted.filter { names.contains($0.name) }

        func hostedImages(on host: Volume) -> [Volume] {
            let prefix = host.path.hasSuffix("/") ? host.path : host.path + "/"
            let mountPoints = images.filter { $0.imagePath.hasPrefix(prefix) }.flatMap(\.mountPoints)
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

    /// Ejects off the main thread (unmounting can take seconds) and reports on the main thread.
    /// Stops at the first failure: if an image on a drive cannot be ejected, the drive cannot be either.
    /// Never forces: a busy volume is reported, not torn away from the app using it.
    static func eject(names: [String], completion: @escaping (Outcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let volumes = plan(names: names, mounted: mountedVolumes(), images: diskImages())
            var done: [String] = []
            var outcome = Outcome.nothingMounted
            for volume in volumes {
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: volume.path))
                    done.append(volume.name)
                    outcome = .ejected(done)
                } catch {
                    outcome = .failed(volume: volume.name, error: error, ejected: done)
                    break
                }
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}
