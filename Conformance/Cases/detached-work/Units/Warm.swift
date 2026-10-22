import Foundation

func warm() -> String {
    Thread.detachNewThread {
        Thread.sleep(forTimeInterval: 0.05)
        cache.value = warmValue()
    }
    return "warming"
}
