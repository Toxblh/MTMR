//
//  CurrencyBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 18.04.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa
import CoreLocation

class CurrencyBarItem: CustomButtonTouchBarItem {
    private let activity = NSBackgroundActivityScheduler(identifier: "com.toxblh.mtmr.currency.updatecheck")
    private var prefix: String
    private var from: String
    private var to: String
    private var oldValue: Float32!

    private let currencies = [
        "USD": "$",
        "EUR": "€",
        "RUB": "₽",
        "JPY": "¥",
        "GBP": "₤",
        "CAD": "$",
        "KRW": "₩",
        "CNY": "¥",
        "AUD": "$",
        "BRL": "R$",
        "IDR": "Rp",
        "MXN": "$",
        "SGD": "$",
        "CHF": "Fr.",
        "BTC": "฿",
        "LTC": "Ł",
        "ETH": "Ξ",
    ]

    init(identifier: NSTouchBarItem.Identifier, interval: TimeInterval, from: String, to: String, onTap: @escaping () -> (), onLongTap: @escaping () -> ()) {
        activity.interval = interval
        self.from = from
        self.to = to

        if let prefix = currencies[from] {
            self.prefix = prefix
        } else {
            self.prefix = from
        }

        super.init(identifier: identifier, title: "⏳", onTap: onTap, onLongTap: onLongTap)

        self.view = button

        activity.repeats = true
        activity.qualityOfService = .utility
        activity.schedule { (completion: NSBackgroundActivityScheduler.CompletionHandler) in
            self.updateCurrency()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
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
//                    print(json)
                    var value: Float32!

                    if let data_array = json["data"] as? [String : AnyObject] {
                        if let rates = data_array["rates"] as? [String : AnyObject] {
                            if let item = rates["\(self.to)"] as? String {
                                value = Float32(item)
                            }
                        }
                    }
                    if value != nil {
                        DispatchQueue.main.async {
                            self.setCurrency(value: value!)
                        }
                    }
                } catch let jsonError {
                    print(jsonError.localizedDescription)
                }
            }
        }

        task.resume()
    }

    func setCurrency(value: Float32) {
        var color = NSColor.white

        if let oldValue = self.oldValue {
            if oldValue < value {
                color = NSColor.green
            } else if oldValue > value {
                color = NSColor.red
            }
        }
        self.oldValue = value

        button.title = String(format: "%@%.2f", self.prefix, value)

        let textRange = NSRange(location: 0, length: button.title.count)
        let newTitle = NSMutableAttributedString(string: button.title)
        newTitle.addAttribute(NSAttributedStringKey.foregroundColor, value: color, range: textRange)
        newTitle.addAttribute(NSAttributedStringKey.font, value: button.font!, range: textRange)
        newTitle.setAlignment(.center, range: textRange)

        button.attributedTitle = newTitle
    }
}
