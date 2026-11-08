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
    static func parse(_ text: String) throws -> JSONValue {
        fatalError("TODO: implemented by the model agent")
    }

    /// Pretty-printed JSON: `indent` spaces, keys in stored order, `/` not escaped,
    /// non-ASCII characters kept as-is, trailing newline. Output is strict JSON (no comments).
    func serialized(indent: Int = 2) -> String {
        fatalError("TODO: implemented by the model agent")
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
