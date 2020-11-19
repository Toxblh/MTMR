//
//  BasicView.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 3/29/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation


class BasicView: NSCustomTouchBarItem, NSGestureRecognizerDelegate {
    var twofingers: NSPanGestureRecognizer!
    var threefingers: NSPanGestureRecognizer!
    var fourfingers: NSPanGestureRecognizer!
    var swipeItems: [SwipeItem] = []
    var prevPositions: [Int: CGFloat] = [2:0, 3:0, 4:0]

    // legacy gesture positions
    // by legacy I mean gestures to increse/decrease volume/brigtness which can be checked from app menu
    var legacyPrevPositions: [Int: CGFloat] = [2:0, 3:0, 4:0]
    var legacyGesturesEnabled = false

    init(identifier: NSTouchBarItem.Identifier, items: [NSTouchBarItem], swipeItems: [SwipeItem]) {
        super.init(identifier: identifier)
        self.swipeItems = swipeItems
        let views = items.compactMap { $0.view }
        let stackView = NSStackView(views: views)
        stackView.spacing = 8
        stackView.orientation = .horizontal
        view = stackView

        twofingers = NSPanGestureRecognizer(target: self, action: #selector(twofingersHandler(_:)))
        twofingers.numberOfTouchesRequired = 2
        twofingers.allowedTouchTypes = .direct
        view.addGestureRecognizer(twofingers)

        threefingers = NSPanGestureRecognizer(target: self, action: #selector(threefingersHandler(_:)))
        threefingers.numberOfTouchesRequired = 3
        threefingers.allowedTouchTypes = .direct
        view.addGestureRecognizer(threefingers)

        fourfingers = NSPanGestureRecognizer(target: self, action: #selector(fourfingersHandler(_:)))
        fourfingers.numberOfTouchesRequired = 4
        fourfingers.allowedTouchTypes = .direct
        view.addGestureRecognizer(fourfingers)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureHandler(position: CGFloat, fingers: Int, state: NSGestureRecognizer.State) {
        switch state {
        case .began:
            prevPositions[fingers] = position
            legacyPrevPositions[fingers] = position
        case .changed:
            if self.legacyGesturesEnabled {
                if fingers == 2 {
                    let prevPos = legacyPrevPositions[fingers]!
                    if ((position - prevPos) > 10) || ((prevPos - position) > 10) {
                        if position > prevPos {
                            HIDPostAuxKey(NX_KEYTYPE_SOUND_UP)
                        } else if position < prevPos {
                            HIDPostAuxKey(NX_KEYTYPE_SOUND_DOWN)
                        }
                        legacyPrevPositions[fingers] = position
                    }
                }
                if fingers == 3 {
                    let prevPos = legacyPrevPositions[fingers]!
                    if ((position - prevPos) > 15) || ((prevPos - position) > 15) {
                        if position > prevPos {
                            HIDPostAuxKey(NX_KEYTYPE_BRIGHTNESS_UP)
                        } else if position < prevPos {
                            HIDPostAuxKey(NX_KEYTYPE_BRIGHTNESS_DOWN)
                        }
                        legacyPrevPositions[fingers] = position
                    }
                }
            }
        case .ended:
            print("gesture ended \(position - prevPositions[fingers]!) \(fingers)")
            for item in swipeItems {
                item.processEvent(offset: position - prevPositions[fingers]!, fingers: fingers)
            }
        default:
            break
        }
    }

    @objc func twofingersHandler(_ sender: NSGestureRecognizer?) {
        let position = (sender?.location(in: sender?.view).x)!
        self.gestureHandler(position: position, fingers: 2, state: sender!.state)
    }

    @objc func threefingersHandler(_ sender: NSGestureRecognizer?) {
        let position = (sender?.location(in: sender?.view).x)!
        self.gestureHandler(position: position, fingers: 3, state: sender!.state)
    }

    @objc func fourfingersHandler(_ sender: NSGestureRecognizer?) {
        let position = (sender?.location(in: sender?.view).x)!
        self.gestureHandler(position: position, fingers: 4, state: sender!.state)
    }
}
