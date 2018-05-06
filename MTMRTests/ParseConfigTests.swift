import XCTest
@testable import MTMR

class ParseConfig: XCTestCase {
    
    func testButtonNoAction() {
        let buttonNoActionFixture = """
            [  { "type": "staticButton",  "title": "Pew" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        XCTAssertEqual(result?.first?.type, .staticButton(title: "Pew"))
        XCTAssertEqual(result?.first?.action, .some(.none))
    }

    func testButtonKeyCodeAction() {
        let buttonKeycodeFixture = """
            [  { "type": "staticButton",  "title": "Pew", "action": "hidKey", "keycode": 123} ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        XCTAssertEqual(result?.first?.type, .staticButton(title: "Pew"))
        XCTAssertEqual(result?.first?.action, .hidKey(keycode: 123))
    }
    
    func testPredefinedItem() {
        let buttonKeycodeFixture = """
            [  { "type": "escape" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        XCTAssertEqual(result?.first?.type, .staticButton(title: "esc"))
        XCTAssertEqual(result?.first?.action, .keyPress(keycode: 53))
    }
    
    func testExtendedWidthForPredefinedItem() {
        let buttonKeycodeFixture = """
            [  { "type": "escape", "width": 110}, ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        XCTAssertEqual(result?.first?.type, .staticButton(title: "esc"))
        XCTAssertEqual(result?.first?.action, .keyPress(keycode: 53))
    }
    
}
