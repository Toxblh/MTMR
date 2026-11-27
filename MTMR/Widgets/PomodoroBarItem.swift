//
//  PomodoroBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 10.05.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa
import UserNotifications

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

    private let defaultTitle = "🍅 "
    private let workSeconds: Int
    private let restSeconds: Int
    private let notify: (Bool) -> Void
    private var timer: DispatchSourceTimer?
    private var timeLeft = 0

    init(identifier: NSTouchBarItem.Identifier, workTime: TimeInterval, restTime: TimeInterval,
         notify: @escaping (Bool) -> Void = PomodoroBarItem.sendNotification) {
        workSeconds = PomodoroDuration.seconds(workTime, fallback: PomodoroDuration.defaultWork)
        restSeconds = PomodoroDuration.seconds(restTime, fallback: PomodoroDuration.defaultRest)
        self.notify = notify
        super.init(identifier: identifier, title: defaultTitle)
        actions.append(contentsOf: [
            ItemAction(trigger: .singleTap) { [weak self] in self?.startStopWork() },
            ItemAction(trigger: .longTap) { [weak self] in self?.startStopRest() }
        ])
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func startStopWork() {
        startStopTimer(isWork: true)
    }

    @objc func startStopRest() {
        startStopTimer(isWork: false)
    }

    private func startStopTimer(isWork: Bool) {
        guard timer == nil else {
            reset()
            return
        }
        timeLeft = isWork ? workSeconds : restSeconds
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        // Keep the active item available through the group's weak cache when its view is released.
        timer.setEventHandler { self.tick(isWork: isWork) }
        self.timer = timer
        timer.resume()

        NSSound.beep()
    }

    private func reset() {
        timer?.setEventHandler(handler: nil)
        timer?.cancel()
        timer = nil
        title = defaultTitle
    }

    private func tick(isWork: Bool) {
        guard let timer else { return }
        let elapsed = Int(clamping: timer.data)
        guard timeLeft >= elapsed else {
            reset()
            notify(isWork)
            return
        }
        timeLeft -= elapsed
        title = defaultTitle + " " + PomodoroDuration.display(timeLeft)
    }

    private static func sendNotification(isWork: Bool) {
        // UserNotifications replaces the deprecated NSUserNotification(Center) (macOS 11).
        // Authorization is requested lazily on first use; if the user declines, no banner is shown.
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Pomodoro"
        content.body = isWork ? "it's time to rest your mind!" : "It's time to work!"
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        // UNNotificationSound(named:) only finds sounds in the app bundle / ~/Library/Sounds, not the
        // system "Submarine" sound NSUserNotification used, so it is played directly.
        NSSound(named: "Submarine")?.play()
    }
}
