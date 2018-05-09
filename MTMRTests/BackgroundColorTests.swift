import XCTest

class BackgroundColorTests: XCTestCase {
    
    func testOpaque() {
        let buttonNoActionFixture = """
            [  { "type": "staticButton",  "title": "Pew", "background": "#FF0000" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        guard case .background(let color)? = result?.first?.additionalParameters[.background] else {
            XCTFail()
            return
        }
        XCTAssertEqual(color, .red)
    }
    
    func testAlpha() {
        let buttonNoActionFixture = """
            [  { "type": "staticButton",  "title": "Pew", "background": "#FF000080" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        guard case .background(let color)? = result?.first?.additionalParameters[.background] else {
            XCTFail()
            return
        }
        XCTAssertEqual(color.alphaComponent, 0.5, accuracy: 0.01)
    }
    
}
