//
//  ShellScriptTouchBarItem.swift
//  MTMR
//
//  Created by bobr on 08/08/2019.
//  Copyright © 2019 Anton Palgunov. All rights reserved.
//
import Foundation

class ShellScriptTouchBarItem: CustomButtonTouchBarItem {
    private let interval: TimeInterval
    private let source: String
    private var forceHideConstraint: NSLayoutConstraint!
    
    private enum CodingKeys: String, CodingKey {
        case source
        case refreshInterval
    }
    
    override class var typeIdentifier: String {
        return "shellScriptTitledButton"
    }
    
    init?(identifier: NSTouchBarItem.Identifier, source: SourceProtocol, interval: TimeInterval) {
        self.interval = interval
        self.source = source.string ?? "echo No \"source\""
        super.init(identifier: identifier, title: "⏳")
        
        initScripts()
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decode(Source.self, forKey: .source)
        self.source = source.string ?? "echo No \"source\""
        self.interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 1800.0
        
        try super.init(from: decoder)
        self.title = "⏳"
        
        initScripts()
    }
    
    func initScripts() {
        forceHideConstraint = view.widthAnchor.constraint(equalToConstant: 0)
        
        DispatchQueue.shellScriptQueue.async {
            self.refreshAndSchedule()
        }
    }
    
    func refreshAndSchedule() {
        // Execute script and get result
        let scriptResult = execute(source)
        
        // Apply returned text attributes (if they were returned) to our result string
        let helper = AMR_ANSIEscapeHelper.init()
        helper.defaultStringColor = NSColor.white
        helper.font = "1".defaultTouchbarAttributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let title = NSMutableAttributedString.init(attributedString: helper.attributedString(withANSIEscapedString: scriptResult) ?? NSAttributedString(string: ""))
        title.addAttributes([.baselineOffset: 1], range: NSRange(location: 0, length: title.length))
        let newBackgoundColor: NSColor? = title.length != 0 ? title.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor : nil
        
        // Update UI
        DispatchQueue.main.async { [weak self, newBackgoundColor] in
            if (newBackgoundColor != self?.backgroundColor) { // performance optimization because of reinstallButton
                self?.backgroundColor = newBackgoundColor
            }
            self?.setAttributedTitle(title)
            self?.forceHideConstraint.isActive = scriptResult == ""
        }
        
        // Schedule next update
        DispatchQueue.shellScriptQueue.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.refreshAndSchedule()
        }
    }
    
    func execute(_ command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        var output: String = NSString(data: data, encoding: String.Encoding.utf8.rawValue) as String? ?? ""
        
        if (output == "" && task.terminationStatus != 0) {
            output = "error"
        }
        
        return output.replacingOccurrences(of: "\\n+$", with: "", options: .regularExpression)
    }
}

extension DispatchQueue {
    static let shellScriptQueue = DispatchQueue(label: "mtmr.shellscript")
}
