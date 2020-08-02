//
//  UpNextScrubberTouchBarItems.swift
//  MTMR
//
//  Created by Connor Meehan on 13/7/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
// 
//

import Foundation
import EventKit

class UpNextScrubberTouchBarItem: NSCustomTouchBarItem {
    // Dependencies
    private let scrollView = NSScrollView()
    private let activity: NSBackgroundActivityScheduler // Update scheduler
    private var eventSources : [IUpNextSource] = []
    private var items: [UpNextItem] = []

    // Settings
    private var futureSearchCutoff: Double
    private var pastSearchCutoff: Double
    private var maxToShow: Int
    private var widthConstraint: NSLayoutConstraint?
    private var autoResize: Bool = false
    
    /// <#Description#>
    /// - Parameters:
    ///   - identifier: Unique identifier of widget
    ///   - interval: Update view interval in seconds
    ///   - from: Relative to current time, how far back we search for events in hours
    ///   - to: Relative to current time, how far forward we search for events in hours
    ///   - maxToShow:  Which event to show (1 is first, 2 is second, and so on)
    init(identifier: NSTouchBarItem.Identifier, interval: TimeInterval, from: Double, to: Double, maxToShow: Int, autoResize: Bool) {
        // Initialise member properties
        activity = NSBackgroundActivityScheduler(identifier: "\(identifier.rawValue).updateCheck")
        pastSearchCutoff = from * 3600
        futureSearchCutoff = to * 3600
        self.maxToShow = maxToShow
        self.autoResize = autoResize
        UpNextItem.df.dateFormat = "HH:mm"
        // Error handling
        if (maxToShow <= 0) {
            fatalError("Error on UpNext bar item.  maxToShow property must be greater than 0.")
        }
        // Init super
        super.init(identifier: identifier)
        view = scrollView
        // Add event sources
        // Can optionally pass an update view callback to an event source to redraw element
        self.eventSources.append(UpNextCalenderSource(updateCallback: self.updateView))
        // Fallback interactivity via interval
        activity.interval = interval
        activity.repeats = true
        activity.qualityOfService = .utility
        activity.schedule { (completion: NSBackgroundActivityScheduler.CompletionHandler) in
            self.updateView()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
        updateView()
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateView() -> Void {
        items = []
        var upcomingEvents = self.getUpcomingEvents()
        upcomingEvents.sort(by: {$0.startDate.compare($1.startDate) == .orderedAscending})
        var index = 1
        DispatchQueue.main.async {
            for event in upcomingEvents {
                // Create UpNextItem
                let item = UpNextItem(event: event)
                item.backgroundColor = self.getBackgroundColor(startDate: event.startDate)
                // Bind tap event
                item.actions.append(ItemAction(trigger: .singleTap) { [weak self] in
                    self?.switchToApp(event: event)
                })
                // Add to view
                self.items.append(item)
                // Check if should display any more
                if (index == self.maxToShow) {
                    break;
                }
                index += 1
            }
            self.reloadData()
            self.updateSize()
        }
    }
    
    private func reloadData() {
        let stackView = NSStackView(views: items.compactMap { $0.view })
        stackView.spacing = 5
        stackView.orientation = .horizontal
        let visibleRect = self.scrollView.documentVisibleRect
        self.scrollView.documentView = stackView
        stackView.scroll(visibleRect.origin)
    }
    
    func updateSize() {
        if self.autoResize {
            self.widthConstraint?.isActive = false
            
            let width = self.scrollView.documentView?.fittingSize.width ?? 0
            self.widthConstraint = self.scrollView.widthAnchor.constraint(equalToConstant: width)
            self.widthConstraint!.isActive = true
        }
    }

    
    private func getUpcomingEvents() -> [UpNextEventModel] {
        var upcomingEvents: [UpNextEventModel] = []

        // Calculate the range we're going to search for events in
        let dateLowerBounds = Date(timeIntervalSinceNow: self.pastSearchCutoff)
        let dateUpperBounds = Date(timeIntervalSinceNow: self.futureSearchCutoff)
        
        // Get all events from all sources
        for eventSource in self.eventSources {
            if (eventSource.hasPermission) {
                let events = eventSource.getUpcomingEvents(dateLowerBounds: dateLowerBounds, dateUpperBounds: dateUpperBounds)
                upcomingEvents.append(contentsOf: events)
            }
        }
        
        return upcomingEvents
    }
    
    public func switchToApp(event: UpNextEventModel) {
        var bundleIdentifier: String
        switch(event.sourceType) {
        case .iCalendar:
            bundleIdentifier = UpNextCalenderSource.bundleIdentifier
        }
        
        NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleIdentifier, options: [.default], additionalEventParamDescriptor: nil, launchIdentifier: nil)

        // NB: if you can't open app which on another space, try to check mark
        // "When switching to an application, switch to a Space with open windows for the application"
        // in Mission control settings
    }

    
    func getBackgroundColor(startDate: Date) -> NSColor {
        let distance = startDate.timeIntervalSinceReferenceDate/60 - Date().timeIntervalSinceReferenceDate/60 // Get time difference in minutes
        if (distance < 0 as TimeInterval) { // If it's in the past, draw as blue
            return NSColor.systemBlue
        } else if (distance < 30 as TimeInterval) { // Less than 30 minutes, backround is red
            return NSColor.systemRed
        }
        return NSColor.clear
    }
}

private class UpNextItem : CustomButtonTouchBarItem {
    static public let df = DateFormatter()

    init(event: UpNextEventModel) {
        let identifier = UpNextItem.getIdentifier(event: event)
        let title = UpNextItem.getTitle(event: event)
        super.init(identifier: NSTouchBarItem.Identifier(rawValue: identifier), title: title)
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private static func getTitle(event: UpNextEventModel) -> String {
        var title = ""
        let startDateString = UpNextItem.df.string(for: event.startDate)
        switch event.sourceType {
        case .iCalendar:
            title = String.init(format: "🗓 %@ - %@ ", event.title, startDateString!)
        }
        return title
    }
    
    private static func getIdentifier(event: UpNextEventModel) -> String {
        var identifier : String
        switch event.sourceType {
        case .iCalendar:
            identifier = "com.mtmr.iCalendarEvent"
        }
        return identifier + "." + event.title
    }
}

enum UpNextSourceType {
    case iCalendar
}
    
// Model for events to be displayed in dock
struct UpNextEventModel {
    let title: String
    let startDate: Date
    let sourceType: UpNextSourceType
}


// Interface for any event source
protocol IUpNextSource {
    static var bundleIdentifier: String { get }
    var hasPermission : Bool { get }
    var updateCallback : () -> Void { get set }
    
    init(updateCallback: @escaping () -> Void)
    func getUpcomingEvents(dateLowerBounds: Date, dateUpperBounds: Date) -> [UpNextEventModel]
}

class UpNextCalenderSource : IUpNextSource {
    static public let bundleIdentifier: String = "com.apple.iCal"

    public var hasPermission: Bool = false
    private var eventStore : EKEventStore
    internal var updateCallback: () -> Void
    
    required init(updateCallback: @escaping () -> Void = {}) {
        self.updateCallback = updateCallback
        eventStore = EKEventStore()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: nil, using: handleUpdate)
        let authStatus = EKEventStore.authorizationStatus(for: .event)
        if (authStatus != .authorized) {
            eventStore.requestAccess(to: .event){ granted, error in
                self.hasPermission = granted;
                self.handleUpdate()
                if(!granted) {
                     NSLog("Error: MTMR UpNextBarWidget not given calendar access.")
                     return
                 }
            }
        } else {
            self.handleUpdate()
        }

    }
    public func handleUpdate() {
        self.handleUpdate(note: Notification(name: Notification.Name("refresh view")))
    }
    public func handleUpdate(note: Notification) {
        self.updateCallback()
    }
    
    public func getUpcomingEvents(dateLowerBounds: Date, dateUpperBounds: Date) -> [UpNextEventModel] {
        var upcomingEvents: [UpNextEventModel] = []
        let calendars = self.eventStore.calendars(for: .event)
        let predicate = self.eventStore.predicateForEvents(withStart: dateLowerBounds, end: dateUpperBounds, calendars: calendars)
        let events = self.eventStore.events(matching: predicate)
        for event in events {
            upcomingEvents.append(UpNextEventModel(title: event.title, startDate: event.startDate, sourceType: UpNextSourceType.iCalendar))
        }
        return upcomingEvents
    }
}
