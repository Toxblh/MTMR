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

class UpNextBarItem: CustomButtonTouchBarItem {
    private let activity: NSBackgroundActivityScheduler // Update scheduler
    private let df = DateFormatter()
    private let buttonTemplate = "🗓 %@ - %@ "
    
    // Settings
    private var futureSearchCutoff: Double
    private var pastSearchCutoff: Double
    private var nthEvent: Int
    
    // State
    private var eventSources : [IUpNextSource] = []
    
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
        pastSearchCutoff = from * 360
        futureSearchCutoff = to * 360
        self.nthEvent = nthEvent
        df.dateFormat = "HH:mm"
        // Error handling
        if (nthEvent <= 0) {
            fatalError("Error on UpNext bar item.  nthEvent property must be greater than 0.")
        }
        // Init super
        super.init(identifier: identifier, title: " ")
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
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateView() {
        var upcomingEvents = self.getUpcomingEvents()
        upcomingEvents.sort(by: {$0.startDate.compare($1.startDate) == .orderedAscending})
        for event in upcomingEvents {
            print("\(event.title) - \(event.startDate)")
        }
        if (upcomingEvents.count >= self.nthEvent) {
            let event = upcomingEvents[self.nthEvent-1]
            let title = event.title
            let startDateString = self.df.string(for: event.startDate)
            print("TITLE: " + title + " STARTDATE: " + (startDateString ?? "nil"))
                        
            print("SHOW")
            self.image = nil
            self.title = String(format: self.buttonTemplate, title, startDateString ?? "No time")
//            self.view.widthAnchor.constraint(lessThanOrEqualToConstant: 1000 as CGFloat).isActive = true
        } else {
           // Do not display any event
            print("HIDE " + String(upcomingEvents.count) + " " + String(self.nthEvent) + " " + String(upcomingEvents.count > self.nthEvent))
            self.image = nil
            self.title = ""
//            self.setWidth(value: 0)
        }
    }
    
    func getUpcomingEvents() -> [UpNextEventModel] {
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
    
    func gotoAppleCalendar() {
        print("CLICK")
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Calendar.app"))
    }
}
// Model for events to be displayed in dock
struct UpNextEventModel {
    var title: String
    var startDate: Date
}
// Interface for any event source
protocol IUpNextSource {
    var hasPermission : Bool { get }
    init()
    func getUpcomingEvents(dateLowerBounds: Date, dateUpperBounds: Date) -> [UpNextEventModel]
}

class UpNextCalenderSource : IUpNextSource {
    public var hasPermission: Bool = false
    private let eventStore = EKEventStore() //
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
        var upcomingEvents: [UpNextEventModel] = []
        let calendars = self.eventStore.calendars(for: .event)
        
        for calendar in calendars {
            
            let predicate = self.eventStore.predicateForEvents(withStart: dateLowerBounds, end: dateUpperBounds, calendars: [calendar])

            let events = self.eventStore.events(matching: predicate)
            for event in events {
                upcomingEvents.append(UpNextEventModel(title: event.title, startDate: event.startDate))
            }
        }
        
        print("Found " + String(upcomingEvents.count) + " events.")
        return upcomingEvents
    }
}
