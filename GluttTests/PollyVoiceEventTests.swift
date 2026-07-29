import XCTest
@testable import Glutt

final class PollyVoiceEventTests: XCTestCase {
    func testStructuredEventAppearsInDump() {
        let log = PollyDebugLog(clock: { Date(timeIntervalSince1970: 1_000) })
        log.reset()
        log.event(.followUpRejected, ["reason": "uncertain", "n": "1"])
        let dump = log.dump()
        XCTAssertTrue(dump.contains("evt=followup.rejected"))
        XCTAssertTrue(dump.contains("reason=uncertain"))
        XCTAssertTrue(dump.contains("n=1"))
    }
}
