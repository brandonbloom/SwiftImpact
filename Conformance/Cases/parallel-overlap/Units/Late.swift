import Foundation

func late() -> String {
    Thread.sleep(forTimeInterval: 0.05)
    return "late"
}
