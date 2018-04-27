import Foundation

class ScrollViewItem: NSCustomTouchBarItem {
    
    init(identifier: NSTouchBarItem.Identifier, items: [NSTouchBarItem]) {
        super.init(identifier: identifier)
        let views = items.compactMap { $0.view }
        let stackView = NSStackView(views: views)
        stackView.spacing = 1
        stackView.orientation = .horizontal
        let scrollView = NSScrollView(frame: CGRect(origin: .zero, size: stackView.fittingSize))
        scrollView.documentView = stackView
        scrollView.documentView?.bounds.origin = CGPoint(x: 0.0, y: -5.5)
        self.view = scrollView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
