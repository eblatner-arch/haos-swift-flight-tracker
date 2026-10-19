import Foundation

/// Any JSON value. The add-on's API grows new fields often; reading it loosely means a new or
/// missing field never breaks the app.
enum JSON: Decodable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSON].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSON].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    static func parse(_ data: Data) throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: data)
    }

    subscript(key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    subscript(index: Int) -> JSON {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    var string: String? {
        switch self {
        case .string(let s): return s.isEmpty ? nil : s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        default: return nil
        }
    }

    var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    var int: Int? {
        guard let d = double, d.isFinite else { return nil }
        return Int(d)
    }

    var bool: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        default: return false
        }
    }

    var array: [JSON] {
        if case .array(let a) = self { return a }
        return []
    }

    var object: [String: JSON] {
        if case .object(let o) = self { return o }
        return [:]
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// A Unix time in the API as a Date.
    var date: Date? {
        guard let d = double, d > 0 else { return nil }
        return Date(timeIntervalSince1970: d)
    }

    /// Back to a plain value tree, for writing changes into a copy.
    mutating func set(_ key: String, _ value: JSON) {
        if case .object(var o) = self {
            o[key] = value
            self = .object(o)
        }
    }
}
