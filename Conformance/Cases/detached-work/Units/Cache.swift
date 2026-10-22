import Foundation

final class Cache: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = ""

    var value: String {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

let cache = Cache()
