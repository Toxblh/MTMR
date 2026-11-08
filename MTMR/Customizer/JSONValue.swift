//
//  JSONValue.swift
//  MTMR
//
//  Lossless, order-preserving JSON model for the Touch Bar customizer.
//
//  Why not BarItemDefinition: it is Decodable only, holds closures and drops unknown keys,
//  so a decode/encode round trip would lose user data. The customizer edits this tree
//  instead and validates the result with the app's real decoder before saving.
//

import Foundation

enum JSONValue: Equatable {
    case null
    case bool(Bool)
    /// Integers are kept apart from doubles so `"keycode": 53` is not written back as `53.0`.
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)
}

/// A JSON object that keeps its key order, so a preset saved by the UI diffs cleanly
/// against the hand-edited original.
struct JSONObject: Equatable {
    struct Entry: Equatable {
        var key: String
        var value: JSONValue
    }

    private(set) var entries: [Entry] = []

    init(_ entries: [Entry] = []) {
        self.entries = entries
    }

    /// Convenience for literals in code: keys keep the given order.
    init(pairs: [(String, JSONValue)]) {
        entries = pairs.map { Entry(key: $0.0, value: $0.1) }
    }

    var keys: [String] { entries.map(\.key) }

    /// Setting an existing key replaces its value in place; a new key is appended;
    /// setting `nil` removes the key.
    subscript(key: String) -> JSONValue? {
        get { entries.first(where: { $0.key == key })?.value }
        set {
            if let index = entries.firstIndex(where: { $0.key == key }) {
                if let newValue = newValue {
                    entries[index].value = newValue
                } else {
                    entries.remove(at: index)
                }
            } else if let newValue = newValue {
                entries.append(Entry(key: key, value: newValue))
            }
        }
    }
}

enum JSONParseError: Error, Equatable, LocalizedError {
    case unexpectedCharacter(Character, line: Int, column: Int)
    case unexpectedEnd
    case invalidNumber(String, line: Int, column: Int)
    case invalidEscape(line: Int, column: Int)

    var errorDescription: String? {
        switch self {
        case let .unexpectedCharacter(c, line, column): return "Unexpected “\(c)” at line \(line), column \(column)."
        case .unexpectedEnd: return "The file ends unexpectedly."
        case let .invalidNumber(text, line, column): return "Invalid number “\(text)” at line \(line), column \(column)."
        case let .invalidEscape(line, column): return "Invalid escape sequence at line \(line), column \(column)."
        }
    }
}

extension JSONValue {
    /// Parses strict JSON plus what MTMR presets contain in the wild:
    /// `//` line comments, `/* */` block comments and trailing commas in arrays/objects.
    ///
    /// - Numbers without `.`/exponent that fit into Int64 become `.int`, everything else `.double`.
    /// - Duplicate object keys: the last value wins and keeps the position of the first occurrence.
    /// - Raw control characters inside strings are rejected (as the app's own JSON decoder does).
    /// - Nesting deeper than 512 levels is rejected instead of overflowing the stack.
    /// - A leading byte order mark is ignored.
    static func parse(_ text: String) throws -> JSONValue {
        var parser = JSONParser(bytes: Array(text.utf8))
        return try parser.parseDocument()
    }

    /// Pretty-printed JSON: `indent` spaces, keys in stored order, `/` not escaped,
    /// non-ASCII characters kept as-is, trailing newline. Output is strict JSON (no comments).
    /// `.double` values always contain a `.` or exponent so they stay doubles when re-parsed;
    /// non-finite doubles (not representable in JSON) are written as `null`.
    func serialized(indent: Int = 2) -> String {
        var out = ""
        write(to: &out, indent: max(0, indent), level: 0)
        out.append("\n")
        return out
    }

    /// True when `text` contains a `//` or `/* */` comment outside of string literals.
    /// A purely lexical scan: it also works on files that do not parse.
    static func containsComments(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        var i = 0
        var inString = false
        while i < bytes.count {
            let b = bytes[i]
            if inString {
                if b == UInt8(ascii: "\\") { i += 1 } else if b == UInt8(ascii: "\"") { inString = false }
            } else if b == UInt8(ascii: "\"") {
                inString = true
            } else if b == UInt8(ascii: "/"), i + 1 < bytes.count,
                      bytes[i + 1] == UInt8(ascii: "/") || bytes[i + 1] == UInt8(ascii: "*") {
                return true
            }
            i += 1
        }
        return false
    }

    private func write(to out: inout String, indent: Int, level: Int) {
        switch self {
        case .null: out.append("null")
        case let .bool(b): out.append(b ? "true" : "false")
        case let .int(i): out.append(String(i))
        case let .double(d):
            if d.isFinite {
                // Swift's description is the shortest round-tripping form and always has "." or "e".
                out.append(d.description)
            } else {
                out.append("null")
            }
        case let .string(s): JSONValue.writeString(s, to: &out)
        case let .array(items):
            if items.isEmpty { out.append("[]"); return }
            out.append("[\n")
            for (n, item) in items.enumerated() {
                out.append(String(repeating: " ", count: indent * (level + 1)))
                item.write(to: &out, indent: indent, level: level + 1)
                out.append(n == items.count - 1 ? "\n" : ",\n")
            }
            out.append(String(repeating: " ", count: indent * level))
            out.append("]")
        case let .object(object):
            if object.entries.isEmpty { out.append("{}"); return }
            out.append("{\n")
            for (n, entry) in object.entries.enumerated() {
                out.append(String(repeating: " ", count: indent * (level + 1)))
                JSONValue.writeString(entry.key, to: &out)
                out.append(": ")
                entry.value.write(to: &out, indent: indent, level: level + 1)
                out.append(n == object.entries.count - 1 ? "\n" : ",\n")
            }
            out.append(String(repeating: " ", count: indent * level))
            out.append("}")
        }
    }

    /// Escapes only what JSON requires: `"`, `\` and control characters below U+0020.
    private static func writeString(_ s: String, to out: inout String) {
        out.append("\"")
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            case "\u{08}": out.append("\\b")
            case "\u{0C}": out.append("\\f")
            default:
                if scalar.value < 0x20 {
                    out.append("\\u" + String(format: "%04X", scalar.value))
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out.append("\"")
    }

    // MARK: Convenience accessors (lenient where presets are lenient)

    var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    /// `.int` and `.double` both convert.
    var doubleValue: Double? {
        switch self {
        case let .int(i): return Double(i)
        case let .double(d): return d
        default: return nil
        }
    }

    /// `.int`, or `.double` without fractional part.
    var intValue: Int? {
        switch self {
        case let .int(i): return Int(i)
        case let .double(d) where d.rounded() == d: return Int(d)
        default: return nil
        }
    }

    /// Accepts `true`/`false` and the strings `"true"`/`"false"` (the README documents `"bordered": "false"`).
    var boolValue: Bool? {
        switch self {
        case let .bool(b): return b
        case let .string(s) where s.lowercased() == "true": return true
        case let .string(s) where s.lowercased() == "false": return false
        default: return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case let .array(a) = self { return a }
        return nil
    }

    var objectValue: JSONObject? {
        if case let .object(o) = self { return o }
        return nil
    }
}

// MARK: - Parser

/// Recursive-descent parser over UTF-8 bytes. Positions are reported as 1-based line/column
/// (column counts characters, not bytes) and computed only when an error is thrown.
private struct JSONParser {
    let bytes: [UInt8]
    var pos = 0
    var depth = 0
    static let maxDepth = 512

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func parseDocument() throws -> JSONValue {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { pos = 3 }
        try skipTrivia()
        let value = try parseValue()
        try skipTrivia()
        if pos < bytes.count { throw unexpected(at: pos) }
        return value
    }

    // MARK: Errors

    func position(of offset: Int) -> (line: Int, column: Int) {
        var line = 1, column = 1
        var i = 0
        while i < offset && i < bytes.count {
            if bytes[i] == 0x0A {
                line += 1; column = 1
            } else if bytes[i] & 0xC0 != 0x80 { // count characters, skip UTF-8 continuation bytes
                column += 1
            }
            i += 1
        }
        return (line, column)
    }

    func unexpected(at offset: Int) -> JSONParseError {
        guard offset < bytes.count else { return .unexpectedEnd }
        var end = offset + 1
        while end < bytes.count, bytes[end] & 0xC0 == 0x80 { end += 1 }
        let char = String(decoding: bytes[offset ..< end], as: UTF8.self).first ?? "?"
        let p = position(of: offset)
        return .unexpectedCharacter(char, line: p.line, column: p.column)
    }

    // MARK: Whitespace and comments

    mutating func skipTrivia() throws {
        while pos < bytes.count {
            switch bytes[pos] {
            case 0x20, 0x09, 0x0A, 0x0D:
                pos += 1
            case UInt8(ascii: "/"):
                guard pos + 1 < bytes.count else { throw JSONParseError.unexpectedEnd }
                if bytes[pos + 1] == UInt8(ascii: "/") {
                    pos += 2
                    while pos < bytes.count, bytes[pos] != 0x0A { pos += 1 }
                } else if bytes[pos + 1] == UInt8(ascii: "*") {
                    pos += 2
                    var closed = false
                    while pos + 1 < bytes.count {
                        if bytes[pos] == UInt8(ascii: "*"), bytes[pos + 1] == UInt8(ascii: "/") {
                            pos += 2; closed = true; break
                        }
                        pos += 1
                    }
                    if !closed { pos = bytes.count; throw JSONParseError.unexpectedEnd }
                } else {
                    throw unexpected(at: pos)
                }
            default:
                return
            }
        }
    }

    // MARK: Values

    mutating func parseValue() throws -> JSONValue {
        guard pos < bytes.count else { throw JSONParseError.unexpectedEnd }
        switch bytes[pos] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0") ... UInt8(ascii: "9"): return try parseNumber()
        default: throw unexpected(at: pos)
        }
    }

    mutating func expect(_ word: String) throws {
        for expected in word.utf8 {
            guard pos < bytes.count else { throw JSONParseError.unexpectedEnd }
            guard bytes[pos] == expected else { throw unexpected(at: pos) }
            pos += 1
        }
    }

    mutating func enter() throws {
        depth += 1
        if depth > JSONParser.maxDepth { throw unexpected(at: pos) }
    }

    mutating func parseArray() throws -> JSONValue {
        try enter()
        defer { depth -= 1 }
        pos += 1 // [
        var items: [JSONValue] = []
        try skipTrivia()
        while true {
            guard pos < bytes.count else { throw JSONParseError.unexpectedEnd }
            if bytes[pos] == UInt8(ascii: "]") { pos += 1; return .array(items) }
            items.append(try parseValue())
            try skipTrivia()
            guard pos < bytes.count else { throw JSONParseError.unexpectedEnd }
            if bytes[pos] == UInt8(ascii: ",") {
                pos += 1
                try skipTrivia()
            } else if bytes[pos] != UInt8(ascii: "]") {
                throw unexpected(at: pos)
            }
        }
    }

    mutating func parseObject() throws -> JSONValue {
        try enter()
        defer { depth -= 1 }
        pos += 1 // {
        var object = JSONObject()
        try skipTrivia()
        while true {
            guard pos < bytes.count else { throw JSONParseError.unexpectedEnd }
            if bytes[pos] == UInt8(ascii: "}") { pos += 1; return .object(object) }
            guard bytes[pos] == UInt8(ascii: "\"") else { throw unexpected(at: pos) }
            let key = try parseString()
            try skipTrivia()
            guard pos < bytes.count else { throw JSONParseError.unexpectedEnd }
            guard bytes[pos] == UInt8(ascii: ":") else { throw unexpected(at: pos) }
            pos += 1
            try skipTrivia()
            object[key] = try parseValue() // duplicate key: last wins
            try skipTrivia()
            guard pos < bytes.count else { throw JSONParseError.unexpectedEnd }
            if bytes[pos] == UInt8(ascii: ",") {
                pos += 1
                try skipTrivia()
            } else if bytes[pos] != UInt8(ascii: "}") {
                throw unexpected(at: pos)
            }
        }
    }

    // MARK: Numbers

    mutating func parseNumber() throws -> JSONValue {
        let start = pos
        var isInteger = true
        func digits(_ p: inout JSONParser) -> Int {
            var n = 0
            while p.pos < p.bytes.count, (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(p.bytes[p.pos]) { p.pos += 1; n += 1 }
            return n
        }
        if bytes[pos] == UInt8(ascii: "-") { pos += 1 }
        let intStart = pos
        let intDigits = digits(&self)
        var valid = intDigits > 0 && !(intDigits > 1 && bytes[intStart] == UInt8(ascii: "0"))
        if valid, pos < bytes.count, bytes[pos] == UInt8(ascii: ".") {
            isInteger = false
            pos += 1
            valid = digits(&self) > 0
        }
        if valid, pos < bytes.count, bytes[pos] == UInt8(ascii: "e") || bytes[pos] == UInt8(ascii: "E") {
            isInteger = false
            pos += 1
            if pos < bytes.count, bytes[pos] == UInt8(ascii: "+") || bytes[pos] == UInt8(ascii: "-") { pos += 1 }
            valid = digits(&self) > 0
        }
        let text = String(decoding: bytes[start ..< pos], as: UTF8.self)
        func invalid() -> JSONParseError {
            let p = position(of: start)
            return .invalidNumber(text, line: p.line, column: p.column)
        }
        guard valid else { throw invalid() }
        if isInteger, let i = Int64(text) { return .int(i) }
        guard let d = Double(text), d.isFinite else { throw invalid() }
        return .double(d)
    }

    // MARK: Strings

    mutating func parseString() throws -> String {
        pos += 1 // opening quote
        var buffer: [UInt8] = []
        while true {
            guard pos < bytes.count else { throw JSONParseError.unexpectedEnd }
            let b = bytes[pos]
            switch b {
            case UInt8(ascii: "\""):
                pos += 1
                return String(decoding: buffer, as: UTF8.self)
            case UInt8(ascii: "\\"):
                try parseEscape(into: &buffer)
            case 0 ..< 0x20:
                throw unexpected(at: pos)
            default:
                buffer.append(b)
                pos += 1
            }
        }
    }

    mutating func parseEscape(into buffer: inout [UInt8]) throws {
        let escapeStart = pos
        func invalid() -> JSONParseError {
            let p = position(of: escapeStart)
            return .invalidEscape(line: p.line, column: p.column)
        }
        pos += 1 // backslash
        guard pos < bytes.count else { throw JSONParseError.unexpectedEnd }
        let c = bytes[pos]
        pos += 1
        switch c {
        case UInt8(ascii: "\""): buffer.append(c)
        case UInt8(ascii: "\\"): buffer.append(c)
        case UInt8(ascii: "/"): buffer.append(c)
        case UInt8(ascii: "b"): buffer.append(0x08)
        case UInt8(ascii: "f"): buffer.append(0x0C)
        case UInt8(ascii: "n"): buffer.append(0x0A)
        case UInt8(ascii: "r"): buffer.append(0x0D)
        case UInt8(ascii: "t"): buffer.append(0x09)
        case UInt8(ascii: "u"):
            guard let first = hex4() else { throw invalid() }
            var value = first
            if (0xD800 ... 0xDBFF).contains(first) {
                // High surrogate: must be followed by \uDC00-\uDFFF.
                guard pos + 1 < bytes.count, bytes[pos] == UInt8(ascii: "\\"), bytes[pos + 1] == UInt8(ascii: "u") else { throw invalid() }
                pos += 2
                guard let second = hex4(), (0xDC00 ... 0xDFFF).contains(second) else { throw invalid() }
                value = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
            } else if (0xDC00 ... 0xDFFF).contains(first) {
                throw invalid()
            }
            guard let scalar = Unicode.Scalar(value) else { throw invalid() }
            buffer.append(contentsOf: Array(String(Character(scalar)).utf8))
        default:
            pos -= 1
            throw invalid()
        }
    }

    mutating func hex4() -> UInt32? {
        guard pos + 4 <= bytes.count else { pos = bytes.count; return nil }
        var value: UInt32 = 0
        for _ in 0 ..< 4 {
            guard let digit = Character(Unicode.Scalar(bytes[pos])).hexDigitValue else { return nil }
            value = value << 4 | UInt32(digit)
            pos += 1
        }
        return value
    }
}
