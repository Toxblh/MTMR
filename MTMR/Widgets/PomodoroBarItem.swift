//
//  PomodoroBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 10.05.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

class PomodoroBarItem: CustomButtonTouchBarItem, Widget {
    static let identifier = "com.toxblh.mtmr.pomodoro."
    static let name = "pomodoro"
    static let decoder: ParametersDecoder = { decoder in
        enum CodingKeys: String, CodingKey {
            case workTime
            case restTime
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let workTime = try container.decodeIfPresent(Double.self, forKey: .workTime)
        let restTime = try container.decodeIfPresent(Double.self, forKey: .restTime)

        return (
            item: .pomodoro(workTime: workTime ?? 1500.00, restTime: restTime ?? 300),
            actions: [],
            legacyAction: .none,
            legacyLongAction: .none,
            parameters: [:]
        )
    }

    private enum TimeTypes {
        case work
        case rest
        case none
    }

    private let defaultTitle = "🍅 "
    private let workTime: TimeInterval
    private let restTime: TimeInterval
    private var typeTime: TimeTypes = .none
    private var timer: DispatchSourceTimer?

    private var timeLeft: Int = 0
    private var timeLeftString: String {
        return String(format: "%.2i:%.2i", timeLeft / 60, timeLeft % 60)
    }

    init(identifier: NSTouchBarItem.Identifier, workTime: TimeInterval, restTime: TimeInterval) {
        self.workTime = workTime
        self.restTime = restTime
        super.init(identifier: identifier, title: defaultTitle)
        actions.append(contentsOf: [
            ItemAction(trigger: .singleTap) { [weak self] in self?.startStopWork() },
            ItemAction(trigger: .longTap) { [weak self] in self?.startStopRest() }
        ])
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.cancel()
        timer = nil
    }

    @objc func startStopWork() {
        typeTime = .work
        startStopTimer()
    }

    @objc func startStopRest() {
        typeTime = .rest
        startStopTimer()
    }

    func startStopTimer() {
        timer == nil ? start() : reset()
    }

    private func start() {
        timeLeft = Int(typeTime == .work ? workTime : restTime)
        let queue: DispatchQueue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer?.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer?.setEventHandler(handler: tick)
        timer?.resume()

        NSSound.beep()
    }

    private func finish() {
        if typeTime != .none {
            sendNotification()
        }

        reset()
    }

    private func reset() {
        typeTime = .none
        timer?.cancel()
        timer = nil
        title = defaultTitle
    }

    private func tick() {
        timeLeft -= 1
        DispatchQueue.main.async {
            if self.timeLeft >= 0 {
                self.title = self.defaultTitle + " " + self.timeLeftString
            } else {
                self.finish()
            }
        }
    }

    private func sendNotification() {
        let notification: NSUserNotification = NSUserNotification()
        notification.title = "Pomodoro"
        notification.informativeText = typeTime == .work ? "it's time to rest your mind!" : "It's time to work!"
        notification.soundName = "Submarine"
        NSUserNotificationCenter.default.deliver(notification)
    }
}
