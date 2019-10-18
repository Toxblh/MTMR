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
    
    init(identifier: NSTouchBarItem.Identifier, flip: Bool = false) {
        self.flip = flip
        super.init(identifier: identifier, title: " ")
        startMonitoringProcess()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startMonitoringProcess() {
        var pipe: Pipe
        var outputHandle: FileHandle
        var bandwidthProcess: Process?
        var dSpeed: UInt64?
        var uSpeed: UInt64?
        var curr: Array<Substring>?
        var dataAvailable: NSObjectProtocol?

        pipe = Pipe()
        bandwidthProcess = Process()
        bandwidthProcess?.launchPath = "/usr/bin/env"
        bandwidthProcess?.arguments = ["netstat", "-w1", "-l", "en0"]
        bandwidthProcess?.standardOutput = pipe

        outputHandle = pipe.fileHandleForReading
        outputHandle.waitForDataInBackgroundAndNotify(forModes: [RunLoop.Mode.common])

        dataAvailable = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSFileHandleDataAvailable,
            object: outputHandle,
            queue: nil
        ) { _ -> Void in
            let data = pipe.fileHandleForReading.availableData
            if data.count > 0 {
                if let str = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
                    curr = [""]
                    curr = str
                        .replacingOccurrences(of: "  ", with: " ")
                        .split(separator: " ")
                    if curr == nil || (curr?.count)! < 6 {} else {
                        if Int64(curr![2]) == nil {} else {
                            dSpeed = UInt64(curr![2])
                            uSpeed = UInt64(curr![5])

                            self.setTitle(up: self.getHumanizeSize(speed: uSpeed!), down: self.getHumanizeSize(speed: dSpeed!))
                        }
                    }
                }
                outputHandle.waitForDataInBackgroundAndNotify()
            } else if let dataAvailable = dataAvailable {
                NotificationCenter.default.removeObserver(dataAvailable)
            }
        }

        var dataReady: NSObjectProtocol?
        dataReady = NotificationCenter.default.addObserver(
            forName: Process.didTerminateNotification,
            object: outputHandle,
            queue: nil
        ) { _ -> Void in
            print("Task terminated!")
            if let observer = dataReady {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        bandwidthProcess?.launch()
    }

    func getHumanizeSize(speed: UInt64) -> String {
        let humanText: String

        if speed < 1024 {
            humanText = String(format: "%.0f", Double(speed)) + " B/s"
        } else if speed < (1024 * 1024) {
            humanText = String(format: "%.1f", Double(speed) / 1024) + " KB/s"
        } else if speed < (1024 * 1024 * 1024) {
            humanText = String(format: "%.1f", Double(speed) / (1024 * 1024)) + " MB/s"
        } else {
            humanText = String(format: "%.2f", Double(speed) / (1024 * 1024 * 1024)) + " GB/s"
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
