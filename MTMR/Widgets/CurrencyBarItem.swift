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
    private let activity: NSBackgroundActivityScheduler
    private var prefix: String
    private var postfix: String
    private var from: String
    private var to: String
    private var oldValue: Float32!
    private var full: Bool = false

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

    init(identifier: NSTouchBarItem.Identifier, interval: TimeInterval, from: String, to: String, full: Bool) {
        activity = NSBackgroundActivityScheduler(identifier: "\(identifier.rawValue).updatecheck")
        activity.interval = interval
        self.from = from
        self.to = to
        self.full = full

        if let prefix = currencies[from] {
            self.prefix = prefix
        } else {
            prefix = from
        }

        if let postfix = currencies[to] {
            self.postfix = postfix
        } else {
            postfix = to
        }

        super.init(identifier: identifier, title: "⏳")

        activity.repeats = true
        activity.qualityOfService = .utility
        activity.schedule { (completion: NSBackgroundActivityScheduler.CompletionHandler) in
            self.updateCurrency()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
        updateCurrency()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func updateCurrency() {
        let urlRequest = URLRequest(url: URL(string: "https://api.coinbase.com/v2/exchange-rates?currency=\(from)")!)

        let task = URLSession.shared.dataTask(with: urlRequest) { data, _, error in
            if error == nil {
                do {
                    let json = try JSONSerialization.jsonObject(with: data!, options: .mutableContainers) as! [String: AnyObject]
                    var value: Float32!

                    if let data_array = json["data"] as? [String: AnyObject] {
                        if let rates = data_array["rates"] as? [String: AnyObject] {
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

        oldValue = value

        var title = ""
        if full {
            title = String(format: "%@‣%.2f%@", prefix, value, postfix)
        } else {
            title = String(format: "%@%.2f", prefix, value)
        }

        let regularFont = attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 15)
        let newTitle = NSMutableAttributedString(string: title as String, attributes: [.foregroundColor: color, .font: regularFont, .baselineOffset: 1])
        newTitle.setAlignment(.center, range: NSRange(location: 0, length: title.count))
        attributedTitle = newTitle
    }
    
    deinit {
        activity.invalidate()
    }
}
