//
//  NetworkBarItem.swift
//  MTMR
//
//  Created by Anton Palgunov on 23/02/2019.
//  Copyright © 2019 Anton Palgunov. All rights reserved.
//

import Foundation

class NetworkBarItem: CustomButtonTouchBarItem, Widget {
    static var name: String = "network"
    static var identifier: String = "com.toxblh.mtmr.network"
    
    private let flip: Bool
    private let process = Process()
    private let pipe = Pipe()
    private var dataObserver: NSObjectProtocol?
    private let units: String
    
    init(identifier: NSTouchBarItem.Identifier, flip: Bool = false, units: String) {
        self.flip = flip
        self.units = units
        super.init(identifier: identifier, title: " ")
        startMonitoringProcess()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func startMonitoringProcess() {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["netstat", "-w1", "-l", "en0"]
        process.standardOutput = pipe
        let handle = pipe.fileHandleForReading
        dataObserver = NotificationCenter.default.addObserver(forName: .NSFileHandleDataAvailable, object: handle,
                                                               queue: .main) { [weak self] _ in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
                let fields = line.split(whereSeparator: \.isWhitespace)
                if fields.count >= 6, let down = UInt64(fields[2]), let up = UInt64(fields[5]) {
                    self.setTitle(up: self.getHumanizeSize(speed: up), down: self.getHumanizeSize(speed: down))
                }
            }
            handle.waitForDataInBackgroundAndNotify(forModes: [.common])
        }
        do {
            try process.run()
            handle.waitForDataInBackgroundAndNotify(forModes: [.common])
        } catch {
            title = "error"
        }
    }

    deinit {
        if let dataObserver { NotificationCenter.default.removeObserver(dataObserver) }
        if process.isRunning { process.terminate() }
        try? pipe.fileHandleForReading.close()
    }

    func getHumanizeSize(speed: UInt64) -> String {
        let humanText: String
        
        func speedB(speed: UInt64)-> String {
            return String(format: "%.0f", Double(speed)) + " B/s"
        }
        
        func speedKB(speed: UInt64)-> String {
            return String(format: "%.1f", Double(speed) / 1024) + " KB/s"
        }
        
        func speedMB(speed: UInt64)-> String {
            return String(format: "%.1f", Double(speed) / (1024 * 1024)) + " MB/s"
        }
        
        func speedGB(speed: UInt64)-> String {
            return String(format: "%.2f", Double(speed) / (1024 * 1024 * 1024)) + " GB/s"
        }
        
        switch self.units {
        case "B/s":
            humanText = speedB(speed: speed)
        case "KB/s":
            humanText = speedKB(speed: speed)
        case "MB/s":
            humanText = speedMB(speed: speed)
        case "GB/s":
            humanText = speedGB(speed: speed)
        default:
            if speed < 1024 {
                humanText = speedB(speed: speed)
            } else if speed < (1024 * 1024) {
                humanText = speedKB(speed: speed)
            } else if speed < (1024 * 1024 * 1024) {
                humanText = speedMB(speed: speed)
            } else {
                humanText = speedGB(speed: speed)
            }
        }

        return humanText
    }
    
    func appendUpSpeed(appendString: NSMutableAttributedString, up: String, titleFont: NSFont, newStr: Bool = false) {
        appendString.append(NSMutableAttributedString(
            string: newStr ? "\n↑" : "↑",
            attributes: [
                NSAttributedString.Key.foregroundColor: NSColor.blue,
                NSAttributedString.Key.font: titleFont,
                ]))
        
        appendString.append(NSMutableAttributedString(
            string: up,
            attributes: [
                NSAttributedString.Key.font: titleFont,
                ]))
    }
    
    func appendDownSpeed(appendString: NSMutableAttributedString, down: String, titleFont: NSFont, newStr: Bool = false) {
        appendString.append(NSMutableAttributedString(
            string: newStr ? "\n↓" : "↓",
            attributes: [
                NSAttributedString.Key.foregroundColor: NSColor.red,
                NSAttributedString.Key.font: titleFont,
                ]))
            
            appendString.append(NSMutableAttributedString(
                string: down,
                attributes: [
                    NSAttributedString.Key.font: titleFont
                ]))
    }
    
    func setTitle(up: String, down: String) {
        let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: NSFont.Weight.light)
        
        let newTitle: NSMutableAttributedString = NSMutableAttributedString(string: "")
        
        if (self.flip) {
            appendUpSpeed(appendString: newTitle, up: up, titleFont: titleFont)
            appendDownSpeed(appendString: newTitle, down: down, titleFont: titleFont, newStr: true)
        } else {
            appendDownSpeed(appendString: newTitle, down: down, titleFont: titleFont)
            appendUpSpeed(appendString: newTitle, up: up, titleFont: titleFont, newStr: true)
        }
        
        
        self.attributedTitle = newTitle
    }
}
