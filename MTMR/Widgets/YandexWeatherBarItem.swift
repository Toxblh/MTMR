//
//  YandexWeatherBarItem.swift
//  MTMR
//
//  Created by bobrosoft on 22/07/2019.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa
import CoreLocation

class YandexWeatherBarItem: CustomButtonTouchBarItem, CLLocationManagerDelegate {
    private let activity: NSBackgroundActivityScheduler
    private let unitsStr = "°C"
    private let iconsSource = ["Ясно": "☀️", "Малооблачно": "🌤", "Облачно с прояснениями": "⛅️", "Пасмурно": "☁️", "Небольшой дождь": "🌦", "Дождь": "🌧", "Ливень": "⛈", "Гроза": "🌩", "Дождь со снегом": "☔️", "Небольшой снег": "❄️", "Снег": "🌨", "Туман": "🌫"]
    private var location: CLLocation!
    private var prevLocation: CLLocation!
    private var manager: CLLocationManager!
    
    init(identifier: NSTouchBarItem.Identifier, interval: TimeInterval) {
        activity = NSBackgroundActivityScheduler(identifier: "\(identifier.rawValue).updatecheck")
        activity.interval = interval
        
        super.init(identifier: identifier, title: "⏳")
        
        let status = CLLocationManager.authorizationStatus()
        if status == .restricted || status == .denied {
            print("User permission not given")
            return
        }
        
        if !CLLocationManager.locationServicesEnabled() {
            print("Location services not enabled")
            return
        }
        
        activity.repeats = true
        activity.qualityOfService = .utility
        activity.schedule { (completion: NSBackgroundActivityScheduler.CompletionHandler) in
            self.updateWeather()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
        updateWeather()
        
        manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.startUpdatingLocation()
        
        tapClosure = tapClosure ?? defaultTapAction
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func updateWeather() {
        var urlRequest = URLRequest(url: URL(string: getWeatherUrl())!)
        urlRequest.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.100 Safari/537.36", forHTTPHeaderField: "user-agent") // important for the right format
        
        let task = URLSession.shared.dataTask(with: urlRequest) { data, _, error in
            guard error == nil, let response = data?.utf8string else {
                return
            }
//            print(response)
            
            var matches: [[String]]
            var temperature: String?
            matches = response.matchingStrings(regex: "fact__temp.*?temp__value.*?>(.*?)<")
            temperature = matches.first?.item(at: 1)
            
            var icon: String?
            matches = response.matchingStrings(regex: "link__condition.*?>(.*?)<")
            icon = matches.first?.item(at: 1)
            if let _ = icon, let test = self.iconsSource[icon!] {
                icon = test
            }
            
            if temperature != nil {
                DispatchQueue.main.async {
                    self.setWeather(text: "\(icon ?? "?") \(temperature!)\(self.unitsStr)")
                }
            }
        }
        
        task.resume()
    }
    
    func getWeatherUrl() -> String {
        if location != nil {
            return "https://yandex.ru/pogoda/?lat=\(location.coordinate.latitude)&lon=\(location.coordinate.longitude)"
        } else {
            return "https://yandex.ru/pogoda/" // Yandex will try to determine your location by default
        }
    }
    
    func setWeather(text: String) {
        title = text
    }
    
    func defaultTapAction() {
        print(getWeatherUrl())
        if let url = URL(string: getWeatherUrl()) {
            NSWorkspace.shared.open(url)
        }
    }
    
    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let lastLocation = locations.last!
        location = lastLocation
        if prevLocation == nil {
            updateWeather()
        }
        prevLocation = lastLocation
    }
    
    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        print(error)
    }
    
    func locationManager(_: CLLocationManager, didChangeAuthorization _: CLAuthorizationStatus) {
        updateWeather()
    }
    
    deinit {
        activity.invalidate()
    }
}

extension String {
    func matchingStrings(regex: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: regex, options: []) else { return [] }
        let nsString = self as NSString
        let results  = regex.matches(in: self, options: [], range: NSMakeRange(0, nsString.length))
        return results.map { result in
            (0..<result.numberOfRanges).map {
                result.range(at: $0).location != NSNotFound
                    ? nsString.substring(with: result.range(at: $0))
                    : ""
            }
        }
    }
}

extension Array {
    func item(at index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
