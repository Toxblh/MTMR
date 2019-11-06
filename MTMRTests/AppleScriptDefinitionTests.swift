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

    // This tests that users can pass paths to files with ~ in them
    func testUserPath() {
        let buttonNoActionFixture = """
            [  { "type": "appleScriptTitledButton",  "source": { "filePath":  "~/pew" } } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        guard case .appleScriptTitledButton(let source, _)? = result?.first?.type else {
            XCTFail()
            return
        }
        let sourceStruct = source as? Source
        // gives you a string in the format of file:///Users/your_uer_name/pew
        let expandedPath = URL(fileURLWithPath: NSString("~/pew").expandingTildeInPath) as URL
        XCTAssertEqual(sourceStruct?.filePath?.fileURL, expandedPath)
    }

    // This tests that users can pass paths to images with ~ in them
    func testUserImagePath() {
        let relativeImagePath = """
            [  { "filePath": "~/pew/image.png" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([Source].self, from: relativeImagePath)
        // gives you a string in the format of file:///Users/your_uer_name/pew/image.png
        let expandedPath = URL(fileURLWithPath: NSString("~/pew/image.png").expandingTildeInPath) as URL
        XCTAssertEqual(result?.first?.filePath?.fileURL, expandedPath)
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
