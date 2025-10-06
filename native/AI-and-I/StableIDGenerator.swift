import Foundation

enum StableIDGenerator {
    private static let lock = NSLock()
    private static var counter: UInt64 = 0

    static func make(prefix: String) -> String {
        lock.lock()
        let next = counter &+ 1
        counter = next
        lock.unlock()
        let timestamp = UInt64((Date().timeIntervalSince1970 * 1000).rounded())
        return "\(prefix)-\(timestamp)-\(next)"
    }
}
