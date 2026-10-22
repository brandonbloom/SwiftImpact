import Foundation

final class Box: @unchecked Sendable {
    var value = ""
}

func computeOnAnotherThread() -> String {
    let box = Box()
    let done = DispatchSemaphore(value: 0)
    let thread = Thread {
        box.value = compute()
        done.signal()
    }
    thread.start()
    done.wait()
    return box.value
}
