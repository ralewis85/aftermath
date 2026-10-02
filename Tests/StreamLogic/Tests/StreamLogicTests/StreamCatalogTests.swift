import XCTest
@testable import StreamLogic

@MainActor
final class StreamCatalogTests: XCTestCase {
    private let fixture = """
    #EXTM3U
    #EXTINF:-1 tvg-id="A.us" group-title="News",Alpha
    https://e.test/a.m3u8
    #EXTINF:-1 tvg-id="B.uk" group-title="Kids",Beta
    https://e.test/b.m3u8
    """

    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        cacheURL = FileManager.default.temporaryDirectory
            .appending(path: "catalog-test-\(UUID().uuidString).m3u")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheURL)
        super.tearDown()
    }

    private struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }

    func testLoadPopulatesStreamsFiltersAndCache() async throws {
        let text = fixture
        let catalog = StreamCatalog(cacheURL: cacheURL, fetch: { text })
        await catalog.load()
        XCTAssertEqual(catalog.state, .loaded)
        XCTAssertEqual(catalog.streams.count, 2)
        XCTAssertEqual(catalog.categories, ["Kids", "News"])
        XCTAssertEqual(catalog.countries, ["UK", "US"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))

        catalog.query = "alp"
        XCTAssertEqual(catalog.filtered.map(\.name), ["Alpha"])
        catalog.query = ""
        catalog.country = "UK"
        XCTAssertEqual(catalog.filtered.map(\.name), ["Beta"])
    }

    func testFailureWithNoCacheIsFailedState() async {
        let catalog = StreamCatalog(cacheURL: cacheURL, fetch: { throw Boom() })
        await catalog.load()
        XCTAssertEqual(catalog.state, .failed("boom"))
        XCTAssertTrue(catalog.streams.isEmpty)
    }

    func testFailureFallsBackToCachedCopy() async throws {
        try fixture.write(to: cacheURL, atomically: true, encoding: .utf8)
        let catalog = StreamCatalog(cacheURL: cacheURL, fetch: { throw Boom() })
        await catalog.load()
        XCTAssertEqual(catalog.state, .loaded)
        XCTAssertEqual(catalog.streams.count, 2)
    }

    func testCorruptCacheAndFailedFetchIsFailedNotCrash() async throws {
        try "<html>garbage</html>".write(to: cacheURL, atomically: true, encoding: .utf8)
        let catalog = StreamCatalog(cacheURL: cacheURL, fetch: { throw Boom() })
        await catalog.load()
        XCTAssertEqual(catalog.state, .failed("boom"))
    }

    func testEmptyPlaylistFromServerIsTreatedAsFailure() async {
        let catalog = StreamCatalog(cacheURL: cacheURL, fetch: { "#EXTM3U\n" })
        await catalog.load()
        if case .failed = catalog.state {} else { XCTFail("expected failed, got \(catalog.state)") }
    }

    func testCancellingTheCallerDoesNotAbortTheDownload() async {
        let text = fixture
        let counter = Counter()
        let catalog = StreamCatalog(cacheURL: cacheURL, fetch: {
            _ = await counter.next()
            try await Task.sleep(nanoseconds: 200_000_000)
            return text
        })
        let first = Task { await catalog.load() }
        try? await Task.sleep(nanoseconds: 30_000_000)
        first.cancel()
        await first.value

        XCTAssertEqual(catalog.state, .loaded, "dismissing the sheet must not fail the download")
        XCTAssertEqual(catalog.streams.count, 2)
        let fetches = await counter.next() - 1
        XCTAssertEqual(fetches, 1)
    }

    func testFailedRefreshKeepsExistingStreams() async {
        let text = fixture
        let counter = Counter()
        let catalog = StreamCatalog(cacheURL: cacheURL, fetch: {
            if await counter.next() == 1 { return text }
            throw Boom()
        })
        await catalog.load()
        XCTAssertEqual(catalog.streams.count, 2)
        await catalog.load()
        XCTAssertEqual(catalog.state, .loaded)
        XCTAssertEqual(catalog.streams.count, 2)
    }
}

private actor Counter {
    private var value = 0
    func next() -> Int { value += 1; return value }
}
