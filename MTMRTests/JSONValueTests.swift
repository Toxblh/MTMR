import XCTest

final class JSONValueTests: XCTestCase {
    private func parse(_ text: String) throws -> JSONValue { try JSONValue.parse(text) }

    // MARK: Parser

    func testScalars() throws {
        XCTAssertEqual(try parse("null"), .null)
        XCTAssertEqual(try parse("true"), .bool(true))
        XCTAssertEqual(try parse(" false "), .bool(false))
        XCTAssertEqual(try parse("\"hi\""), .string("hi"))
    }

    func testIntegersVersusDoubles() throws {
        XCTAssertEqual(try parse("53"), .int(53))
        XCTAssertEqual(try parse("-7"), .int(-7))
        XCTAssertEqual(try parse("0"), .int(0))
        XCTAssertEqual(try parse("2.0"), .double(2.0))
        XCTAssertEqual(try parse("1e3"), .double(1000))
        XCTAssertEqual(try parse("-1.5E-2"), .double(-0.015))
        XCTAssertEqual(try parse("9223372036854775807"), .int(Int64.max))
        XCTAssertEqual(try parse("-9223372036854775808"), .int(Int64.min))
        // Does not fit Int64 -> double instead of failing.
        XCTAssertEqual(try parse("9223372036854775808"), .double(9223372036854775808))
    }

    func testInvalidNumbers() {
        for text in ["01", "-", "1.", ".5", "1e", "1e+", "--1", "+1", "1e999", "0x10"] {
            XCTAssertThrowsError(try parse(text), text)
        }
        XCTAssertThrowsError(try parse("[01]")) { error in
            XCTAssertEqual(error as? JSONParseError, .invalidNumber("01", line: 1, column: 2))
        }
    }

    func testNestingAndKeyOrder() throws {
        let value = try parse(#"{"b": [1, {"x": null}], "a": {}, "c": []}"#)
        let object = try XCTUnwrap(value.objectValue)
        XCTAssertEqual(object.keys, ["b", "a", "c"])
        XCTAssertEqual(object["b"]?.arrayValue?.count, 2)
        XCTAssertEqual(object["a"], .object(JSONObject()))
        XCTAssertEqual(object["c"], .array([]))
    }

    func testDuplicateKeysLastWinsAtFirstPosition() throws {
        let object = try XCTUnwrap(try parse(#"{"a": 1, "b": 2, "a": 3}"#).objectValue)
        XCTAssertEqual(object.keys, ["a", "b"])
        XCTAssertEqual(object["a"], .int(3))
    }

    func testLineAndBlockComments() throws {
        let text = """
        // leading
        [
          1, // one
          /* two
             lines */ 2,
          3 /* trailing */
        ] // end
        """
        XCTAssertEqual(try parse(text), .array([.int(1), .int(2), .int(3)]))
    }

    func testCommentMarkersInsideStringsArePreserved() throws {
        let value = try parse(#"{"url": "http://example.com/*x*/ // y", "c": "/* not a comment */"}"#)
        XCTAssertEqual(value.objectValue?["url"], .string("http://example.com/*x*/ // y"))
        XCTAssertEqual(value.objectValue?["c"], .string("/* not a comment */"))
    }

    func testTrailingCommas() throws {
        XCTAssertEqual(try parse("[1, 2,]"), .array([.int(1), .int(2)]))
        XCTAssertEqual(try parse(#"{"a": 1,}"#).objectValue?["a"], .int(1))
        XCTAssertEqual(try parse("[\n 1, // c\n]"), .array([.int(1)]))
        XCTAssertThrowsError(try parse("[,]"))
        XCTAssertThrowsError(try parse("[1,,2]"))
        XCTAssertThrowsError(try parse(#"{,}"#))
    }

    func testStringEscapes() throws {
        XCTAssertEqual(try parse(#""a\"b\\c\/d\b\f\n\r\t""#), .string("a\"b\\c/d\u{08}\u{0C}\n\r\t"))
        XCTAssertEqual(try parse(#""éA""#), .string("éA"))
        XCTAssertEqual(try parse(#""😀""#), .string("😀"))
        XCTAssertEqual(try parse(#""\u0000""#), .string("\u{0}"))
    }

    func testInvalidEscapes() {
        for text in [#""\x""#, #""\u12""#, #""\uZZZZ""#, #""\uD83D""#, #""\uD83Dx""#, #""\uDE00""#, #""\uD83DA""#] {
            XCTAssertThrowsError(try parse(text), text) { error in
                guard case .invalidEscape? = error as? JSONParseError else {
                    return XCTFail("\(text): \(error)")
                }
            }
        }
    }

    func testUnicodeAndBOM() throws {
        XCTAssertEqual(try parse("\u{FEFF}[\"☕️ ü 日本\"]"), .array([.string("☕️ ü 日本")]))
    }

    func testRawControlCharacterInStringIsRejected() {
        XCTAssertThrowsError(try parse("\"a\nb\""))
    }

    func testErrorPositions() {
        XCTAssertThrowsError(try parse("[1,\n  2,\n  x]")) { error in
            XCTAssertEqual(error as? JSONParseError, .unexpectedCharacter("x", line: 3, column: 3))
        }
        XCTAssertThrowsError(try parse("{\"a\": 1} extra")) { error in
            XCTAssertEqual(error as? JSONParseError, .unexpectedCharacter("e", line: 1, column: 10))
        }
        // Column counts characters, not bytes.
        XCTAssertThrowsError(try parse("[\"日本\", ?]")) { error in
            XCTAssertEqual(error as? JSONParseError, .unexpectedCharacter("?", line: 1, column: 8))
        }
        XCTAssertThrowsError(try parse("[1, 2")) { XCTAssertEqual($0 as? JSONParseError, .unexpectedEnd) }
        XCTAssertThrowsError(try parse("")) { XCTAssertEqual($0 as? JSONParseError, .unexpectedEnd) }
        XCTAssertThrowsError(try parse("/* open")) { XCTAssertEqual($0 as? JSONParseError, .unexpectedEnd) }
        XCTAssertThrowsError(try parse("[1] / 2"))
        XCTAssertNotNil(JSONParseError.unexpectedEnd.errorDescription)
    }

    func testDeepNestingIsRejectedNotCrashing() {
        XCTAssertThrowsError(try parse(String(repeating: "[", count: 100_000)))
        XCTAssertNoThrow(try parse(String(repeating: "[", count: 500) + String(repeating: "]", count: 500)))
    }

    func testGarbageNeverCrashes() {
        let samples = [
            "", " ", "{", "}", "[", "]", "\"", "\\", "/", "//", "/*", "*/", "{\"a\"", "{\"a\":", "{\"a\":1", "[1,", "tru", "nul", "-",
            "\u{0}", "\u{FEFF}", "{\"a\": \"\\u", "[\"\\uD800", "{1:2}", "[}", "{]", "'x'", "\u{1F600}", "\"\u{1F600}",
        ]
        for sample in samples {
            _ = try? parse(sample)
        }
        let valid = #"{"a": [1, 2.5, "x\n", {"b": null, "c": [true, false]}], "d": "é😀"} // end"#
        // Every prefix and every single-byte mutation of a valid document.
        let bytes = Array(valid.utf8)
        for end in 0 ... bytes.count {
            _ = try? parse(String(decoding: bytes[0 ..< end], as: UTF8.self))
        }
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 2000 {
            var mutated = bytes
            mutated[Int.random(in: 0 ..< mutated.count, using: &generator)] = UInt8.random(in: 0 ... 255, using: &generator)
            _ = try? parse(String(decoding: mutated, as: UTF8.self))
        }
    }

    // MARK: Serializer

    func testPrettyFormatting() throws {
        let value = JSONValue.array([
            .object(JSONObject(pairs: [
                ("type", .string("a")),
                ("n", .int(1)),
                ("list", .array([.int(1), .int(2)])),
                ("empty", .array([])),
                ("obj", .object(JSONObject())),
            ])),
        ])
        let expected = """
        [
          {
            "type": "a",
            "n": 1,
            "list": [
              1,
              2
            ],
            "empty": [],
            "obj": {}
          }
        ]

        """
        XCTAssertEqual(value.serialized(), expected)
        XCTAssertTrue(value.serialized(indent: 4).contains("\n    {\n        \"type\""))
        XCTAssertEqual(JSONValue.array([]).serialized(), "[]\n")
    }

    func testStringEscapingOnlyWhatJSONRequires() {
        let value = JSONValue.string("a\"b\\c/d é 😀 \n\t\u{01}\u{1F}")
        XCTAssertEqual(value.serialized(), "\"a\\\"b\\\\c/d é 😀 \\n\\t\\u0001\\u001F\"\n")
    }

    func testDoublesStayDoubles() throws {
        XCTAssertEqual(JSONValue.double(2.0).serialized(), "2.0\n")
        XCTAssertEqual(JSONValue.int(2).serialized(), "2\n")
        XCTAssertEqual(try parse(JSONValue.double(2.0).serialized()), .double(2.0))
        XCTAssertEqual(JSONValue.double(.infinity).serialized(), "null\n")
        for d in [0.1, 1e20, 1e-7, 5e-324, 1.7976931348623157e308, -0.0, 123456789.123456789] {
            XCTAssertEqual(try parse(JSONValue.double(d).serialized()), .double(d), "\(d)")
        }
    }

    func testKeyOrderSurvivesSerialization() throws {
        let text = #"{"z": 1, "a": 2, "m": 3}"#
        let object = try XCTUnwrap(try parse(JSONValue.object(try XCTUnwrap(try parse(text).objectValue)).serialized()).objectValue)
        XCTAssertEqual(object.keys, ["z", "a", "m"])
    }

    // MARK: Round trip

    private func randomValue(_ rng: inout SystemRandomNumberGenerator, depth: Int) -> JSONValue {
        let pool = ["", "a", "Key", "é", "日本", "😀", "a\"b", "back\\slash", "line\nbreak", "tab\t", "// not comment", "/* x */", "\u{01}", "a/b"]
        func string(_ rng: inout SystemRandomNumberGenerator) -> String { pool.randomElement(using: &rng)! }
        switch Int.random(in: 0 ... (depth > 3 ? 5 : 7), using: &rng) {
        case 0: return .null
        case 1: return .bool(Bool.random(using: &rng))
        case 2: return .int(Int64.random(in: Int64.min ... Int64.max, using: &rng))
        case 3: return .double(Double.random(in: -1e9 ... 1e9, using: &rng))
        case 4: return .double(Double(Int.random(in: -5 ... 5, using: &rng))) // integral doubles
        case 5: return .string(string(&rng))
        case 6: return .array((0 ..< Int.random(in: 0 ... 4, using: &rng)).map { _ in randomValue(&rng, depth: depth + 1) })
        default:
            var object = JSONObject()
            for _ in 0 ..< Int.random(in: 0 ... 4, using: &rng) { object[string(&rng)] = randomValue(&rng, depth: depth + 1) }
            return .object(object)
        }
    }

    func testRoundTripProperty() throws {
        var rng = SystemRandomNumberGenerator()
        for _ in 0 ..< 500 {
            let value = randomValue(&rng, depth: 0)
            for indent in [0, 2, 4] {
                XCTAssertEqual(try parse(value.serialized(indent: indent)), value)
            }
        }
    }

    func testContainsComments() {
        XCTAssertTrue(JSONValue.containsComments("[] // x"))
        XCTAssertTrue(JSONValue.containsComments("[ /* x */ ]"))
        XCTAssertFalse(JSONValue.containsComments(#"["http://a/b", "/* x */", "esc \" // y"]"#))
        XCTAssertFalse(JSONValue.containsComments("[1, 2]"))
        XCTAssertFalse(JSONValue.containsComments(#"["unterminated // "#))
    }

    // MARK: Accessors

    func testAccessors() {
        XCTAssertEqual(JSONValue.int(3).doubleValue, 3)
        XCTAssertEqual(JSONValue.double(3.0).intValue, 3)
        XCTAssertNil(JSONValue.double(3.5).intValue)
        XCTAssertEqual(JSONValue.string("False").boolValue, false)
        XCTAssertNil(JSONValue.string("x").boolValue)
        var object = JSONObject(pairs: [("a", .int(1))])
        object["a"] = .int(2)
        object["b"] = .int(3)
        object["a"] = nil
        XCTAssertEqual(object.keys, ["b"])
    }
}
