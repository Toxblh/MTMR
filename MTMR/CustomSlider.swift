//
//  CustomSlider.swift
//  MTMR
//
//  Created by Anton Palgunov on 15/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

class CustomSliderCell: NSSliderCell {
    /// Template knobs (the outline icons) are stored pre-tinted white: drawn as-is they are black and
    /// disappear on the black Touch Bar. Colour images are kept unchanged.
    var knobImage: NSImage! {
        didSet { knobImage = Self.touchBarKnob(knobImage) }
    }

    /// didSet does not run for assignments inside this class's own initializers, so init(knob:) calls this too.
    private static func touchBarKnob(_ image: NSImage?) -> NSImage? {
        guard let image = image, image.isTemplate else { return image }
        return IconLibrary.tinted(image, color: .white)
    }
    private var _currentKnobRect: NSRect!
    private var _barRect: NSRect!

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override init() {
        super.init()
    }

    init(knob: NSImage?) {
        super.init()
        knobImage = Self.touchBarKnob(knob)
    }

    override func drawKnob(_ knobRect: NSRect) {
        if knobImage == nil {
            super.drawKnob(knobRect)
            return
        }

        _currentKnobRect = knobRect
        drawBar(inside: _barRect, flipped: true)

        // A Touch Bar slider is only ~19 pt high (measured on an M1); a 24 pt icon drawn at its natural size
        // from y+3 was cut off at the bottom. Fit the knob to the control's height and centre it vertically;
        // the horizontal travel formula is unchanged, only it uses the drawn width.
        let height = controlView?.bounds.height ?? knobRect.height
        let side = min(knobImage.size.height, max(height - 2, 1))
        let width = knobImage.size.width * side / max(knobImage.size.height, 1)
        let x = (knobRect.origin.x * (_barRect.size.width - (width - knobRect.size.width)) / _barRect.size.width) + 1
        let y = (height - side) / 2

        // Clear the track under the knob so the white icon stays readable over the bright active part.
        let knobFrame = NSRect(x: x, y: y, width: width, height: side)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: knobFrame.insetBy(dx: -2, dy: 0), xRadius: 4, yRadius: 4).fill()
        knobImage.draw(
            in: knobFrame,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    override func drawBar(inside aRect: NSRect, flipped _: Bool) {
        _barRect = aRect

        let barRadius = CGFloat(2)

        var bgRect = aRect
        bgRect.size.height = CGFloat(4)

        // Inactive track (right of the knob) dark, active part (the value) bright, like the system sliders'
        // filled track; it used to be the other way round.
        let bg = NSBezierPath(roundedRect: bgRect, xRadius: barRadius, yRadius: barRadius)
        NSColor(white: 0.3, alpha: 1).setFill()
        bg.fill()

        var activeRect = bgRect

        activeRect.size.width = CGFloat((Double(bgRect.size.width) / (maxValue - minValue)) * doubleValue)
        let active = NSBezierPath(roundedRect: activeRect, xRadius: barRadius, yRadius: barRadius)
        NSColor(white: 0.85, alpha: 1).setFill()
        active.fill()
    }
}

class CustomSlider: NSSlider {
    var currentValue: CGFloat = 0

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        if (cell?.isKind(of: CustomSliderCell.self)) == false {
            let cell: CustomSliderCell = CustomSliderCell()
            self.cell = cell
        }
    }

    convenience init(knob: NSImage) {
        self.init()
        cell = CustomSliderCell(knob: knob)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    /// An NSSlider has no intrinsic width, so on the Touch Bar a slider without a preset "width" collapsed
    /// to ~2 pt and looked missing (measured on an M1). This default sits below the required constraint
    /// that a preset "width" installs (TouchBarController setWidth), so an explicit width still wins.
    static let defaultTouchBarWidth: CGFloat = 150

    func applyDefaultTouchBarWidth() {
        let constraint = widthAnchor.constraint(equalToConstant: CustomSlider.defaultTouchBarWidth)
        constraint.priority = .defaultHigh
        constraint.isActive = true
    }

    func knobImage() -> NSImage {
        let cell = self.cell as! CustomSliderCell
        return cell.knobImage
    }

    func setKnobImage(image: NSImage) {
        let cell = self.cell as! CustomSliderCell
        cell.knobImage = image
    }
}
