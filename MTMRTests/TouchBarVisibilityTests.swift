import AppKit
import XCTest

final class TouchBarVisibilityTests: XCTestCase {
    /// The centre of the bar is a stack view inside a scroll view whose frame is set once, from the size at
    /// creation (ScrollViewItem). A widget that starts hidden and appears with its first value must widen it,
    /// or it is clipped.
    func testShowingAViewWidensTheScrollingStack() {
        let widget = NSView()
        widget.translatesAutoresizingMaskIntoConstraints = false
        widget.widthAnchor.constraint(equalToConstant: 40).isActive = true
        widget.heightAnchor.constraint(equalToConstant: 30).isActive = true
        widget.isHidden = true
        let stack = NSStackView(views: [widget])
        let scroll = NSScrollView(frame: CGRect(origin: .zero, size: stack.fittingSize))
        scroll.documentView = stack
        XCTAssertEqual(stack.frame.width, 0)

        widget.setShownInBar(true)
        XCTAssertFalse(widget.isHidden)
        XCTAssertEqual(stack.frame.width, 40)

        widget.setShownInBar(false)
        XCTAssertTrue(widget.isHidden)
        XCTAssertEqual(stack.frame.width, 0)
    }

    func testAViewOutsideAScrollAreaIsOnlyShown() {
        let widget = NSView()
        widget.isHidden = true
        widget.setShownInBar(true)
        XCTAssertFalse(widget.isHidden)
    }
}
