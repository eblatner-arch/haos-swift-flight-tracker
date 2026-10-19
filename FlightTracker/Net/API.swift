import Foundation

/// Talks to the Home Assistant add-on (the same API the web app uses). Every answer is also kept on
/// the phone, so with no signal the app opens with the last copy (marked offline).
enum API {
    static let serverKey = "server"

    /// e.g. https://ericsflights.duckdns.org:8090/ (always ends with a slash)
    static var base: URL? {
        guard var s = UserDefaults.standard.string(forKey: serverKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        if !s.hasSuffix("/") { s += "/" }
        return URL(string: s)
    }

    static func url(_ path: String) -> URL? {
        guard let b = base else { return nil }
        return URL(string: path, relativeTo: b)?.absoluteURL
    }

    enum Failure: LocalizedError {
        case noServer, http(Int)
        var errorDescription: String? {
            switch self {
            case .noServer: return "Set your add-on's address in Settings."
            case .http(let c): return "The add-on answered \(c)."
            }
        }
    }

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 200 << 20)   // pictures
        return URLSession(configuration: c)
    }()

    /// GET a JSON path (like "api/state"). -> (value, fromPhone) where fromPhone means the add-on
    /// couldn't be reached and this is the last saved copy.
    static func get(_ path: String, timeout: TimeInterval = 15, keep: Bool = true) async throws -> (JSON, Bool) {
        guard let u = url(path) else { throw Failure.noServer }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw Failure.http(code) }
            let j = try JSON.parse(data)
            if keep { Disk.save(data, for: path) }
            return (j, false)
        } catch {
            if (error as? CancellationError) != nil || (error as? URLError)?.code == .cancelled { throw error }
            if keep, let d = Disk.load(path), let j = try? JSON.parse(d) { return (j, true) }
            throw error
        }
    }
}

/// The phone's copies of the add-on's answers (Library/Caches/api).
enum Disk {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("api", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func file(_ path: String) -> URL {
        let safe = path.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return dir.appendingPathComponent(String(safe) + ".json")
    }

    static func save(_ data: Data, for path: String) {
        try? data.write(to: file(path), options: .atomic)
    }

    static func load(_ path: String) -> Data? {
        try? Data(contentsOf: file(path))
    }
}
