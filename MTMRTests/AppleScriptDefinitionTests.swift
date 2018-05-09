import XCTest

class AppleScriptDefinitionTests: XCTestCase {

    func testInline() {
        let buttonNoActionFixture = """
            [  { "type": "appleScriptTitledButton",  "source": { "inline":  "tell everything fine" } } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        guard case .appleScriptTitledButton(let source, _)? = result?.first?.type else {
            XCTFail()
            return
        }
        XCTAssertEqual(source.string, "tell everything fine")
    }
    
    func testPath() {
        let buttonNoActionFixture = """
            [  { "type": "appleScriptTitledButton",  "source": { "filePath":  "/ololo/pew" } } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        guard case .appleScriptTitledButton(let source, _)? = result?.first?.type else {
            XCTFail()
            return
        }
        let sourceStruct = source as? Source
        XCTAssertEqual(sourceStruct?.filePath, "/ololo/pew")
    }
    
    func testRefreshInterval() {
        let buttonNoActionFixture = """
            [  { "type": "appleScriptTitledButton",  "source": { "inline":  "tell everything fine" },  "refreshInterval": 305} ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        guard case .appleScriptTitledButton(_, 305)? = result?.first?.type else {
            XCTFail()
            return
        }
    }
    
}
