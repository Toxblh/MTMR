//
//  CPUBarItem.swift
//  MTMR
//
//  Created by bobrosoft on 17/08/2021.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

class CPUBarItem: CustomButtonTouchBarItem {
    private let refreshInterval: TimeInterval
    private var refreshQueue: DispatchQueue? = DispatchQueue(label: "mtmr.cpu")
    private let defaultSingleTapScript: NSAppleScript! = "activate application \"Activity Monitor\"\rtell application \"System Events\"\r\ttell process \"Activity Monitor\"\r\t\ttell radio button \"CPU\" of radio group 1 of group 2 of toolbar 1 of window 1 to perform action \"AXPress\"\r\tend tell\rend tell".appleScript

    init(identifier: NSTouchBarItem.Identifier, refreshInterval: TimeInterval) {
        self.refreshInterval = refreshInterval
        super.init(identifier: identifier, title: "⏳")
                
        // Set default image
        if self.image == nil {
            self.image = #imageLiteral(resourceName: "cpu").resize(maxSize: NSSize(width: 24, height: 24));
        }
        
        // Set default action
        if actions.filter({ $0.trigger == .singleTap }).isEmpty {
            actions.append(ItemAction(
                trigger: .singleTap,
                defaultTapAction
            ))
        }
        
        refreshAndSchedule()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func refreshAndSchedule() {
        DispatchQueue.main.async {
            // Get CPU load
            let usage = 100 - CPU.systemUsage().idle
            guard usage.isFinite else {
                return
            }
            
            // Choose color based on CPU load
            var color: NSColor? = nil
            var bgColor: NSColor? = nil
            if usage > 70 {
                color = .black
                bgColor = .yellow
            } else if usage > 30 {
                color = .yellow
            }
            
            // Update layout
            let attrTitle = NSMutableAttributedString.init(attributedString: String(format: "%.1f%%", usage).defaultTouchbarAttributedString)
            if let color = color {
                attrTitle.addAttributes([.foregroundColor: color], range: NSRange(location: 0, length: attrTitle.length))
            }
            self.attributedTitle = attrTitle
            self.backgroundColor = bgColor
        }
        
        refreshQueue?.asyncAfter(deadline: .now() + refreshInterval) { [weak self] in
            self?.refreshAndSchedule()
        }
    }

    func defaultTapAction() {
        refreshQueue?.async { [weak self] in
            self?.defaultSingleTapScript.executeAndReturnError(nil)
        }
    }
    
    deinit {
        refreshQueue?.suspend()
        refreshQueue = nil
    }
}
