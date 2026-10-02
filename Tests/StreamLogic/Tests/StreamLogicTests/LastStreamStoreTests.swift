import XCTest
@testable import StreamLogic

final class LastStreamStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "LastStreamStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private let stream = IPTVStream(
        name: "Chan", url: URL(string: "https://e.test/c.m3u8")!,
        channelID: "C.us", categories: ["News"], country: "US", logoURL: nil
    )

    func testNothingSavedLoadsNil() {
        XCTAssertNil(LastStreamStore(defaults: defaults).load())
    }

    func testSaveThenLoadRoundTrips() {
        LastStreamStore(defaults: defaults).save(stream)
        XCTAssertEqual(LastStreamStore(defaults: defaults).load(), stream)
    }

    func testCorruptDataLoadsNil() {
        defaults.set(Data("nope".utf8), forKey: "lastStream")
        XCTAssertNil(LastStreamStore(defaults: defaults).load())
    }
}
