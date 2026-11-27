//
//  TouchBarVisibility.swift
//  MTMR
//
//  Showing and hiding a widget at run time. The left and right parts of the bar are stack views laid out by
//  constraints, which drop hidden views on their own. The scrolling centre (ScrollViewItem) is a stack view
//  inside a scroll view whose size is set once, when the bar is built; it has to be resized by hand, or a
//  widget that starts hidden and appears later is clipped.
//

import AppKit

extension NSView {
    func setShownInBar(_ shown: Bool) {
        guard isHidden == shown else { return }
        isHidden = !shown
        guard let stack = superview as? NSStackView,
              let scroll = stack.enclosingScrollView, scroll.documentView === stack
        else { return }
        stack.setFrameSize(stack.fittingSize)
    }
}
