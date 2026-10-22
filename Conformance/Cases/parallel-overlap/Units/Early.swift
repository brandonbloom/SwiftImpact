import Foundation

func early() -> String {
    let value = earlyValue()
    Thread.sleep(forTimeInterval: 0.2)
    return value
}
