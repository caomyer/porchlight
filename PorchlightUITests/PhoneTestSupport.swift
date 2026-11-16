import XCTest

extension XCUIElement {
    /// Waits for an element in a sheet that is still sliding up to come to rest: a tap
    /// computed mid-slide can land outside the sheet and close it.
    func waitToSettle() {
        var last = frame
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.15)
            let now = frame
            if now == last && isHittable { return }
            last = now
        }
    }
}
