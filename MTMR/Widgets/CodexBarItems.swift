// Codex-specific Touch Bar widgets.

import Foundation
import AppKit

/// A compact Codex allowance meter that pairs the native Touch Bar container
/// with SILO's green/amber/red quota states. The meter asks the locally
/// authenticated Codex app-server for a fresh snapshot every refresh cycle.
final class CodexQuotaBarItem: NSCustomTouchBarItem {
    private let refreshInterval: TimeInterval
    private let refreshQueue = DispatchQueue(label: "mtmr.codex-quota", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let quotaView = CodexQuotaView(frame: NSRect(x: 0, y: 0, width: 230, height: 30))

    init(identifier: NSTouchBarItem.Identifier, refreshInterval: TimeInterval) {
        self.refreshInterval = max(5, refreshInterval)
        super.init(identifier: identifier)
        view = quotaView
        refreshAndSchedule()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refreshAndSchedule() {
        refreshQueue.async { [weak self] in
            self?.refresh()
        }

        let timer = DispatchSource.makeTimerSource(queue: refreshQueue)
        timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        self.timer = timer
        timer.resume()
    }

    private func refresh() {
        let snapshot = CodexQuotaReader.snapshot()
        DispatchQueue.main.async { [weak self] in
            self?.quotaView.setSnapshot(snapshot)
        }
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

private final class CodexQuotaView: NSView {
    private let planLabel = NSTextField(labelWithString: "CODEX")
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private let valueLabel = NSTextField(labelWithString: "—")
    private let resetLabel = NSTextField(labelWithString: "↻ —")
    private var fillWidthConstraint: NSLayoutConstraint!
    private let maximumFillWidth: CGFloat = 214

    private let successColor = NSColor(
        srgbRed: 82.0 / 255.0,
        green: 182.0 / 255.0,
        blue: 142.0 / 255.0,
        alpha: 1
    )
    private let warningColor = NSColor(
        srgbRed: 221.0 / 255.0,
        green: 161.0 / 255.0,
        blue: 71.0 / 255.0,
        alpha: 1
    )
    private let dangerColor = NSColor(
        srgbRed: 239.0 / 255.0,
        green: 116.0 / 255.0,
        blue: 107.0 / 255.0,
        alpha: 1
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.13).cgColor

        planLabel.translatesAutoresizingMaskIntoConstraints = false
        planLabel.textColor = NSColor(white: 1, alpha: 0.64)
        planLabel.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
        planLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.wantsLayer = true
        progressTrack.layer?.cornerRadius = 2
        progressTrack.layer?.backgroundColor = NSColor(white: 1, alpha: 0.20).cgColor

        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressFill.wantsLayer = true
        progressFill.layer?.cornerRadius = 2
        progressFill.layer?.backgroundColor = successColor.cgColor

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.alignment = .right
        valueLabel.textColor = .white
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        valueLabel.lineBreakMode = .byClipping

        resetLabel.translatesAutoresizingMaskIntoConstraints = false
        resetLabel.alignment = .right
        resetLabel.textColor = NSColor(white: 1, alpha: 0.64)
        resetLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        resetLabel.lineBreakMode = .byClipping

        addSubview(planLabel)
        addSubview(progressTrack)
        progressTrack.addSubview(progressFill)
        addSubview(valueLabel)
        addSubview(resetLabel)

        fillWidthConstraint = progressFill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            planLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            planLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            planLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -6),
            progressTrack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            progressTrack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            progressTrack.widthAnchor.constraint(equalToConstant: maximumFillWidth),
            progressTrack.heightAnchor.constraint(equalToConstant: 4),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fillWidthConstraint,
            valueLabel.leadingAnchor.constraint(equalTo: planLabel.trailingAnchor, constant: 7),
            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: resetLabel.leadingAnchor, constant: -8),
            resetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            resetLabel.centerYAnchor.constraint(equalTo: valueLabel.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSnapshot(_ snapshot: CodexQuotaSnapshot?) {
        guard let snapshot = snapshot else {
            valueLabel.stringValue = "—"
            resetLabel.stringValue = "↻ —"
            fillWidthConstraint.constant = 0
            return
        }

        let clamped = min(100, max(0, snapshot.remainingPercent))
        valueLabel.stringValue = String(format: "%.0f%%", clamped)
        if let resetsAt = snapshot.resetsAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d HH:mm"
            resetLabel.stringValue = "↻ " + formatter.string(from: resetsAt)
        } else {
            resetLabel.stringValue = "↻ —"
        }
        let color = clamped <= 10 ? dangerColor : (clamped <= 30 ? warningColor : successColor)
        progressFill.layer?.backgroundColor = color.cgColor
        fillWidthConstraint.constant = maximumFillWidth * CGFloat(clamped / 100)
    }
}

private struct CodexQuotaSnapshot {
    let remainingPercent: Double
    let resetsAt: Date?
}

private enum CodexQuotaReader {
    private final class AppServerRequestState {
        var buffer = Data()
        var didSendRateLimitRequest = false
        var result: CodexQuotaSnapshot?
        var isFinished = false
        let lock = NSLock()
        let completion = DispatchSemaphore(value: 0)
    }

    private static let snapshotLock = NSLock()
    private static var lastSnapshot: CodexQuotaSnapshot?
    private static var lastFetchAt: Date?
    private static let cacheLifetime: TimeInterval = 8

    static func snapshot() -> CodexQuotaSnapshot? {
        // Both Codex widgets refresh on their own utility queues. Serialize
        // requests and reuse a result for a few seconds so one 10-second tick
        // produces only one app-server connection.
        snapshotLock.lock()
        defer { snapshotLock.unlock() }

        if let lastFetchAt = lastFetchAt,
           Date().timeIntervalSince(lastFetchAt) < cacheLifetime {
            return lastSnapshot
        }

        let freshSnapshot = liveSnapshot()
        lastSnapshot = freshSnapshot
        lastFetchAt = Date()
        return freshSnapshot
    }

    private static func liveSnapshot() -> CodexQuotaSnapshot? {
        guard let codexURL = codexExecutableURL() else { return nil }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()

        process.executableURL = codexURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput

        let state = AppServerRequestState()
        let inputHandle = input.fileHandleForWriting
        let outputHandle = output.fileHandleForReading

        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            var shouldSendRateLimitRequest = false
            var shouldSignal = false

            state.lock.lock()
            if data.isEmpty {
                if !state.isFinished {
                    state.isFinished = true
                    shouldSignal = true
                }
            } else {
                state.buffer.append(data)
                while let newlineIndex = state.buffer.firstIndex(of: 0x0A) {
                    let lineData = Data(state.buffer[..<newlineIndex])
                    state.buffer.removeSubrange(...newlineIndex)
                    guard !lineData.isEmpty,
                          let object = try? JSONSerialization.jsonObject(with: lineData),
                          let message = object as? [String: Any],
                          let messageID = (message["id"] as? NSNumber)?.intValue else { continue }

                    if messageID == 1 && !state.didSendRateLimitRequest {
                        state.didSendRateLimitRequest = true
                        shouldSendRateLimitRequest = true
                    } else if messageID == 2 {
                        if let result = message["result"] as? [String: Any],
                           let rateLimit = primaryRateLimit(from: result),
                           let used = rateLimit["usedPercent"] as? NSNumber {
                            let resetsAt = (rateLimit["resetsAt"] as? NSNumber).map {
                                Date(timeIntervalSince1970: $0.doubleValue)
                            }
                            state.result = CodexQuotaSnapshot(
                                remainingPercent: min(100, max(0, 100 - used.doubleValue)),
                                resetsAt: resetsAt
                            )
                        }
                        if !state.isFinished {
                            state.isFinished = true
                            shouldSignal = true
                        }
                    }
                }
            }
            state.lock.unlock()

            // The app-server protocol requires initialize to finish before
            // initialized and account/rateLimits/read are sent.
            if shouldSendRateLimitRequest {
                let requests = [
                    #"{"method":"initialized","params":{}}"#,
                    #"{"id":2,"method":"account/rateLimits/read"}"#
                ].joined(separator: "\n") + "\n"
                inputHandle.write(Data(requests.utf8))
            }
            if shouldSignal {
                state.completion.signal()
            }
        }

        do {
            try process.run()
            let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"mtmr-codex-quota","version":"1.0"}}}"# + "\n"
            inputHandle.write(Data(initialize.utf8))
            _ = state.completion.wait(timeout: .now() + 5)
        } catch {
            outputHandle.readabilityHandler = nil
            return nil
        }

        outputHandle.readabilityHandler = nil
        inputHandle.closeFile()
        if process.isRunning {
            process.terminate()
        }

        state.lock.lock()
        let result = state.result
        state.lock.unlock()
        return result
    }

    private static func codexExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            home + "/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private static func primaryRateLimit(from result: [String: Any]) -> [String: Any]? {
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = buckets["codex"] as? [String: Any],
           let primary = codex["primary"] as? [String: Any] {
            return primary
        }
        guard let rateLimits = result["rateLimits"] as? [String: Any] else { return nil }
        return rateLimits["primary"] as? [String: Any]
    }

}

/// TokenTracker-style daily activity, compressed into a native Touch Bar pill.
final class CodexTodayBarItem: NSCustomTouchBarItem {
    private let refreshInterval: TimeInterval
    private let refreshQueue = DispatchQueue(label: "mtmr.codex-today", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let todayView = CodexTodayView(frame: NSRect(x: 0, y: 0, width: 320, height: 30))

    init(identifier: NSTouchBarItem.Identifier, refreshInterval: TimeInterval) {
        self.refreshInterval = max(10, refreshInterval)
        super.init(identifier: identifier)
        view = todayView
        refreshAndSchedule()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refreshAndSchedule() {
        refreshQueue.async { [weak self] in self?.refresh() }

        let timer = DispatchSource.makeTimerSource(queue: refreshQueue)
        timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        timer.setEventHandler { [weak self] in self?.refresh() }
        self.timer = timer
        timer.resume()
    }

    private func refresh() {
        let todaySnapshot = CodexTodayReader.snapshot()
        let quotaSnapshot = CodexQuotaReader.snapshot()
        DispatchQueue.main.async { [weak self] in
            self?.todayView.setSnapshots(today: todaySnapshot, quota: quotaSnapshot)
        }
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

private final class CodexTodayView: NSView {
    private let petView = CodexPetView()
    private let messageLabel = NSTextField(labelWithString: "⏳ Crunching numbers…")
    private let pillView = NSView()
    private let tailView = CodexSpeechTailView()
    private let switchButton = NSButton()
    private var todaySnapshot: CodexTodaySnapshot?
    private var quotaSnapshot: CodexQuotaSnapshot?
    private var pageIndex = 0
    private var hasPresentedFirstSnapshot = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        pillView.translatesAutoresizingMaskIntoConstraints = false
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius = 13
        pillView.layer?.backgroundColor = NSColor(white: 1, alpha: 0.16).cgColor

        tailView.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.alignment = .left
        messageLabel.textColor = NSColor(white: 1, alpha: 0.92)
        messageLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        messageLabel.lineBreakMode = .byTruncatingMiddle
        messageLabel.maximumNumberOfLines = 1

        switchButton.translatesAutoresizingMaskIntoConstraints = false
        switchButton.title = ""
        switchButton.isBordered = false
        switchButton.setButtonType(.momentaryChange)
        switchButton.focusRingType = .none
        switchButton.target = self
        switchButton.action = #selector(cycleMessage(_:))

        petView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(petView)
        addSubview(tailView)
        addSubview(pillView)
        pillView.addSubview(messageLabel)
        pillView.addSubview(switchButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            petView.leadingAnchor.constraint(equalTo: leadingAnchor),
            petView.centerYAnchor.constraint(equalTo: centerYAnchor),
            petView.widthAnchor.constraint(equalToConstant: 34),
            petView.heightAnchor.constraint(equalToConstant: 30),
            tailView.widthAnchor.constraint(equalToConstant: 8),
            tailView.heightAnchor.constraint(equalToConstant: 12),
            tailView.leadingAnchor.constraint(equalTo: petView.trailingAnchor, constant: 6),
            tailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillView.leadingAnchor.constraint(equalTo: petView.trailingAnchor, constant: 11),
            pillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillView.heightAnchor.constraint(equalToConstant: 26),
            messageLabel.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -12),
            messageLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            switchButton.leadingAnchor.constraint(equalTo: pillView.leadingAnchor),
            switchButton.trailingAnchor.constraint(equalTo: pillView.trailingAnchor),
            switchButton.topAnchor.constraint(equalTo: pillView.topAnchor),
            switchButton.bottomAnchor.constraint(equalTo: pillView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSnapshots(today: CodexTodaySnapshot?, quota: CodexQuotaSnapshot?) {
        todaySnapshot = today
        quotaSnapshot = quota
        pageIndex = min(pageIndex, max(0, messagePool.count - 1))
        renderCurrentPage(animatePet: !hasPresentedFirstSnapshot)
        hasPresentedFirstSnapshot = true
    }

    @objc private func cycleMessage(_: NSButton) {
        let count = max(1, messagePool.count)
        pageIndex = (pageIndex + 1) % count
        renderCurrentPage(animatePet: true)
    }

    private func renderCurrentPage(animatePet: Bool) {
        let messages = messagePool
        guard !messages.isEmpty else { return }
        pageIndex %= messages.count
        messageLabel.stringValue = messages[pageIndex]
        if animatePet { petView.showCarouselAction(at: pageIndex) }
    }

    /// Mirrors TokenTracker's dashboard quip pool: live totals, rolling windows,
    /// conversation activity, quota state, usage-sensitive reactions, and a
    /// small set of personality lines. Tapping the bubble walks the whole pool.
    private var messagePool: [String] {
        guard let snapshot = todaySnapshot else {
            return ["⏳ Crunching numbers…", "📡 Fetching latest data!", "🧮 Counting your tokens~"]
        }

        let tokens = formatTokens(snapshot.totalTokens)
        let cost = "$" + String(format: "%.2f", snapshot.estimatedCost)
        var messages = [
            "👋 Hey there~",
            "📊 Today: \(tokens) tokens",
            "📈 \(tokens) tokens — \(cost) spent today",
            "🧾 Today's bill: \(cost) for \(tokens) tokens",
            "💳 AI tab today: \(cost)"
        ]

        if snapshot.totalTokens < 50_000 {
            messages += ["☕ Just warming up!", "🌱 A gentle start"]
        } else if snapshot.totalTokens < 200_000 {
            messages += ["🎯 Getting into the flow!", "💪 Solid progress today"]
        } else if snapshot.totalTokens < 500_000 {
            messages += ["🔥 Busy day!", "⚡ You're on a roll!"]
        } else if snapshot.totalTokens < 2_000_000 {
            messages += ["🚀 Heavy usage today!", "🖨 Token machine goes brrr"]
        } else {
            messages += ["🤯 MASSIVE day!", "🔥 Token counter on fire!"]
        }

        if let sevenDayTokens = snapshot.sevenDayTokens, sevenDayTokens > 0 {
            messages.append("📅 7-day total: \(formatTokens(sevenDayTokens)) tokens")
            if let activeDays = snapshot.sevenDayActiveDays, activeDays > 0 {
                messages.append("🗓 \(activeDays) active days this week")
                if activeDays >= 7 { messages.append("🏆 7/7 active days — perfect streak!") }
            }
        }
        if let thirtyDayTokens = snapshot.thirtyDayTokens, thirtyDayTokens > 0 {
            messages.append("📆 30-day total: \(formatTokens(thirtyDayTokens)) tokens")
        }
        if let average = snapshot.thirtyDayAverage, average > 0 {
            messages.append("📊 Averaging ~\(formatTokens(average))/day this month")
        }
        if snapshot.conversationCount > 0 {
            messages.append("💬 \(snapshot.conversationCount) conversations today")
            if snapshot.conversationCount >= 10 {
                messages.append("🗣 \(snapshot.conversationCount) chats! Busy talker today")
            }
        }

        messages.append(quotaMessage())
        messages += [
            "👆 Tap me for more!",
            "📋 I count so you don't have to",
            "✨ Every token tells a story",
            "🤝 Your AI spending buddy"
        ]
        return messages
    }

    private func quotaMessage() -> String {
        guard let snapshot = quotaSnapshot else { return "Codex 7d · quota unavailable" }
        let remaining = min(100, max(0, snapshot.remainingPercent))
        let status: String
        if remaining <= 10 {
            status = "near limit"
        } else if remaining <= 30 {
            status = "running low"
        } else {
            status = "available"
        }
        guard let reset = snapshot.resetsAt else { return "Codex 7d · \(status)" }
        return "Codex 7d · \(status) · \(relativeReset(reset))"
    }

    private func relativeReset(_ date: Date) -> String {
        let seconds = max(0, date.timeIntervalSinceNow)
        if seconds >= 86_400 { return "in \(max(1, Int(ceil(seconds / 86_400))))d" }
        if seconds >= 3_600 { return "in \(max(1, Int(ceil(seconds / 3_600))))h" }
        return "in \(max(1, Int(ceil(seconds / 60))))m"
    }

    private func formatTokens(_ tokens: Int64) -> String {
        if tokens >= 1_000_000_000 {
            return String(format: "%.1fB", Double(tokens) / 1_000_000_000)
        }
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.0fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }
}

private final class CodexSpeechTailView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(white: 1, alpha: 0.15).setFill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: bounds.midY))
        path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        path.line(to: NSPoint(x: bounds.maxX, y: bounds.minY))
        path.close()
        path.fill()
    }
}

private enum CodexPetMood {
    case usage
    case quotaComfortable
    case quotaLow
}

/// A native AppKit recreation of TokenTracker's official Clawd. It includes
/// every state in TokenTracker's ClawdState enum plus the five physical tap
/// reactions, rendered as crisp pixels so animation remains live in NSTouchBar.
private final class CodexPetView: NSView {
    private let clawdColor = NSColor(calibratedRed: 0xDE / 255, green: 0x88 / 255, blue: 0x6D / 255, alpha: 1)
    private let cyanColor = NSColor(calibratedRed: 0x40 / 255, green: 0xC4 / 255, blue: 1, alpha: 1)
    private let goldColor = NSColor(calibratedRed: 1, green: 0.82, blue: 0.40, alpha: 1)
    private let wizardColor = NSColor(calibratedRed: 0.25, green: 0.19, blue: 0.55, alpha: 1)
    private var automaticActionTimer: Timer?
    private var frameTimer: Timer?
    private let interactionView = NSView()
    private var pendingSingleTap: DispatchWorkItem?
    private var ignoreSingleTapUntil: CFTimeInterval = 0
    private var action: PetAction = .idleLiving
    private var physicalAction: PhysicalAction?
    private var physicalActionStarted: CFTimeInterval = 0
    private var displayMood: CodexPetMood = .quotaComfortable
    private var actionStarted: CFTimeInterval = 0
    private var actionDuration: TimeInterval = 0
    private var tapAnimationIndex = 0

    /// Matches TokenTracker's complete ClawdState enum, including mini states.
    private enum PetAction: CaseIterable {
        case idleLiving
        case idleLook
        case idleDoze
        case sleeping
        case workingTyping
        case workingThinking
        case workingUltrathink
        case workingJuggling
        case workingWizard
        case workingOverheated
        case happy
        case disconnected
        case error
        case yawning
        case waking
        case miniIdle
        case miniPeek
        case miniAlert
        case miniHappy
        case miniSleep
    }

    private enum PhysicalAction: CaseIterable {
        case jump
        case wiggle
        case flip
        case multiBlink
        case wave
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configurePet()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePet()
    }

    private func configurePet() {
        wantsLayer = true
        layer?.masksToBounds = false
        startFrameUpdates()
        configureInteraction()

        let timer = Timer(timeInterval: 6, repeats: true) { [weak self] _ in
            self?.performAutomaticAction()
        }
        RunLoop.main.add(timer, forMode: .common)
        automaticActionTimer = timer

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, self.actionDuration == 0 else { return }
            self.setAction(.happy, duration: 2.4, physical: .wave)
        }
    }

    private func startFrameUpdates() {
        let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
        needsDisplay = true
    }

    private func configureInteraction() {
        interactionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(interactionView)
        NSLayoutConstraint.activate([
            interactionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            interactionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            interactionView.topAnchor.constraint(equalTo: topAnchor),
            interactionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let singleTap = NSClickGestureRecognizer(target: self, action: #selector(singleTapped(_:)))
        singleTap.numberOfClicksRequired = 1
        let doubleTap = NSClickGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfClicksRequired = 2
        interactionView.addGestureRecognizer(singleTap)
        interactionView.addGestureRecognizer(doubleTap)
        let press = NSPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        press.minimumPressDuration = 0.55
        interactionView.addGestureRecognizer(press)
    }

    @objc private func singleTapped(_: NSClickGestureRecognizer) {
        guard CACurrentMediaTime() >= ignoreSingleTapUntil else { return }
        pendingSingleTap?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.showCarouselAction(at: self.tapAnimationIndex)
            self.tapAnimationIndex += 1
        }
        pendingSingleTap = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    @objc private func doubleTapped(_: NSClickGestureRecognizer) {
        ignoreSingleTapUntil = CACurrentMediaTime() + 0.4
        pendingSingleTap?.cancel()
        setAction(.workingUltrathink, duration: 3.5, physical: .flip)
    }

    @objc private func longPressed(_ sender: NSPressGestureRecognizer) {
        guard sender.state == .began else { return }
        ignoreSingleTapUntil = CACurrentMediaTime() + 0.8
        pendingSingleTap?.cancel()
        setAction(.workingWizard, duration: 3.2, physical: .wave)
    }

    private func performAutomaticAction() {
        guard actionDuration == 0 else { return }
        let ambient: [PetAction] = [
            .idleLook, .idleDoze, .workingThinking, .workingTyping,
            .workingJuggling, .workingWizard, .workingUltrathink,
            .yawning, .waking, .miniPeek, .miniHappy
        ]
        setAction(ambient.randomElement() ?? .idleLiving, duration: 3.2)
    }

    /// Cycle the complete official TokenTracker Clawd state set. Each scene is
    /// paired with one of the five physical reactions so no state or tap motion
    /// is omitted from the Touch Bar adaptation.
    func showCarouselAction(at index: Int) {
        let actions = PetAction.allCases
        let reactions = PhysicalAction.allCases
        setAction(
            actions[index % actions.count],
            duration: 3.0,
            physical: reactions[index % reactions.count]
        )
    }

    func showMood(_ mood: CodexPetMood) {
        displayMood = mood
        switch mood {
        case .usage:
            setAction(.happy, duration: 2.8, physical: .jump)
        case .quotaComfortable:
            setAction(.idleLook, duration: 2.6)
        case .quotaLow:
            setAction(.workingOverheated, duration: 3.4, physical: .wiggle)
        }
    }

    private func setAction(_ newAction: PetAction, duration: TimeInterval, physical: PhysicalAction? = nil) {
        action = newAction
        actionStarted = CACurrentMediaTime()
        actionDuration = duration
        physicalAction = physical
        physicalActionStarted = actionStarted
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let now = CACurrentMediaTime()
        var progress: CGFloat
        if actionDuration > 0 {
            progress = CGFloat((now - actionStarted) / actionDuration)
            if progress >= 1 {
                action = .idleLiving
                actionDuration = 0
                progress = 0
            }
        } else {
            progress = CGFloat(fmod(now, 3.2) / 3.2)
        }
        let phase = CGFloat(fmod(now, 1.0))
        let blinkPhase = fmod(now, 4.0)
        var dx: CGFloat = 0
        var dy: CGFloat = sin(CGFloat(now) * 2) * 0.18
        var flipped = false
        var forceBlink = blinkPhase > 1.82 && blinkPhase < 2.02
        var wave = false

        if let physicalAction, now - physicalActionStarted < 0.75 {
            let physicalProgress = CGFloat((now - physicalActionStarted) / 0.75)
            switch physicalAction {
            case .jump:
                dy -= abs(sin(physicalProgress * .pi)) * 2.1
            case .wiggle:
                dx += sin(physicalProgress * .pi * 8) * (1 - physicalProgress)
            case .flip:
                flipped = physicalProgress > 0.18 && physicalProgress < 0.82
            case .multiBlink:
                forceBlink = Int(physicalProgress * 8) % 2 == 0
            case .wave:
                wave = true
            }
        }

        switch action {
        case .idleLiving:
            switch displayMood {
            case .usage: wave = true
            case .quotaComfortable: dx -= 0.2
            case .quotaLow: wave = true
            }
            drawClawd(dx: dx, dy: dy, eyesClosed: forceBlink, wave: wave, flipped: flipped)
        case .idleLook:
            dx += sin(progress * .pi * 2) * 1.0
            drawClawd(dx: dx, dy: dy, eyeShift: progress < 0.5 ? -0.7 : 0.7, wave: wave, flipped: flipped)
            drawQuestion(dx: dx, dy: dy)
        case .idleDoze:
            drawClawd(dx: dx, dy: dy + 0.8, eyesClosed: true, mouth: .small, wave: wave, flipped: flipped)
            drawZ(dx: dx, dy: dy)
        case .sleeping:
            drawCollapsed(dx: dx, dy: dy + 2.1, eyes: .closed, flipped: flipped)
            drawZ(dx: dx, dy: dy)
        case .workingTyping:
            dx += sin(progress * .pi * 18) * 0.25
            drawClawd(dx: dx, dy: dy, eyesClosed: forceBlink, armsUp: true, wave: wave, flipped: flipped)
            drawTypingParticles(phase: phase, dx: dx, dy: dy)
        case .workingThinking:
            dx += sin(progress * .pi * 2) * 0.35
            drawClawd(dx: dx, dy: dy, eyeShift: -0.55, handToFace: true, wave: wave, flipped: flipped)
            drawThinkingDots(phase: phase, dx: dx, dy: dy)
        case .workingUltrathink:
            dx += sin(progress * .pi * 18) * 0.45
            drawClawd(dx: dx, dy: dy, eyesClosed: forceBlink, armsUp: true, wave: wave, flipped: flipped)
            drawRainbowCrown(phase: phase, dx: dx, dy: dy)
            drawSparks(phase: phase, dx: dx, dy: dy)
        case .workingJuggling:
            drawClawd(dx: dx, dy: dy, eyesClosed: forceBlink, armsUp: true, wave: wave, flipped: flipped)
            drawJugglingBalls(phase: phase, dx: dx, dy: dy)
        case .workingWizard:
            drawClawd(dx: dx, dy: dy + 0.5, eyesClosed: forceBlink, armSpread: true, wave: wave, flipped: flipped)
            drawWizardCostume(phase: phase, dx: dx, dy: dy)
        case .workingOverheated:
            drawCollapsed(dx: dx + sin(progress * .pi * 16) * 0.35, dy: dy + 1.8, eyes: .crossed, hot: true, flipped: flipped)
            drawSteam(phase: phase, dx: dx, dy: dy)
        case .happy:
            dy -= abs(sin(progress * .pi * 6)) * 1.3
            drawClawd(dx: dx, dy: dy, eyes: .happy, armSpread: true, wave: wave, flipped: flipped)
            drawSparkles(phase: phase, dx: dx, dy: dy)
        case .disconnected:
            dx += sin(progress * .pi * 5) * 0.65
            drawClawd(dx: dx, dy: dy, eyeShift: progress < 0.5 ? -0.6 : 0.6, wave: wave, flipped: flipped)
            progress < 0.58 ? drawQuestion(dx: dx, dy: dy) : drawExclamation(dx: dx, dy: dy, color: .white)
        case .error:
            drawCollapsed(dx: dx + sin(progress * .pi * 14) * 0.25, dy: dy + 2.0, eyes: .crossed, flipped: flipped)
            drawSmoke(phase: phase, dx: dx, dy: dy)
            drawExclamation(dx: dx, dy: dy, color: NSColor.systemRed)
        case .yawning:
            drawClawd(dx: dx, dy: dy + 0.5, eyesClosed: true, mouth: .wide, wave: wave, flipped: flipped)
            pixel(3, 11, color: cyanColor, dx: dx, dy: dy)
        case .waking:
            drawClawd(dx: dx, dy: dy, eyes: .wide, armSpread: true, wave: wave, flipped: flipped)
            drawSparkles(phase: phase, dx: dx, dy: dy)
        case .miniIdle:
            drawMini(dx: dx, dy: dy + 3.4, eyes: .normal, flipped: flipped)
        case .miniPeek:
            drawMini(dx: dx, dy: dy + 3.4, eyes: .wide, waving: true, flipped: flipped)
        case .miniAlert:
            drawMini(dx: dx, dy: dy + 3.4, eyes: .wide, flipped: flipped)
            drawExclamation(dx: dx, dy: dy + 1, color: NSColor.systemRed)
        case .miniHappy:
            drawMini(dx: dx, dy: dy + 3.4 - abs(sin(progress * .pi * 6)), eyes: .happy, waving: true, flipped: flipped)
            drawSparkles(phase: phase, dx: dx, dy: dy)
        case .miniSleep:
            drawMini(dx: dx, dy: dy + 4.0, eyes: .closed, flipped: flipped)
            drawZ(dx: dx, dy: dy + 1)
        }
    }

    private enum EyeStyle { case normal, closed, crossed, happy, wide }
    private enum MouthStyle { case none, small, wide }

    private func drawClawd(
        dx: CGFloat, dy: CGFloat, eyes: EyeStyle = .normal, eyeShift: CGFloat = 0,
        eyesClosed: Bool = false, mouth: MouthStyle = .none, armsUp: Bool = false,
        armSpread: Bool = false, handToFace: Bool = false, wave: Bool = false,
        flipped: Bool = false
    ) {
        pixel(3, 14, width: 9, color: NSColor.black.withAlphaComponent(0.45), dx: dx, dy: dy, flipped: flipped)
        pixel(2, 6, width: 11, height: 7, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        let armY: CGFloat = armsUp ? 6 : 9
        pixel(0, armY, width: 2, height: 2, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        pixel(13, wave ? 6 + sin(CGFloat(CACurrentMediaTime()) * 12) : armY, width: 2, height: 2, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        if armSpread {
            pixel(0, 8, width: 3, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
            pixel(12, 8, width: 3, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        }
        if handToFace { pixel(2, 7, width: 3, color: clawdColor, dx: dx, dy: dy, flipped: flipped) }
        for x in [3, 5, 9, 11] { pixel(CGFloat(x), 13, height: 2, color: clawdColor, dx: dx, dy: dy, flipped: flipped) }
        drawEyes(eyesClosed ? .closed : eyes, shift: eyeShift, dx: dx, dy: dy, flipped: flipped)
        if mouth == .small { pixel(7, 10, color: .black, dx: dx, dy: dy, flipped: flipped) }
        if mouth == .wide { pixel(6, 10, width: 3, height: 2, color: .black, dx: dx, dy: dy, flipped: flipped) }
    }

    private func drawEyes(_ style: EyeStyle, shift: CGFloat = 0, dx: CGFloat, dy: CGFloat, flipped: Bool) {
        switch style {
        case .normal:
            pixel(4 + shift, 8, width: 2, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(9 + shift, 8, width: 2, color: .black, dx: dx, dy: dy, flipped: flipped)
        case .closed:
            pixel(4, 9, width: 2, height: 0.6, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(9, 9, width: 2, height: 0.6, color: .black, dx: dx, dy: dy, flipped: flipped)
        case .crossed:
            for x in [4, 9] {
                pixel(CGFloat(x), 8, color: .black, dx: dx, dy: dy, flipped: flipped)
                pixel(CGFloat(x + 1), 9, color: .black, dx: dx, dy: dy, flipped: flipped)
                pixel(CGFloat(x + 1), 8, color: .black, dx: dx, dy: dy, flipped: flipped)
                pixel(CGFloat(x), 9, color: .black, dx: dx, dy: dy, flipped: flipped)
            }
        case .happy:
            pixel(4, 9, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(5, 8, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(9, 8, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(10, 9, color: .black, dx: dx, dy: dy, flipped: flipped)
        case .wide:
            pixel(4, 7.5, width: 2, height: 2, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(9, 7.5, width: 2, height: 2, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(4.5, 7.7, width: 0.55, height: 0.55, color: .white, dx: dx, dy: dy, flipped: flipped)
            pixel(9.5, 7.7, width: 0.55, height: 0.55, color: .white, dx: dx, dy: dy, flipped: flipped)
        }
    }

    private func drawCollapsed(dx: CGFloat, dy: CGFloat, eyes: EyeStyle, hot: Bool = false, flipped: Bool) {
        pixel(2, 9, width: 11, height: 4, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        pixel(0, 11, width: 2, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        pixel(13, 11, width: 2, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        pixel(3, 13, width: 9, color: NSColor.black.withAlphaComponent(0.45), dx: dx, dy: dy, flipped: flipped)
        drawEyes(eyes, dx: dx, dy: dy + 2, flipped: flipped)
        if hot { pixel(2, 9, width: 11, height: 4, color: NSColor.systemRed.withAlphaComponent(0.32), dx: dx, dy: dy, flipped: flipped) }
    }

    private func drawMini(dx: CGFloat, dy: CGFloat, eyes: EyeStyle, waving: Bool = false, flipped: Bool) {
        pixel(4, 7, width: 7, height: 5, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        pixel(2, waving ? 6.3 : 9, width: 2, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        pixel(11, 9, width: 2, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        pixel(5, 12, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        pixel(9, 12, color: clawdColor, dx: dx, dy: dy, flipped: flipped)
        switch eyes {
        case .closed:
            pixel(5, 9, width: 1.5, height: 0.5, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(8.5, 9, width: 1.5, height: 0.5, color: .black, dx: dx, dy: dy, flipped: flipped)
        case .happy:
            pixel(5, 9, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(9, 9, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(7, 10, color: .black, dx: dx, dy: dy, flipped: flipped)
        case .wide:
            pixel(5, 8, height: 2, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(9, 8, height: 2, color: .black, dx: dx, dy: dy, flipped: flipped)
        default:
            pixel(5, 9, color: .black, dx: dx, dy: dy, flipped: flipped)
            pixel(9, 9, color: .black, dx: dx, dy: dy, flipped: flipped)
        }
    }

    private func drawWizardCostume(phase: CGFloat, dx: CGFloat, dy: CGFloat) {
        pixel(4, 5, width: 7, color: wizardColor, dx: dx, dy: dy)
        pixel(5, 3, width: 5, height: 2, color: wizardColor, dx: dx, dy: dy)
        pixel(6, 1, width: 3, height: 2, color: wizardColor, dx: dx, dy: dy)
        pixel(8, 0, width: 2, color: wizardColor, dx: dx, dy: dy)
        pixel(13, 5, width: 0.8, height: 9, color: NSColor(calibratedRed: 0.46, green: 0.28, blue: 0.12, alpha: 1), dx: dx, dy: dy)
        pixel(12.4, 4.2, width: 2, height: 2, color: goldColor, dx: dx, dy: dy - abs(sin(phase * .pi * 2)))
    }

    private func drawJugglingBalls(phase: CGFloat, dx: CGFloat, dy: CGFloat) {
        let colors: [NSColor] = [.systemRed, goldColor, cyanColor]
        for index in 0 ..< 3 {
            let p = phase + CGFloat(index) / 3
            let x = 3 + CGFloat(index) * 4 + sin(p * .pi * 2) * 1.2
            let y = 3.8 - abs(sin(p * .pi * 2)) * 2.8
            pixel(x, y, width: 1.5, height: 1.5, color: colors[index], dx: dx, dy: dy)
        }
    }

    private func drawTypingParticles(phase: CGFloat, dx: CGFloat, dy: CGFloat) {
        for index in 0 ..< 4 {
            let p = CGFloat(index) / 4
            let y = 13 - fmod(phase + p, 1) * 7
            pixel(2 + CGFloat(index) * 3.3, y, width: 0.7, height: 0.7, color: cyanColor.withAlphaComponent(0.8), dx: dx, dy: dy)
        }
    }

    private func drawThinkingDots(phase: CGFloat, dx: CGFloat, dy: CGFloat) {
        for index in 0 ..< 3 {
            let alpha = 0.3 + 0.7 * max(0, sin((phase + CGFloat(index) * 0.2) * .pi * 2))
            pixel(10 + CGFloat(index) * 1.5, 3.5 - CGFloat(index) * 0.7, width: 0.9, height: 0.9, color: cyanColor.withAlphaComponent(alpha), dx: dx, dy: dy)
        }
    }

    private func drawRainbowCrown(phase: CGFloat, dx: CGFloat, dy: CGFloat) {
        let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
        for (index, color) in colors.enumerated() {
            let y = 4 - abs(CGFloat(index) - 2.5) * 0.45
            pixel(4 + CGFloat(index) * 1.2, y, width: 1.2, height: 0.8, color: color, dx: dx, dy: dy - abs(sin(phase * .pi * 2)) * 0.5)
        }
    }

    private func drawSparks(phase: CGFloat, dx: CGFloat, dy: CGFloat) {
        let offset = abs(sin(phase * .pi * 2))
        pixel(1, 4 - offset, color: goldColor, dx: dx, dy: dy)
        pixel(13, 3 + offset, color: cyanColor, dx: dx, dy: dy)
        pixel(2, 2 + offset, width: 0.7, height: 0.7, color: .white, dx: dx, dy: dy)
    }

    private func drawSparkles(phase: CGFloat, dx: CGFloat, dy: CGFloat) {
        let blink = phase < 0.5 ? goldColor : NSColor.white
        pixel(1, 5, color: blink, dx: dx, dy: dy)
        pixel(13, 4, color: blink, dx: dx, dy: dy)
        pixel(12, 11, width: 0.7, height: 0.7, color: goldColor, dx: dx, dy: dy)
    }

    private func drawSteam(phase: CGFloat, dx: CGFloat, dy: CGFloat) {
        let rise = fmod(phase * 2, 1) * 3
        pixel(4, 7 - rise, width: 0.8, height: 2, color: NSColor.white.withAlphaComponent(0.7), dx: dx, dy: dy)
        pixel(9, 6 - fmod(phase + 0.5, 1) * 3, width: 0.8, height: 2, color: NSColor.white.withAlphaComponent(0.7), dx: dx, dy: dy)
    }

    private func drawSmoke(phase: CGFloat, dx: CGFloat, dy: CGFloat) {
        let rise = fmod(phase * 1.5, 1) * 3
        pixel(5, 8 - rise, width: 1.2, height: 1.2, color: NSColor.gray.withAlphaComponent(0.7), dx: dx, dy: dy)
        pixel(9, 7 - fmod(phase + 0.4, 1) * 3, width: 1.1, height: 1.1, color: NSColor.gray.withAlphaComponent(0.55), dx: dx, dy: dy)
    }

    private func drawQuestion(dx: CGFloat, dy: CGFloat) {
        pixel(1, 3, width: 2, color: cyanColor, dx: dx, dy: dy)
        pixel(0, 4, color: cyanColor, dx: dx, dy: dy)
        pixel(3, 4, height: 2, color: cyanColor, dx: dx, dy: dy)
        pixel(2, 6, color: cyanColor, dx: dx, dy: dy)
        pixel(1, 8, color: cyanColor, dx: dx, dy: dy)
    }

    private func drawExclamation(dx: CGFloat, dy: CGFloat, color: NSColor) {
        pixel(13, 3, height: 4, color: color, dx: dx, dy: dy)
        pixel(13, 8, color: color, dx: dx, dy: dy)
    }

    private func drawZ(dx: CGFloat, dy: CGFloat) {
        pixel(11, 3, width: 3, height: 0.7, color: NSColor.white.withAlphaComponent(0.85), dx: dx, dy: dy)
        pixel(13, 3.7, width: 0.7, height: 0.7, color: NSColor.white.withAlphaComponent(0.85), dx: dx, dy: dy)
        pixel(12, 4.4, width: 0.7, height: 0.7, color: NSColor.white.withAlphaComponent(0.85), dx: dx, dy: dy)
        pixel(11, 5.1, width: 3, height: 0.7, color: NSColor.white.withAlphaComponent(0.85), dx: dx, dy: dy)
    }

    private func pixel(
        _ x: CGFloat, _ y: CGFloat, width: CGFloat = 1, height: CGFloat = 1,
        color: NSColor, dx: CGFloat = 0, dy: CGFloat = 0, flipped: Bool = false
    ) {
        let scale = min(bounds.width / 15, bounds.height / 16)
        let originX = (bounds.width - 15 * scale) / 2
        let originY = (bounds.height - 16 * scale) / 2
        let pixelX = flipped ? 15 - x - width : x
        color.setFill()
        NSRect(
            x: originX + (pixelX + dx) * scale,
            y: originY + (y + dy) * scale,
            width: max(0.5, width * scale),
            height: max(0.5, height * scale)
        ).fill()
    }

    deinit {
        automaticActionTimer?.invalidate()
        frameTimer?.invalidate()
        pendingSingleTap?.cancel()
    }
}

private struct CodexTodaySnapshot {
    let totalTokens: Int64
    let estimatedCost: Double
    let conversationCount: Int
    let sevenDayTokens: Int64?
    let sevenDayActiveDays: Int?
    let thirtyDayTokens: Int64?
    let thirtyDayAverage: Int64?

    init(
        totalTokens: Int64,
        estimatedCost: Double,
        conversationCount: Int = 0,
        sevenDayTokens: Int64? = nil,
        sevenDayActiveDays: Int? = nil,
        thirtyDayTokens: Int64? = nil,
        thirtyDayAverage: Int64? = nil
    ) {
        self.totalTokens = totalTokens
        self.estimatedCost = estimatedCost
        self.conversationCount = conversationCount
        self.sevenDayTokens = sevenDayTokens
        self.sevenDayActiveDays = sevenDayActiveDays
        self.thirtyDayTokens = thirtyDayTokens
        self.thirtyDayAverage = thirtyDayAverage
    }
}

private enum CodexTodayReader {
    private struct Price {
        let input: Double
        let cachedInput: Double
        let output: Double
    }

    private static var cachedSignature = ""
    private static var cachedSnapshot: CodexTodaySnapshot?

    static func snapshot() -> CodexTodaySnapshot? {
        if let tokenTrackerSnapshot = tokenTrackerSnapshot() {
            return tokenTrackerSnapshot
        }
        return localLogSnapshot()
    }

    /// TokenTracker's running macOS app exposes this read-only localhost API.
    /// Reading it keeps the Touch Bar total, deduplication, and pricing exactly
    /// aligned with the TokenTracker dashboard.
    private static func tokenTrackerSnapshot() -> CodexTodaySnapshot? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        let today = String(format: "%04d-%02d-%02d", year, month, day)

        var componentsURL = URLComponents(string: "http://127.0.0.1:7680/functions/tokentracker-usage-summary")
        componentsURL?.queryItems = [
            URLQueryItem(name: "from", value: today),
            URLQueryItem(name: "to", value: today),
            URLQueryItem(name: "tz", value: TimeZone.current.identifier)
        ]
        guard let url = componentsURL?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                responseData = data
            }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 2.5) == .success,
              let data = responseData,
              let object = try? JSONSerialization.jsonObject(with: data),
              let response = object as? [String: Any],
              let totals = response["totals"] as? [String: Any] else {
            task.cancel()
            return nil
        }

        let totalTokens = int64(totals["total_tokens"])
        let estimatedCost: Double
        if let cost = totals["total_cost_usd"] as? NSNumber {
            estimatedCost = cost.doubleValue
        } else if let cost = totals["total_cost_usd"] as? String, let parsed = Double(cost) {
            estimatedCost = parsed
        } else {
            return nil
        }
        let rolling = response["rolling"] as? [String: Any]
        let last7 = rolling?["last_7d"] as? [String: Any]
        let last7Totals = last7?["totals"] as? [String: Any]
        let last30 = rolling?["last_30d"] as? [String: Any]
        let last30Totals = last30?["totals"] as? [String: Any]

        return CodexTodaySnapshot(
            totalTokens: totalTokens,
            estimatedCost: estimatedCost,
            conversationCount: Int(int64(totals["conversation_count"])),
            sevenDayTokens: last7Totals.map { int64($0["billable_total_tokens"]) },
            sevenDayActiveDays: last7.map { Int(int64($0["active_days"])) },
            thirtyDayTokens: last30Totals.map { int64($0["billable_total_tokens"]) },
            thirtyDayAverage: last30.map { int64($0["avg_per_active_day"]) }
        )
    }

    private static func localLogSnapshot() -> CodexTodaySnapshot? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }

        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", year, month, day), isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var files: [(url: URL, size: Int, modified: TimeInterval)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            files.append((url, values.fileSize ?? 0, values.contentModificationDate?.timeIntervalSince1970 ?? 0))
        }
        files.sort { $0.url.path < $1.url.path }

        let signature = files.map { "\($0.url.path):\($0.size):\($0.modified)" }.joined(separator: "|")
        if signature == cachedSignature, let cachedSnapshot = cachedSnapshot {
            return cachedSnapshot
        }

        var totalTokens: Int64 = 0
        var estimatedCost = 0.0

        for file in files {
            guard let text = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            var currentModel = "gpt-5.6-sol"
            var modelByTurn: [String: String] = [:]

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.contains("\"type\":\"turn_context\"") || line.contains("\"type\":\"token_usage_record\"") else { continue }
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let record = object as? [String: Any],
                      let type = record["type"] as? String,
                      let payload = record["payload"] as? [String: Any] else { continue }

                if type == "turn_context" {
                    guard let model = payload["model"] as? String else { continue }
                    currentModel = model
                    if let turnID = payload["turn_id"] as? String {
                        modelByTurn[turnID] = model
                    }
                    continue
                }

                guard type == "token_usage_record",
                      let usage = payload["usage"] as? [String: Any] else { continue }
                let model = (payload["turn_id"] as? String).flatMap { modelByTurn[$0] } ?? currentModel
                let input = int64(usage["input_tokens"])
                let cached = int64(usage["cached_input_tokens"])
                let output = int64(usage["output_tokens"])
                let total = int64(usage["total_tokens"])
                let price = priceForModel(model)
                let uncached = max(0, input - cached)

                totalTokens += total
                estimatedCost += (
                    Double(uncached) * price.input
                    + Double(cached) * price.cachedInput
                    + Double(output) * price.output
                ) / 1_000_000
            }
        }

        let snapshot = CodexTodaySnapshot(totalTokens: totalTokens, estimatedCost: estimatedCost)
        cachedSignature = signature
        cachedSnapshot = snapshot
        return snapshot
    }

    private static func int64(_ value: Any?) -> Int64 {
        return (value as? NSNumber)?.int64Value ?? 0
    }

    /// USD per one million tokens. The cached-input rate is separate because
    /// Codex logs include cached tokens inside the input total.
    private static func priceForModel(_ model: String) -> Price {
        if model.contains("gpt-6") {
            return Price(input: 10.00, cachedInput: 1.00, output: 50.00)
        }
        if model.contains("gpt-5.6-luna") {
            return Price(input: 0.20, cachedInput: 0.02, output: 1.20)
        }
        if model.contains("gpt-5.6-terra") {
            return Price(input: 2.00, cachedInput: 0.20, output: 12.00)
        }
        if model.contains("gpt-5.5") {
            return Price(input: 5.00, cachedInput: 0.50, output: 30.00)
        }
        if model.contains("gpt-5.4") {
            return Price(input: 2.50, cachedInput: 0.25, output: 15.00)
        }
        if model.contains("gpt-5.3-codex") || model.contains("gpt-5.2") {
            return Price(input: 1.75, cachedInput: 0.175, output: 14.00)
        }
        return Price(input: 4.00, cachedInput: 0.40, output: 20.00)
    }
}
