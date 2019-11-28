//
//  NotificationsTouchBarItem.swift
//  MTMR
//
//  Created by Matthew Cox on 10/22/19.
//  Copyright © 2019 Anton Palgunov. All rights reserved.
//

import Foundation
import Cocoa
import ScriptingBridge
import SQLite
import Contacts
import UserNotifications

class NotificationBarItem: CustomButtonTouchBarItem {
    public enum Message: String {
        case Messages = "com.apple.iChat"
        case Mail = "com.apple.mail"
    }
    

    private let notificationIdentifiers = [
        Message.Messages,
        Message.Mail,
    ]
    
    private let interval: TimeInterval
    private let disableMarquee: Bool
    private var messageText: String?
    private var messageFrom: String?
    private var timer: Timer?
    private let iconSize = NSSize(width: 21, height: 21)
    private let activity: NSBackgroundActivityScheduler

    init(identifier: NSTouchBarItem.Identifier, interval: TimeInterval, disableMarquee: Bool, image: NSImage? = nil) {

        self.interval = interval
        self.disableMarquee = disableMarquee
        //tapClosure = { [weak self] in self?.DarkModeToggle() }
        if image == nil {
            //sliderItem = CustomSlider()
        } else {
           // sliderItem = CustomSlider(knob: image!)
        }
        
        
        activity = NSBackgroundActivityScheduler(identifier: "\(identifier.rawValue).updatecheck")
        activity.interval = interval
        
        super.init(identifier: identifier, title: "⏳")
        //var systemBlue: NSColor { set }
        isBordered = false
        backgroundColor = NSColor.systemRed
        //button = item.view as? NSButton else { continue }
        
        //let textRange = NSRange(location: 0, length: button.title.characters.count)
        //let titleColor = useCustomColor.state == NSControl.StateValue.on ? NSColor.black : NSColor.white
        //let newTitle = NSMutableAttributedString(string: button.title)
        //newTitle.addAttribute(NSAttributedStringKey.foregroundColor, value: titleColor, range: textRange)
        //newTitle.addAttribute(NSAttributedStringKey.font, value: button.font!, range: textRange)
        //newTitle.setAlignment(.center, range: textRange)
        //button.attributedTitle = newTitle
        //attributedTitle = "test"
        //image = NSImage(name: NSUserGroup)
        //title = "\(Noti.0)"
       // func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) {
       //     print("")
       // }
       // let notificationCenter = UNUserNotificationCenter.current()
         
       // notificationCenter.requestAuthorization(options: [.alert, .badge, .provisional]) {}
        
       // UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
       //     print("Noti")
       //     print(notifications)
            
       // }
        
      /*  let center = UNUserNotificationCenter.current()
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]
        center.requestAuthorization(options: options) { (granted, error) in
            if granted {
                application.registerForRemoteNotifications()
            }
        }
        
        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
            let actionIdentifier = response.actionIdentifier
            let content = response.notification.request.content
             print("\(content)")
            switch actionIdentifier {
            case UNNotificationDismissActionIdentifier: // Notification was dismissed by user
                // Do something
                completionHandler()
            case UNNotificationDefaultActionIdentifier: // App was opened from notification
                // Do something
                completionHandler()
            case "com.usernotificationstutorial.reply":
                if let textResponse = response as? UNTextInputNotificationResponse {
                    let reply = textResponse.userText
                    // Send reply message
                    completionHandler()
                }
            case "com.usernotificationstutorial.delete":
                // Delete message
                completionHandler()
            default:
                completionHandler()
            }

        */
        /*let replyAction = UNTextInputNotificationAction(identifier: "com.usernotificationstutorial.reply", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Type your message")
        let deleteAction = UNNotificationAction(identifier: "com.usernotificationstutorial.delete", title: "Delete", options: [.authenticationRequired, .destructive])
        let category = UNNotificationCategory(identifier: "com.usernotificationstutorial.message", actions: [replyAction, deleteAction], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])

        }
        
        userNotificationCenter(center: center)
        */
        tapClosure = { [weak self] in self?.playPause() }
        longTapClosure = { [weak self] in self?.nextTrack() }

        refreshAndSchedule()
    }
    
    @objc func marquee() {
        let str = title
        if str.count > 10 {
            let indexFirst = str.index(str.startIndex, offsetBy: 0)
            let indexSecond = str.index(str.startIndex, offsetBy: 1)
            title = String(str.suffix(from: indexSecond)) + String(str[indexFirst])
        }
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func playPause() {
        for ident in notificationIdentifiers {
            if let messageApplication = SBApplication(bundleIdentifier: ident.rawValue) {
                if messageApplication.isRunning {
                    if ident == .Messages {
                        let mp = (messageApplication as MessagesApplication)
                        mp.playpause!()
                        return
                    } else if ident == .Mail {
                        let mp = (messageApplication as MailApplication)
                        mp.playpause!()
                        return
                    }
                    break
                }
            }
        }
    }

    @objc func nextTrack() {
        for ident in notificationIdentifiers {
            if let messageApplication = SBApplication(bundleIdentifier: ident.rawValue) {
                if messageApplication.isRunning {
                    if ident == .Messages {
                        let mp = (messageApplication as MessagesApplication)
                        mp.nextTrack!()
                        updateNotification()
                        return
                    } else if ident == .Mail {
                        let mp = (messageApplication as MailApplication)
                        mp.nextTrack!()
                        updateNotification()
                        return
                    }
                }
            }
        }
    }

    func refreshAndSchedule() {
        DispatchQueue.main.async {
            self.updateNotification()
            DispatchQueue.main.asyncAfter(deadline: .now() + self.interval) { [weak self] in
                self?.refreshAndSchedule()
            }
        }
    }
    
    
    
    
    
    
    
    
    
    
    
    
    

    
    
    
    
    
    
    
    
    
    
    
    
    
    

    
    
    
    
    
    
    
    func updateNotification() {
        var iconUpdated = false
        var titleUpdated = false
        var notificationbuilder = ""
        
        let name = ""
        let message = ""
        let durl = ""
        let person = ""
        let dbpath = ""
        let Noti = NotiBar().getAll(name: name, message: message, durl: durl, person: person, dbpath: dbpath)
        //let lastNotificationItem = ""

        print("\(Noti.0) \(Noti.1) \(Noti.3)")
        //icon \(Noti.0)
        //Message \(Noti.1)
        //button path \(Noti.2)
        //Number \(Noti.3)
        let fromBox = String(Noti.3)
        let messageBox = String(Noti.1)
        
        if fromBox.isEmpty
        {
            notificationbuilder = ""
        }
        else
        {
            notificationbuilder = "\(fromBox) - \(messageBox)"
        }

        let lastNotificationItem = "\(notificationbuilder)"
        
        for ident in notificationIdentifiers {
            if let messageApplication = SBApplication(bundleIdentifier: ident.rawValue) {
                if messageApplication.isRunning {
                    
                    var tempTitle = ""
                    if ident == .Messages {
                        tempTitle = lastNotificationItem
                    } else if ident == .Mail {
                        tempTitle = (messageApplication as MailApplication).title
                    }

                    if tempTitle == self.messageText {
                        return
                    } else {
                        self.messageText = tempTitle
                    }

                    if let messageText = self.messageText?.ifNotEmpty {
                        self.timer?.invalidate()
                        self.timer = nil
                        
                        if (disableMarquee) {
                            self.title = " " + messageText
                        } else {
                            self.title = " " + messageText + "     "
                            self.timer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(self.marquee), userInfo: nil, repeats: true)
                        }
                        
                        titleUpdated = true
                    }
                    if let _ = tempTitle.ifNotEmpty,
                        let appPath = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: ident.rawValue) {
                        let image = NSWorkspace.shared.icon(forFile: appPath)
                        image.size = self.iconSize
                        self.image = image
                        iconUpdated = true
                    }
                    break
                }
            }
        }

        DispatchQueue.main.async {
            if !iconUpdated {
                self.image = nil
            }

            if !titleUpdated {
                self.title = ""
            }
        }
    }
}





class NotiRun {
    static func shell(launchPath path: String, arguments args: [String]) -> String {
        let task = Process()
        task.launchPath = path
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)
        task.waitUntilExit()

        return(output!)
    }
    
}

class NotiBar
{
    
    func getAll(name:String, message:String, durl: String, person:String, dbpath: String) -> (String, String, String, String, String)
    {
    
    let res = NotiRun.shell(launchPath: "/usr/bin/getconf", arguments: ["DARWIN_USER_DIR"])
    let trimmedres = res.trimmingCharacters(in: .whitespacesAndNewlines)
    let db = try! Connection("\(trimmedres)com.apple.notificationcenter/db2/db")

    let record = Table("record")
    let app = Table("app")
    let presented = Expression<Int?>("presented")
    let identifier = Expression<String?>("identifier")
    let delivered_date = Expression<Int?>("delivered_date")
    let app_id = Expression<Int?>("app_id")
   // let app_id = Expression<Int64>("app_id")
    let data = Expression<Data>("data")
    var name = ""
    var message = ""
    var durl = ""
    var person = ""
    var dbpath = ""
    let timestamp = Int(NSDate().timeIntervalSinceReferenceDate - 86400)
    //var image = ""
    //var reply = ""
    //var dismiss = ""
    //var other = ""
    let Messages = String("com.apple.iChat")
    let Mail = String("com.apple.mail")

        for app in try! db.prepare(app.select(app[*]))
        {
            if ("\(app[identifier]!)" == Messages)
            {
                
            }
            if ("\(app[identifier]!)" == Mail)
            {
            
            }
           // Messages
           // Mail
        }
       // print("\(timestamp)")
        //for record in try! db.prepare(record.join(app, on: record[app_id] == app[app_id]).select(record[*]).filter(delivered_date > timestamp) ) {
        //app_id == 4 ||
        for record in try! db.prepare(record.select(record[*]).filter(delivered_date > timestamp && app_id == 5) ) {

        guard let notifierout = try? PropertyListSerialization.propertyList(from: record[data], options: [], format: nil) else {
            fatalError("failed to deserialize")
        }
        if let notiDescAppName = (notifierout as AnyObject)["app"]! as? String
        {
            if let ret = self.getPath(appNamedNew: "\(notiDescAppName)") {
                let retfix = ("\(ret)")
                let rettrimmed = retfix.trimmingCharacters(in: .whitespacesAndNewlines)

            let notifierbuilder = Bundle(url: URL(fileURLWithPath: "\(rettrimmed)"))?.infoDictionary?["CFBundleDisplayName"] as? String ?? Bundle(url: URL(fileURLWithPath: "\(rettrimmed)"))?.infoDictionary?["CFBundleName"] as? String
             if notifierbuilder == nil
             {
             }
             else
             {
                if (notifierbuilder == "Messages" || notifierbuilder == "Mail")
                {
                    if (notifierbuilder == "Messages")
                    {
                        name = "💬"
                    }
                    else if notifierbuilder == "Mail"
                    {
                        name = "✉️"
                    }
                    
                    if let notiDescAppMessageTop = (notifierout as AnyObject)["req"]! as? AnyObject
                       {
                           if let notiDescAppMail = (notiDescAppMessageTop as AnyObject)["subt"]! as? String
                           {
                               message = notiDescAppMail
                           }
                           else if let notiDescAppMessage = (notiDescAppMessageTop as AnyObject)["body"]! as? String
                           {
                               message = notiDescAppMessage
                       }
                       }
                       if let notiDescAppURLTop = (notifierout as AnyObject)["req"]! as? AnyObject
                        {
                            if let notiDescAppURL = (notiDescAppURLTop as AnyObject)["durl"]! as? String
                            {
                                durl = notiDescAppURL
                        }
                        }
                       if let notiDescAppPersonTop = (notifierout as AnyObject)["req"]! as? AnyObject
                       {
                           if let notiDescAppPerson = (notiDescAppPersonTop as AnyObject)["titl"]! as? String
                           {

                               person = notiDescAppPerson
                       }
                          // let imagee = getContactImage(imgu: "\(person)")
                       }
                }
                else
                {
                name = notifierbuilder!
                }
             }
        }
    }
        
        dbpath = "\(trimmedres)com.apple.notificationcenter/db2/db"
    }
        //print("\(name)-\(message)-\(durl)-\(person)-\(dbpath)")
        return (name, message, durl, person, dbpath)
    }
    // static func getImage(image: String) -> String
    //{
        
    //}
    //static func getOptionReply(reply: String) -> String
    //{
        
    //}
    //static func getOptionDismiss(dismiss: String) -> String
    //{
        
    //}
    //static func getOptionOther(otNSView()her: String) -> String
    //{
        
    //}

    func getPath(appNamedNew: String) -> String? {
     
       if let absopath = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: appNamedNew) {
            return "\(absopath)"
        } else {
            return ""
        }
    }
    
    func lastModified(path: String) -> NSDate? {
        let fileUrl = NSURL(fileURLWithPath: path)
        var modified: AnyObject?
        do {
          try fileUrl.getResourceValue(&modified, forKey: URLResourceKey.contentModificationDateKey)
            return modified as? NSDate
        } catch let error as NSError {
            print("\(#function) Error: \(error)")
            return nil
        }
    }
    
}

func getContactImage(imgu:String) -> NSImage?
{
    let store = CNContactStore()
    //let contactStore = CNContactStore()
    let keys = [CNContactPhoneNumbersKey, CNContactFamilyNameKey, CNContactGivenNameKey, CNContactNicknameKey, CNContactImageDataKey] as! CNKeyDescriptor
   // let request = CNContactFetchRequest(keysToFetch: keys)

  //  try? contactStore.enumerateContacts(with: request) { (contact, error) in

        // Do something with contact

    //}
    
    
    do
    {
        let contacts = try! store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: imgu), keysToFetch:[keys])
        
        if contacts.count > 0
        {
            if let image = contacts[0].imageData
            {
                return NSImage.init(data: image)
            }
        }
    
    }

    return nil
}


@objc protocol MessagesApplication {
    @objc optional var currentTrack: SpotifyTrack { get }
    @objc optional func nextTrack()
    @objc optional func previousTrack()
    @objc optional func playpause()
}

extension SBApplication: MessagesApplication {}

@objc protocol MessagesTrack {
    @objc optional var artist: String { get }
    @objc optional var name: String { get }
}

extension SBObject: MessagesTrack {}

extension MessagesApplication {
    var title: String {
        guard let t = currentTrack else { return "" }
        return (t.artist ?? "") + " — " + (t.name ?? "")
    }
}

@objc protocol MailApplication {
    @objc optional var currentTrack: MailTrack { get }
    @objc optional func playpause()
    @objc optional func nextTrack()
    @objc optional func previousTrack()
}

extension SBApplication: MailApplication {}

@objc protocol MailTrack {
    @objc optional var artist: String { get }
    @objc optional var name: String { get }
}

extension SBObject: MailTrack {}

extension MailApplication {
    var title: String {
        guard let t = currentTrack else { return "" }
        return (t.artist ?? "") + " — " + (t.name ?? "")
    }
}
