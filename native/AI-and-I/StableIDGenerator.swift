import Foundation

enum StableIDGenerator {
    private static let lock = NSLock()
    private static var counter: UInt64 = 0

    static func make(prefix: String) -> String {
        print("🆔 generator: waiting for lock (prefix: ", prefix, ") thread: ", Thread.isMainThread ? "main" : "background", separator: "")
        lock.lock()
        print("🆔 generator: acquired lock (thread: ", Thread.isMainThread ? "main" : "background", ")")
        let next = counter &+ 1
        counter = next
        lock.unlock()
        let timestamp = UInt64((Date().timeIntervalSince1970 * 1000).rounded())
        let id = "\(prefix)-\(timestamp)-\(next)"
        print("🆔 generator: produced \(id)")
        return id
    }
}
