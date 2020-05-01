//
//  SwipeItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 3/29/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation
import Foundation

class SwipeItem: CustomTouchBarItem {
    private var scriptApple: NSAppleScript?
    private var scriptBash: String?
    private var direction: String
    private var fingers: Int
    private var minOffset: Float
    
    private enum CodingKeys: String, CodingKey {
        case sourceApple
        case sourceBash
        case direction
        case fingers
        case minOffset
    }
    
    override class var typeIdentifier: String {
        return "swipe"
    }
    
    init?(identifier: NSTouchBarItem.Identifier, direction: String, fingers: Int, minOffset: Float, sourceApple: SourceProtocol?, sourceBash: SourceProtocol?) {
        self.direction = direction
        self.fingers = fingers
        self.scriptBash = sourceBash?.string
        self.scriptApple = sourceApple?.appleScript
        self.minOffset = minOffset
        super.init(identifier: identifier)
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.scriptApple = try container.decodeIfPresent(Source.self, forKey: .sourceApple)?.appleScript
        self.scriptBash = try container.decodeIfPresent(Source.self, forKey: .sourceBash)?.string
        self.direction = try container.decode(String.self, forKey: .direction)
        self.fingers = try container.decode(Int.self, forKey: .fingers)
        self.minOffset = try container.decodeIfPresent(Float.self, forKey: .minOffset) ?? 0.0
        
        
        try super.init(from: decoder)
    }
    
    func processEvent(offset: CGFloat, fingers: Int) {
        if direction == "right" && Float(offset) > self.minOffset && self.fingers == fingers {
            self.execute()
        }
        if direction == "left" && Float(offset) < -self.minOffset && self.fingers == fingers {
            self.execute()
        }
    }

    func execute() {
        if scriptApple != nil {
            DispatchQueue.appleScriptQueue.async {
                var error: NSDictionary?
                self.scriptApple?.executeAndReturnError(&error)
                if let error = error {
                    print("SwipeItem apple script error: \(error)")
                    return
                }
            }
        }
        if scriptBash != nil {
            DispatchQueue.shellScriptQueue.async {
                let task = Process()
                task.launchPath = "/bin/bash"
                task.arguments = ["-c", self.scriptBash!]
                task.launch()
                task.waitUntilExit()

                
                if (task.terminationStatus != 0) {
                    print("SwipeItem bash script error. Status: \(task.terminationStatus)")
                }
            }
        }
    }
}
