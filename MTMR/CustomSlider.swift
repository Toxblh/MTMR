//
//  CustomSlider.swift
//  MTMR
//
//  Created by Anton Palgunov on 15/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

class CustomSliderCell: NSSliderCell {
    var knobImage:NSImage!
    private var _currentKnobRect:NSRect!
    private var _barRect:NSRect!
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override init() {
        super.init()
    }
    
    init(knob:NSImage?) {
        knobImage = knob;
        super.init()
    }
    
    override func drawKnob(_ knobRect: NSRect) {
        if (knobImage == nil) {
            super.drawKnob(knobRect)
            return;
        }

        _currentKnobRect = knobRect;
        drawBar(inside: _barRect, flipped: true)

        let x = (knobRect.origin.x * (_barRect.size.width - (knobImage.size.width - knobRect.size.width)) / _barRect.size.width)+1;
        let y = knobRect.origin.y+3

        knobImage.draw(
            at: NSPoint(x: x, y: y),
            from: NSZeroRect,
            operation: NSCompositingOperation.sourceOver,
            fraction: 1
        )
    }
    
    override func drawBar(inside aRect: NSRect, flipped: Bool) {
        _barRect = aRect
        
        var rect = aRect
        rect.size.height = CGFloat(4)
        let barRadius = CGFloat(2)
        let value = CGFloat((self.doubleValue - self.minValue) / (self.maxValue - self.minValue))
        let finalWidth = CGFloat(value * (self.controlView!.frame.size.width - 12))
        
        var leftRect = rect
        leftRect.size.width = finalWidth
        let bg = NSBezierPath(roundedRect: rect, xRadius: barRadius, yRadius: barRadius)
        NSColor.lightGray.setFill()
        bg.fill()
        
        let active = NSBezierPath(roundedRect: leftRect, xRadius: barRadius, yRadius: barRadius)
        NSColor.darkGray.setFill()
        active.fill()
    }
}

class CustomSlider:NSSlider {
    
    var currentValue:CGFloat = 0
    
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        if ((self.cell?.isKind(of: CustomSliderCell.self)) == false) {
            let cell:CustomSliderCell = CustomSliderCell()
            self.cell = cell
        }
    }
    
    convenience init(knob:NSImage) {
        self.init()
        self.cell = CustomSliderCell(knob: knob)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    func knobImage() -> NSImage {
        let cell = self.cell as! CustomSliderCell
        return cell.knobImage
    }
    
    func setKnobImage(image:NSImage) {
        let cell = self.cell as! CustomSliderCell
        cell.knobImage = image
    }
}
