//
//  UpNextBarItems.swift
//  MTMR
//
//  Created by Connor Meehan on 13/7/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
// 
//

import Foundation
import EventKit

class UpNextBarItem: NSCustomTouchBarItem {
    // Dependencies
    private let scrollView = NSScrollView()
    private let activity: NSBackgroundActivityScheduler // Update scheduler
    private var eventSources : [IUpNextSource] = []
    private var items: [UpNextItem] = []

    // Settings
    private var futureSearchCutoff: Double
    private var pastSearchCutoff: Double
    private var nthEvent: Int
    private var widthConstraint: NSLayoutConstraint?
    
    /// <#Description#>
    /// - Parameters:
    ///   - identifier: Unique identifier of widget
    ///   - interval: Update view interval in seconds
    ///   - from: Relative to current time, how far back we search for events in hours
    ///   - to: Relative to current time, how far forward we search for events in hours
    ///   - nthEvent:  Which event to show (1 is first, 2 is second, and so on)
    init(identifier: NSTouchBarItem.Identifier, interval: TimeInterval, from: Double, to: Double, nthEvent: Int) {
        // Initialise member properties
        activity = NSBackgroundActivityScheduler(identifier: "\(identifier.rawValue).updateCheck")
        pastSearchCutoff = from * 3600
        futureSearchCutoff = to * 3600
        self.nthEvent = nthEvent
        UpNextItem.df.dateFormat = "HH:mm"
        // Error handling
        if (nthEvent <= 0) {
            fatalError("Error on UpNext bar item.  nthEvent property must be greater than 0.")
        }
        // Init super
        super.init(identifier: identifier)
        view = scrollView
        // Add event sources
        self.eventSources.append(UpNextCalenderSource())
        // Start activity to update view
        activity.interval = interval
        activity.repeats = true
        activity.qualityOfService = .utility
        activity.schedule { (completion: NSBackgroundActivityScheduler.CompletionHandler) in
            self.updateView()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
        updateView()
        
        let upperBoundsDate = Date(timeIntervalSinceNow: futureSearchCutoff)
        NSLog("Searching up to \(upperBoundsDate)")
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateView() {
        items = []
        var upcomingEvents = self.getUpcomingEvents()
        NSLog("Found \(upcomingEvents.count) events")
        upcomingEvents.sort(by: {$0.startDate.compare($1.startDate) == .orderedAscending})
        var index = 1
        DispatchQueue.main.async {
            for event in upcomingEvents {
                // Create UpNextItem
                let item = UpNextItem(event: event)
                item.backgroundColor = self.getBackgroundColor(startDate: event.startDate)
                // Bind tap event
                item.tapClosure = { [weak self] in
                    self?.switchToApp(event: event)
                }
                // Add to view
                self.items.append(item)
                // Check if should display any more
                if (index == self.nthEvent) {
                    break;
                }
                index += 1
            }
            self.reloadData()
        }
    }
    
    private func reloadData() {
        NSLog("Displaying \(items.count) items...")
        let stackView = NSStackView(views: items.compactMap { $0.view })
        stackView.spacing = 5
        stackView.orientation = .horizontal
        let visibleRect = self.scrollView.documentVisibleRect
        self.scrollView.documentView = stackView
        stackView.scroll(visibleRect.origin)
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
        let distance = abs(Date().timeIntervalSinceReferenceDate/60 - startDate.timeIntervalSinceReferenceDate/60) // Get time difference in minutes
        if(distance < 30 as TimeInterval) { // Less than 30 minutes, backround is red
            return NSColor.systemRed
        } else if (distance < 120 as TimeInterval) { // Less than 2 hours, background is yellow
            return NSColor.systemOrange
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
    init()
    func getUpcomingEvents(dateLowerBounds: Date, dateUpperBounds: Date) -> [UpNextEventModel]
}

class UpNextCalenderSource : IUpNextSource {
    static public let bundleIdentifier: String = "com.apple.iCal"

    public var hasPermission: Bool = false
    private var eventStore = EKEventStore()
    
    required init() {
        eventStore.requestAccess(to: .event){ granted, error in
            self.hasPermission = granted;
            if(!granted) {
                 NSLog("Error: MTMR UpNextBarWidget not given calendar access.")
                 return
             }
        }
    }
    public func getUpcomingEvents(dateLowerBounds: Date, dateUpperBounds: Date) -> [UpNextEventModel] {
        NSLog("Getting calendar events...")
        eventStore = EKEventStore()
        var upcomingEvents: [UpNextEventModel] = []
        let calendars = self.eventStore.calendars(for: .event)
        
        for calendar in calendars {
            let predicate = self.eventStore.predicateForEvents(withStart: dateLowerBounds, end: dateUpperBounds, calendars: [calendar])

            let events = self.eventStore.events(matching: predicate)
            for event in events {
                upcomingEvents.append(UpNextEventModel(title: event.title, startDate: event.startDate, sourceType: UpNextSourceType.iCalendar))
            }
        }
        
        print("Found " + String(upcomingEvents.count) + " events.")
        return upcomingEvents
    }
}
