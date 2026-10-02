import XCTest
@testable import StreamLogic

@MainActor
final class FavoritesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "FavoritesStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func stream(_ n: Int) -> IPTVStream {
        IPTVStream(name: "S\(n)", url: URL(string: "https://e.test/\(n).m3u8")!,
                   channelID: nil, categories: [], country: nil, logoURL: nil)
    }

    func testToggleAddsThenRemovesAndKeepsOrder() {
        let store = FavoritesStore(defaults: defaults)
        store.toggle(stream(1))
        store.toggle(stream(2))
        XCTAssertEqual(store.streams.map(\.name), ["S1", "S2"])
        XCTAssertTrue(store.contains(stream(1)))
        store.toggle(stream(1))
        XCTAssertFalse(store.contains(stream(1)))
        XCTAssertEqual(store.streams.map(\.name), ["S2"])
    }

    func testPersistsAcrossInstances() {
        FavoritesStore(defaults: defaults).toggle(stream(7))
        XCTAssertEqual(FavoritesStore(defaults: defaults).streams.map(\.name), ["S7"])
    }

    func testCorruptStoredDataYieldsEmptyFavorites() {
        defaults.set(Data("not json".utf8), forKey: "favoriteStreams")
        XCTAssertEqual(FavoritesStore(defaults: defaults).streams, [])
    }
}
