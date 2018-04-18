//
//  WeatherBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 18.04.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa
import CoreLocation

class WeatherBarItem: NSCustomTouchBarItem, CLLocationManagerDelegate {
    private let dateFormatter = DateFormatter()
    private var timer: Timer!
    private var interval: TimeInterval!
    private var units: String
    private var api_key: String
    private var units_str = "°F"
    private let button = NSButton(title: "", target: nil, action: nil)
    private var prev_location: CLLocation!
    private var location: CLLocation!
    
    private var manager:CLLocationManager!
    
    init(identifier: NSTouchBarItem.Identifier, interval: TimeInterval, units: String, api_key: String) {
        self.interval = interval
        self.units = units
        self.api_key = api_key
        
        if self.units == "metric" {
            units_str = "°C"
        }
        
        super.init(identifier: identifier)

        button.bezelColor = .clear
        button.title = "⏳"
        self.view = button
        
        let status = CLLocationManager.authorizationStatus()
        if status == .restricted || status == .denied {
            print("User permission not given")
            return
        }
        
        if !CLLocationManager.locationServicesEnabled() {
            print("not enabled");
            return
        }
        
        timer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(updateWeather), userInfo: nil, repeats: true)
        
        manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.startUpdatingLocation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func updateWeather() {
        if self.location != nil {
            let urlRequest = URLRequest(url: URL(string: "https://api.openweathermap.org/data/2.5/weather?lat=\(location.coordinate.latitude)&lon=\(location.coordinate.longitude)&units=\(self.units)&appid=\(self.api_key)")!)
            
            let task = URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
                
                if error == nil {
                    do {
                        let json = try JSONSerialization.jsonObject(with: data!, options: .mutableContainers) as! [String : AnyObject]
                        
                        var temperature: Int!
                        var condition_icon = ""
                        
                        if let main = json["main"] as? [String : AnyObject] {
                            if let temp = main["temp"] as? Int {
                                temperature = temp
                            }
                        }
                        
                        if let weather = json["weather"] as? NSArray, let item = weather[0] as? NSDictionary {
                            let icon = item["icon"] as! String
                            switch (icon) {
                            case "01d", "01n":
                                condition_icon = "☀️"
                                break
                            case "02d", "02n":
                                condition_icon = "⛅️"
                                break
                            case "03d", "03n", "04d", "04n":
                                condition_icon = "☁️"
                                break
                            case "09d", "09n":
                                condition_icon = "⛅️"
                                break
                            case "10d", "10n":
                                condition_icon = "🌦"
                                break
                            case "11d", "11n":
                                condition_icon = "🌩"
                                break
                            case "13d", "13n":
                                condition_icon = "❄️"
                                break
                            case "50d", "50n":
                                condition_icon = "🌫"
                                break
                            default:
                                condition_icon = ""
                            }
                        }
                        
                        if temperature != nil {
                            DispatchQueue.main.async {
                                self.setWeather(text: "\(condition_icon) \(temperature!)\(self.units_str)")
                            }
                        }
                    } catch let jsonError {
                        print(jsonError.localizedDescription)
                    }
                }
            }
            
            task.resume()
        }
    }
    
    func setWeather(text: String) {
        button.title = text
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let lastLocation = locations.last!
        self.location = lastLocation
        if prev_location == nil {
            updateWeather()
        }
        prev_location = lastLocation
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print(error);
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("inside didChangeAuthorization ");
        updateWeather()
    }
    
}

