import XCTest

class ParseConfig: XCTestCase {
    func testButtonNoAction() {
        let buttonNoActionFixture = """
            [  { "type": "staticButton",  "title": "Pew" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        guard case .staticButton("Pew")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard result?.first?.actions.count == 0 else {
            XCTFail()
            return
        }
    }

    func testButtonKeyCodeAction() {
        let buttonKeycodeFixture = """
            [  { "type": "staticButton",  "title": "Pew", "actions": [ { "trigger": "singleTap", "action": "hidKey", "keycode": 123 } ] } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("Pew")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .hidKey(keycode: 123)? = result?.first?.actions.filter({ $0.trigger == .singleTap }).first?.value else {
            XCTFail()
            return
        }
    }
    
    func testButtonKeyCodeLegacyAction() {
        let buttonKeycodeFixture = """
            [  { "type": "staticButton",  "title": "Pew", "action": "hidKey", "keycode": 123 } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("Pew")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .hidKey(keycode: 123)? = result?.first?.legacyAction else {
            XCTFail()
            return
        }
    }

    func testPredefinedItem() {
        let buttonKeycodeFixture = """
            [  { "type": "escape" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("esc")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .keyPress(keycode: 53)? = result?.first?.actions.filter({ $0.trigger == .singleTap }).first?.value else {
            XCTFail()
            return
        }
    }

    func testCodexItemsAndKeyCombo() {
        let fixture = """
            [
              {
                "type": "staticButton",
                "title": "",
                "image": { "systemName": "bubble.left.and.bubble.right" },
                "action": "keyCombo",
                "keycode": 45,
                "modifiers": ["command", "option"]
              },
              { "type": "codexToday", "refreshInterval": 20 },
              { "type": "codexQuota", "refreshInterval": 30 }
            ]
        """.data(using: .utf8)!

        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: fixture)
        XCTAssertEqual(result?.count, 3)

        guard case let .keyCombo(keycode, modifiers)? = result?.first?.legacyAction else {
            return XCTFail("Expected keyCombo action")
        }
        XCTAssertEqual(keycode, 45)
        XCTAssertEqual(modifiers, ["command", "option"])
        guard case let .image(source)? = result?.first?.additionalParameters[.image] else {
            return XCTFail("Expected SF Symbol image source")
        }
        XCTAssertNotNil(source.image)

        guard case .codexToday(refreshInterval: 20)? = result?[1].type else {
            return XCTFail("Expected codexToday item")
        }
        guard case .codexQuota(refreshInterval: 30)? = result?[2].type else {
            return XCTFail("Expected codexQuota item")
        }
    }

    func testCodexItemsDefaultToTenSecondRefresh() throws {
        let fixture = """
            [
              { "type": "codexToday" },
              { "type": "codexQuota" }
            ]
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode([BarItemDefinition].self, from: fixture)
        guard case .codexToday(refreshInterval: 10) = result[0].type else {
            return XCTFail("Expected a 10-second codexToday default")
        }
        guard case .codexQuota(refreshInterval: 10) = result[1].type else {
            return XCTFail("Expected a 10-second codexQuota default")
        }
    }

    func testExtendedWidthForPredefinedItem() {
        let buttonKeycodeFixture = """
            [  { "type": "escape", "width": 110}, ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("esc")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .keyPress(keycode: 53)? = result?.first?.actions.filter({ $0.trigger == .singleTap }).first?.value else {
            XCTFail()
            return
        }
        guard case .width(110)? = result?.first?.additionalParameters[.width] else {
            XCTFail()
            return
        }
    }
}
