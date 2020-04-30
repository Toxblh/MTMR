//
//  EventActions.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class EventAction {
    var closure: ((_ caller: CustomButtonTouchBarItem) -> Void)
    
    func setHidKeyClosure(keycode: Int32) -> EventAction {
        closure = { (_ caller: CustomButtonTouchBarItem) in
            HIDPostAuxKey(keycode)
        }
        return self
    }
    
    func setKeyPressClosure(keycode: Int) -> EventAction {
        closure = { (_ caller: CustomButtonTouchBarItem) in
           GenericKeyPress(keyCode: CGKeyCode(keycode)).send()
        }
        return self
    }
    
    func setAppleScriptClosure(appleScript: NSAppleScript) -> EventAction {
        closure = { (_ caller: CustomButtonTouchBarItem) in
            DispatchQueue.appleScriptQueue.async {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("error \(error) when handling apple script ")
                }
            }
        }
        return self
    }
    
    func setShellScriptClosure(executable: String, parameters: [String]) -> EventAction {
        closure = { (_ caller: CustomButtonTouchBarItem) in
            let task = Process()
            task.launchPath = executable
            task.arguments = parameters
            task.launch()
        }
        return self
    }
    
    func setOpenUrlClosure(url: String) -> EventAction {
        closure = { (_ caller: CustomButtonTouchBarItem) in
            if let url = URL(string: url), NSWorkspace.shared.open(url) {
                #if DEBUG
                    print("URL was successfully opened")
                #endif
            } else {
                print("error", url)
            }
        }
        return self
    }
    
    init() {
        self.closure = { (_ caller: CustomButtonTouchBarItem) in }
    }
    
    init(_ closure: @escaping (_ caller: CustomButtonTouchBarItem) -> Void) {
        self.closure = closure
    }
    
}

class LongTapEventAction: EventAction, Decodable {
    private enum CodingKeys: String, CodingKey {
        case longAction
        case longKeycode
        case longActionAppleScript
        case longExecutablePath
        case longShellArguments
        case longUrl
    }

    private enum LongActionTypeRaw: String, Decodable {
        case hidKey
        case keyPress
        case appleScript
        case shellScript
        case openUrl
    }
    
    required init(from decoder: Decoder) throws {
        super.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(LongActionTypeRaw.self, forKey: .longAction)

        switch type {
        case .some(.hidKey):
            let keycode = try container.decode(Int32.self, forKey: .longKeycode)

            _ = setHidKeyClosure(keycode: keycode)
        case .some(.keyPress):
            let keycode = try container.decode(Int.self, forKey: .longKeycode)

            _ = setKeyPressClosure(keycode: keycode)
        case .some(.appleScript):
            let source = try container.decode(Source.self, forKey: .longActionAppleScript)
            
            guard let appleScript = source.appleScript else {
                print("cannot create apple script")
                return
            }
            
            _ = setAppleScriptClosure(appleScript: appleScript)
        case .some(.shellScript):
            let executable = try container.decode(String.self, forKey: .longExecutablePath)
            let parameters = try container.decodeIfPresent([String].self, forKey: .longShellArguments) ?? []
           
            _ = setShellScriptClosure(executable: executable, parameters: parameters)
        case .some(.openUrl):
            let url = try container.decode(String.self, forKey: .longUrl)
            
            _ = setOpenUrlClosure(url: url)
        case .none:
            break
        }
    }
}

class SingleTapEventAction: EventAction, Decodable {
    private enum CodingKeys: String, CodingKey {
        case action
        case keycode
        case actionAppleScript
        case executablePath
        case shellArguments
        case url
    }
    
    private enum ActionTypeRaw: String, Decodable {
        case hidKey
        case keyPress
        case appleScript
        case shellScript
        case openUrl
    }
    
    required init(from decoder: Decoder) throws {
        super.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(ActionTypeRaw.self, forKey: .action)

        switch type {
        case .some(.hidKey):
            let keycode = try container.decode(Int32.self, forKey: .keycode)

            _ = setHidKeyClosure(keycode: keycode)
        case .some(.keyPress):
            let keycode = try container.decode(Int.self, forKey: .keycode)

            _ = setKeyPressClosure(keycode: keycode)
        case .some(.appleScript):
            let source = try container.decode(Source.self, forKey: .actionAppleScript)
            
            guard let appleScript = source.appleScript else {
                print("cannot create apple script")
                return
            }
            
            _ = setAppleScriptClosure(appleScript: appleScript)
        case .some(.shellScript):
            let executable = try container.decode(String.self, forKey: .executablePath)
            let parameters = try container.decodeIfPresent([String].self, forKey: .shellArguments) ?? []
           
            _ = setShellScriptClosure(executable: executable, parameters: parameters)
        case .some(.openUrl):
            let url = try container.decode(String.self, forKey: .url)
            
            _ = setOpenUrlClosure(url: url)
        case .none:
            break
        }
    }
}
