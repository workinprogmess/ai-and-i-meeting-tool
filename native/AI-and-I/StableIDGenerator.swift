import Foundation

enum StableIDGenerator {
    private static let queue = DispatchQueue(label: "com.ai-and-i.id-generator")
    private static var counter: UInt64 = 0

    static func make(prefix: String) -> String {
        return queue.sync {
            counter &+= 1
            let timestamp = UInt64((Date().timeIntervalSince1970 * 1000).rounded())
            return "\(prefix)-\(timestamp)-\(counter)"
        }
    }
}
