//
//  WidgetProtocol.swift
//  MTMR
//
//  Created by Anton Palgunov on 20/10/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

protocol Widget {
    static var name: String { get }
    static var identifier: String { get }
}

extension Timer {
    /// Widget timers live on the main run loop. Callers capture their owner weakly and
    /// invalidate the timer on release, including when only a preview was using a group.
    @MainActor static func widgetTimer(every interval: TimeInterval, mode: RunLoop.Mode = .default,
                                       action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: mode)
        return timer
    }
}
