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
    private let eventStore = EKEventStore() //
    private let df = DateFormatter()
    private let buttonTemplate = "🗓 %@ - %@ "
    
    // Settings
    private var futureSearchCutoff: Double
    private var pastSearchCutoff: Double
    private var nthEvent: Int
    
    // State
    private var hasPermission: Bool = false

    
    /// <#Description#>
    /// - Parameters:
    ///   - identifier: Unique identifier of widget
    ///   - interval: Update view interval in seconds
    ///   - from: Relative to current time, how far back we search for events in hours
    ///   - to: Relative to current time, how far forward we search for events in hours
    ///   - nthEvent:  Which event to show (1 is first, 2 is second, and so on)
    init(identifier: NSTouchBarItem.Identifier, interval: TimeInterval, from: Double, to: Double, nthEvent: Int) {
        activity = NSBackgroundActivityScheduler(identifier: "\(identifier.rawValue).updateCheck")
        activity.interval = interval
        self.pastSearchCutoff = from
        self.futureSearchCutoff = to
        self.nthEvent = nthEvent
        self.df.dateFormat = "HH:mm"
        
        if (nthEvent <= 0) {
            fatalError("Error on UpNext bar item.  nthEvent property must be greater than 0.")
        }

        super.init(identifier: identifier, title: " ")
        let authorizationStatus = EKEventStore.authorizationStatus(for: EKEntityType.event)
        switch authorizationStatus {
        case .notDetermined:
            print("notDetermined")
        case .restricted:
            print("restricted")
        case .denied:
            print("denied")
        case .authorized:
            print("authorizded")
        default:
            print("Unkown EKEventStore authorization status")
         }
        eventStore.requestAccess(to: .event){ granted, error in
            self.hasPermission = granted;
            if(!granted) {
                 NSLog("Error: MTMR UpNextBarWidget not given calendar access.")
                 return
             }
            self.updateView()
        }
        
        
        tapClosure = { [weak self] in self?.gotoAppleCalendar() }

        
        // Start activity to update view
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
        if (!self.hasPermission) {
            self.title = "🗓 No permissions"
            return
        }
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
                        
            DispatchQueue.main.async {
                print("SHOW")
                self.image = nil
                self.title = String(format: self.buttonTemplate, title, startDateString ?? "No time")
                self.view.isHidden = false
            }
        } else {
           // Do not display any event
            DispatchQueue.main.async {
                print("HIDE " + String(upcomingEvents.count) + " " + String(self.nthEvent) + " " + String(upcomingEvents.count > self.nthEvent))
                self.image = nil
                self.title = ""
                self.view.isHidden = true
            }
        }
    }
    
    func getUpcomingEvents() -> [UpNextEventModel] {
        var upcomingEvents: [UpNextEventModel] = []

        NSLog("Getting calendar events...")
        // Calculate the range we're going to search for events in
        let dateLowerBounds = Date(timeIntervalSinceNow: self.pastSearchCutoff * 360)
        let dateUpperBounds = Date(timeIntervalSinceNow: self.futureSearchCutoff * 360)
        
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
    
    func gotoAppleCalendar() {
        print("CLICK")
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Photos.app"))
    }}

struct UpNextEventModel {
    var title: String
    var startDate: Date
}
