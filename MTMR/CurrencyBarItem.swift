//
//  CurrencyBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 18.04.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa
import CoreLocation

class CurrencyBarItem: NSCustomTouchBarItem {
    private var timer: Timer!
    private var interval: TimeInterval!
    private var from: String
    private var to: String
    private let button = NSButton(title: "", target: nil, action: nil)
    
    init(identifier: NSTouchBarItem.Identifier, interval: TimeInterval, from: String, to: String) {
        self.interval = interval
        self.from = from
        self.to = to
        
        super.init(identifier: identifier)
        
        button.bezelColor = .clear
        button.title = "⏳"
        self.view = button
        
        timer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(updateCurrency), userInfo: nil, repeats: true)
        
        updateCurrency()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func updateCurrency() {
        let urlRequest = URLRequest(url: URL(string: "https://api.coinbase.com/v2/exchange-rates?currency=\(from)")!)
        
        let task = URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
            if error == nil {
                do {
                    let json = try JSONSerialization.jsonObject(with: data!, options: .mutableContainers) as! [String : AnyObject]
                    
                    var value: String!
                    
                    if let data_array = json["data"] as? [String : AnyObject] {
                        if let rates = data_array["rates"] as? [String : AnyObject] {
                            if let item = rates["\(self.to)"] as? String {
                                value = item
                            }
                        }
                    }
                    if value != nil {
                        DispatchQueue.main.async {
                            self.setCurrency(text: "\(self.from)\(value!)")
                        }
                    }
                } catch let jsonError {
                    print(jsonError.localizedDescription)
                }
            }
        }

        task.resume()
    }
    
    func setCurrency(text: String) {
        button.title = text
    }
}
