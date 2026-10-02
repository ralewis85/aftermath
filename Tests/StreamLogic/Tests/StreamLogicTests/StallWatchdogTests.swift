import XCTest
@testable import StreamLogic

@MainActor
final class StallWatchdogTests: XCTestCase {
    func testFiresOnceAfterTimeout() async {
        let watchdog = StallWatchdog()
        var fired = 0
        watchdog.arm(after: 0.05) { fired += 1 }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(fired, 1)
    }

    func testDisarmPreventsFiring() async {
        let watchdog = StallWatchdog()
        var fired = 0
        watchdog.arm(after: 0.05) { fired += 1 }
        watchdog.disarm()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(fired, 0)
    }

    func testRearmingReplacesThePreviousTimer() async {
        let watchdog = StallWatchdog()
        var first = 0
        var second = 0
        watchdog.arm(after: 0.05) { first += 1 }
        watchdog.arm(after: 0.05) { second += 1 }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
    }
}
