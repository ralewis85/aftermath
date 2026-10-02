# iptv-org Stream Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual EST/PST URL fields with a searchable, filterable browser over the public iptv-org playlist, with favorites shown in the ornament, and remove explicit Toonami references.

**Architecture:** All non-UI logic (model, M3U parser, filter, favorites, catalog) lives in `aftermath/Streams/` and imports only Foundation and Observation. A small SwiftPM package under `Tests/StreamLogic` symlinks that folder so `swift test` verifies the logic with Command Line Tools alone. SwiftUI views live in `aftermath/Views/`, and `ContentView` is reworked to use them.

**Tech Stack:** Swift 5, SwiftUI, AVKit, Observation (`@Observable`), XCTest via SwiftPM, visionOS 26.1 target.

**Spec:** `docs/superpowers/specs/2026-10-01-iptv-org-streams-design.md`

## Global Constraints

- Playlist source is exactly `https://iptv-org.github.io/iptv/index.m3u`, fetched at runtime. Nothing is bundled.
- App name, bundle name (`neovision.aftermath`), and project and file names containing "aftermath" stay unchanged.
- Keep the 4:3 window, `.uniform` resizing restriction, volume slider and mute button, ornament auto-hide, and tap to play/pause unchanged.
- The Xcode project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Every type in `aftermath/Streams/` that must be usable off the main actor is explicitly marked `nonisolated`.
- No new third-party dependencies.
- Remove the old `estURL`/`pstURL` storage without migration. Manual URL entry is gone.
- No Toonami wording anywhere in the repo after the change, including `.claude/settings.local.json`.

## Deviations from the spec (decided while planning)

- The model type is `IPTVStream`, not `Stream`, because `Foundation.Stream` already exists.
- `id` is the stream URL string, not `tvg-id`. iptv-org lists several feeds under one `tvg-id`, so `tvg-id` is kept as `channelID` and is not unique.
- `category: String?` becomes `categories: [String]`, because iptv-org's `group-title` can hold several values joined by `;`.
- Choosing a stream starts playback immediately. Previously nothing played until the user tapped the video.

## Review Focus

Each line has its test in the task that owns the code.

1. A `group-title` or other quoted attribute containing a comma must not truncate the channel name. (Task 1)
2. Multiple feeds sharing one `tvg-id` must still get distinct `id`s, or the list and favorites collide. (Task 1)
3. Non-http(s) URLs (e.g. `rtmp://`) must be skipped, since AVPlayer cannot play them. (Task 1)
4. Corrupt favorites data or a corrupt or missing cache must give an empty or fallback state, never a crash. (Tasks 2, 3)
5. A refresh that fails after a successful load must keep the existing list instead of replacing it with an error. (Task 3)
6. Search must match without regard to case or diacritics, and an empty or whitespace query must return everything. (Task 2)

## File Structure

| File | Responsibility |
|---|---|
| `aftermath/Streams/IPTVStream.swift` | Value type for one stream |
| `aftermath/Streams/PlaylistParser.swift` | M3U text to `[IPTVStream]` |
| `aftermath/Streams/StreamFilter.swift` | Pure search, category and country filtering |
| `aftermath/Streams/FavoritesStore.swift` | Persisted ordered favorites |
| `aftermath/Streams/StreamCatalog.swift` | Fetch, cache, parse, expose filtered list and load state |
| `aftermath/Views/StreamArtwork.swift` | Logo or initials circle |
| `aftermath/Views/StreamBrowserView.swift` | Browse sheet (search, filters, list, star toggle) |
| `aftermath/ContentView.swift` | Player, ornament with favorites, browse button, failure overlay |
| `Tests/StreamLogic/` | SwiftPM harness; `Sources/StreamLogic` is a symlink to `aftermath/Streams` |

---

### Task 1: Test harness, model, and parser

**Files:**
- Create: `Tests/StreamLogic/Package.swift`
- Create: symlink `Tests/StreamLogic/Sources/StreamLogic` -> `../../../aftermath/Streams`
- Create: `aftermath/Streams/IPTVStream.swift`
- Create: `aftermath/Streams/PlaylistParser.swift`
- Create: `Tests/StreamLogic/Tests/StreamLogicTests/PlaylistParserTests.swift`
- Modify: `.gitignore` (ensure `.build/` is ignored)

**Interfaces:**
- Produces:
  - `nonisolated struct IPTVStream: Codable, Identifiable, Hashable, Sendable` with `var id: String` (the URL string), `let name: String`, `let url: URL`, `let channelID: String?`, `let categories: [String]`, `let country: String?` (uppercase 2-letter code), `let logoURL: URL?`, and a memberwise init in that order.
  - `nonisolated enum PlaylistParser { static func parse(_ text: String) -> [IPTVStream] }`

- [ ] **Step 1: Create a branch and the harness**

```bash
cd /Users/rlewis/repos/personal/aftermath
git checkout -b iptv-streams
mkdir -p aftermath/Streams Tests/StreamLogic/Sources Tests/StreamLogic/Tests/StreamLogicTests
ln -s ../../../aftermath/Streams Tests/StreamLogic/Sources/StreamLogic
grep -qE '^\.build/?$' .gitignore || printf '\n.build/\n' >> .gitignore
```

Create `Tests/StreamLogic/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StreamLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StreamLogic", path: "Sources/StreamLogic"),
        .testTarget(
            name: "StreamLogicTests",
            dependencies: ["StreamLogic"],
            path: "Tests/StreamLogicTests"
        ),
    ]
)
```

- [ ] **Step 2: Write the failing parser tests**

Create `Tests/StreamLogic/Tests/StreamLogicTests/PlaylistParserTests.swift`:

```swift
import XCTest
@testable import StreamLogic

final class PlaylistParserTests: XCTestCase {
    func testParsesBasicEntry() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-id="BBCOne.uk@SD" tvg-logo="https://x.test/logo.png" group-title="General;News",BBC One (576p)
        https://example.com/bbc.m3u8
        """
        let streams = PlaylistParser.parse(m3u)
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].name, "BBC One (576p)")
        XCTAssertEqual(streams[0].url.absoluteString, "https://example.com/bbc.m3u8")
        XCTAssertEqual(streams[0].id, "https://example.com/bbc.m3u8")
        XCTAssertEqual(streams[0].channelID, "BBCOne.uk@SD")
        XCTAssertEqual(streams[0].categories, ["General", "News"])
        XCTAssertEqual(streams[0].country, "UK")
        XCTAssertEqual(streams[0].logoURL?.absoluteString, "https://x.test/logo.png")
    }

    func testCommaInsideQuotedAttributeDoesNotTruncateName() {
        let m3u = """
        #EXTINF:-1 tvg-id="A.us" group-title="News, Weather",Channel A
        https://example.com/a.m3u8
        """
        let streams = PlaylistParser.parse(m3u)
        XCTAssertEqual(streams.first?.name, "Channel A")
        XCTAssertEqual(streams.first?.categories, ["News, Weather"])
    }

    func testDuplicateChannelIDsGetDistinctStreamIDs() {
        let m3u = """
        #EXTINF:-1 tvg-id="Same.us@SD",Same (480p)
        https://example.com/one.m3u8
        #EXTINF:-1 tvg-id="Same.us@SD",Same (720p)
        https://example.com/two.m3u8
        """
        let streams = PlaylistParser.parse(m3u)
        XCTAssertEqual(streams.count, 2)
        XCTAssertEqual(Set(streams.map(\.id)).count, 2)
    }

    func testSkipsNonHTTPSchemes() {
        let m3u = """
        #EXTINF:-1,Radio
        rtmp://example.com/live
        #EXTINF:-1,Good
        http://example.com/good.m3u8
        """
        let streams = PlaylistParser.parse(m3u)
        XCTAssertEqual(streams.map(\.name), ["Good"])
    }

    func testSkipsEntryWithoutURL() {
        let m3u = """
        #EXTINF:-1,Orphan
        #EXTINF:-1,Real
        https://example.com/real.m3u8
        """
        XCTAssertEqual(PlaylistParser.parse(m3u).map(\.name), ["Real"])
    }

    func testIgnoresUnknownDirectivesBetweenInfoAndURL() {
        let m3u = """
        #EXTINF:-1,Chan
        #EXTVLCOPT:http-referrer=https://ref.test/
        https://example.com/chan.m3u8
        """
        XCTAssertEqual(PlaylistParser.parse(m3u).map(\.name), ["Chan"])
    }

    func testHandlesWindowsLineEndings() {
        let m3u = "#EXTM3U\r\n#EXTINF:-1 tvg-id=\"A.us\",Chan A\r\nhttps://example.com/a.m3u8\r\n"
        let streams = PlaylistParser.parse(m3u)
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].url.absoluteString, "https://example.com/a.m3u8")
    }

    func testMissingAttributesYieldNilsAndEmptyCategories() {
        let streams = PlaylistParser.parse("#EXTINF:-1,Plain\nhttps://example.com/p.m3u8")
        XCTAssertEqual(streams.count, 1)
        XCTAssertNil(streams[0].channelID)
        XCTAssertNil(streams[0].country)
        XCTAssertNil(streams[0].logoURL)
        XCTAssertEqual(streams[0].categories, [])
    }

    func testCountryDerivation() {
        func country(_ tvgID: String) -> String? {
            PlaylistParser.parse("#EXTINF:-1 tvg-id=\"\(tvgID)\",X\nhttps://e.test/\(tvgID).m3u8").first?.country
        }
        XCTAssertEqual(country("Foo.us"), "US")
        XCTAssertEqual(country("Foo.us@HD"), "US")
        XCTAssertNil(country("Foo"))
        XCTAssertNil(country("Foo.com"))
    }

    func testEmptyAndGarbageInputReturnEmpty() {
        XCTAssertEqual(PlaylistParser.parse(""), [])
        XCTAssertEqual(PlaylistParser.parse("<html>not a playlist</html>"), [])
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd Tests/StreamLogic && swift test 2>&1 | tail -20`
Expected: build failure, `cannot find 'PlaylistParser' in scope` (the source folder is empty).
If `swift test` fails because XCTest is unavailable on this machine, stop and report. Do not switch frameworks without asking.

- [ ] **Step 4: Implement the model**

Create `aftermath/Streams/IPTVStream.swift`:

```swift
import Foundation

nonisolated struct IPTVStream: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let url: URL
    let channelID: String?
    let categories: [String]
    let country: String?
    let logoURL: URL?

    var id: String { url.absoluteString }
}
```

- [ ] **Step 5: Implement the parser**

Create `aftermath/Streams/PlaylistParser.swift`:

```swift
import Foundation

nonisolated enum PlaylistParser {
    static func parse(_ text: String) -> [IPTVStream] {
        var streams: [IPTVStream] = []
        var pending: (name: String, attributes: [String: String])?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF:") {
                pending = parseExtInf(String(line.dropFirst("#EXTINF:".count)))
            } else if line.hasPrefix("#") {
                continue
            } else if let info = pending {
                pending = nil
                guard let url = URL(string: line),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { continue }

                let channelID = info.attributes["tvg-id"].flatMap { $0.isEmpty ? nil : $0 }
                let categories = (info.attributes["group-title"] ?? "")
                    .split(separator: ";")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                let logoURL = info.attributes["tvg-logo"].flatMap { $0.isEmpty ? nil : URL(string: $0) }

                streams.append(IPTVStream(
                    name: info.name,
                    url: url,
                    channelID: channelID,
                    categories: categories,
                    country: country(from: channelID),
                    logoURL: logoURL
                ))
            }
        }
        return streams
    }

    /// Splits `-1 key="v" key2="v2",Display Name` at the first comma outside quotes.
    private static func parseExtInf(_ body: String) -> (name: String, attributes: [String: String])? {
        var inQuotes = false
        var commaIndex: String.Index?
        for index in body.indices {
            let character = body[index]
            if character == "\"" {
                inQuotes.toggle()
            } else if character == "," && !inQuotes {
                commaIndex = index
                break
            }
        }

        let header = commaIndex.map { String(body[..<$0]) } ?? body
        var name = commaIndex
            .map { String(body[body.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""

        var attributes: [String: String] = [:]
        for match in header.matches(of: /([A-Za-z0-9_-]+)="([^"]*)"/) {
            attributes[String(match.output.1).lowercased()] = String(match.output.2)
        }

        if name.isEmpty { name = attributes["tvg-name"] ?? "" }
        return name.isEmpty ? nil : (name, attributes)
    }

    /// `BBCOne.uk@SD` -> `UK`. Returns nil unless the suffix is exactly two letters.
    private static func country(from channelID: String?) -> String? {
        guard let channelID else { return nil }
        let base = channelID.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? channelID
        guard let dot = base.lastIndex(of: ".") else { return nil }
        let suffix = base[base.index(after: dot)...]
        guard suffix.count == 2, suffix.allSatisfy(\.isLetter) else { return nil }
        return suffix.uppercased()
    }
}
```

Note: when `parseExtInf` returns nil, `pending` becomes nil and the following URL line is dropped, which is intended (a nameless entry is skipped).

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd Tests/StreamLogic && swift test 2>&1 | tail -20`
Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add .gitignore Tests aftermath/Streams
git commit -m "feat: add IPTVStream model and M3U playlist parser with test harness"
```

---

### Task 2: Filter and favorites

**Files:**
- Create: `aftermath/Streams/StreamFilter.swift`
- Create: `aftermath/Streams/FavoritesStore.swift`
- Create: `Tests/StreamLogic/Tests/StreamLogicTests/StreamFilterTests.swift`
- Create: `Tests/StreamLogic/Tests/StreamLogicTests/FavoritesStoreTests.swift`

**Interfaces:**
- Consumes: `IPTVStream` (Task 1).
- Produces:
  - `nonisolated enum StreamFilter` with `static func apply(_ streams: [IPTVStream], query: String, category: String?, country: String?) -> [IPTVStream]`, `static func categories(in: [IPTVStream]) -> [String]` (sorted, unique), and `static func countries(in: [IPTVStream]) -> [String]` (sorted, unique).
  - `@Observable final class FavoritesStore` with `init(defaults: UserDefaults = .standard)`, `private(set) var streams: [IPTVStream]`, `func contains(_ stream: IPTVStream) -> Bool`, and `func toggle(_ stream: IPTVStream)`.

- [ ] **Step 1: Write the failing tests**

Create `StreamFilterTests.swift`:

```swift
import XCTest
@testable import StreamLogic

final class StreamFilterTests: XCTestCase {
    private func stream(_ name: String, categories: [String] = [], country: String? = nil) -> IPTVStream {
        IPTVStream(
            name: name,
            url: URL(string: "https://e.test/\(name.hashValue).m3u8")!,
            channelID: nil,
            categories: categories,
            country: country,
            logoURL: nil
        )
    }

    func testEmptyAndWhitespaceQueryReturnsEverything() {
        let all = [stream("A"), stream("B")]
        XCTAssertEqual(StreamFilter.apply(all, query: "", category: nil, country: nil), all)
        XCTAssertEqual(StreamFilter.apply(all, query: "   ", category: nil, country: nil), all)
    }

    func testQueryIgnoresCaseAndDiacritics() {
        let all = [stream("Télévision Française"), stream("Other")]
        let result = StreamFilter.apply(all, query: "television", category: nil, country: nil)
        XCTAssertEqual(result.map(\.name), ["Télévision Française"])
    }

    func testCategoryFilterMatchesAnyOfMultipleCategories() {
        let all = [stream("A", categories: ["News", "Sports"]), stream("B", categories: ["Kids"])]
        XCTAssertEqual(StreamFilter.apply(all, query: "", category: "Sports", country: nil).map(\.name), ["A"])
    }

    func testCountryFilterAndCombinedFilters() {
        let all = [
            stream("A", categories: ["News"], country: "US"),
            stream("B", categories: ["News"], country: "UK"),
        ]
        XCTAssertEqual(StreamFilter.apply(all, query: "", category: nil, country: "UK").map(\.name), ["B"])
        XCTAssertEqual(StreamFilter.apply(all, query: "a", category: "News", country: "US").map(\.name), ["A"])
        XCTAssertEqual(StreamFilter.apply(all, query: "a", category: "News", country: "UK"), [])
    }

    func testCategoriesAndCountriesAreSortedAndUnique() {
        let all = [
            stream("A", categories: ["News", "Kids"], country: "US"),
            stream("B", categories: ["News"], country: "UK"),
            stream("C", country: nil),
        ]
        XCTAssertEqual(StreamFilter.categories(in: all), ["Kids", "News"])
        XCTAssertEqual(StreamFilter.countries(in: all), ["UK", "US"])
    }
}
```

Create `FavoritesStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Tests/StreamLogic && swift test 2>&1 | tail -20`
Expected: build failure, `cannot find 'StreamFilter'` / `'FavoritesStore' in scope`.

- [ ] **Step 3: Implement the filter**

Create `aftermath/Streams/StreamFilter.swift`:

```swift
import Foundation

nonisolated enum StreamFilter {
    static func apply(
        _ streams: [IPTVStream],
        query: String,
        category: String?,
        country: String?
    ) -> [IPTVStream] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return streams.filter { stream in
            if let category, !stream.categories.contains(category) { return false }
            if let country, stream.country != country { return false }
            if !trimmed.isEmpty,
               stream.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                return false
            }
            return true
        }
    }

    static func categories(in streams: [IPTVStream]) -> [String] {
        Array(Set(streams.flatMap(\.categories))).sorted()
    }

    static func countries(in streams: [IPTVStream]) -> [String] {
        Array(Set(streams.compactMap(\.country))).sorted()
    }
}
```

- [ ] **Step 4: Implement favorites**

Create `aftermath/Streams/FavoritesStore.swift`:

```swift
import Foundation
import Observation

@Observable
final class FavoritesStore {
    private(set) var streams: [IPTVStream]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "favoriteStreams"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([IPTVStream].self, from: data) {
            streams = decoded
        } else {
            streams = []
        }
    }

    func contains(_ stream: IPTVStream) -> Bool {
        streams.contains { $0.id == stream.id }
    }

    func toggle(_ stream: IPTVStream) {
        if let index = streams.firstIndex(where: { $0.id == stream.id }) {
            streams.remove(at: index)
        } else {
            streams.append(stream)
        }
        if let data = try? JSONEncoder().encode(streams) {
            defaults.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd Tests/StreamLogic && swift test 2>&1 | tail -20`
Expected: all tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add aftermath/Streams Tests
git commit -m "feat: add stream filter and persisted favorites store"
```

---

### Task 3: Stream catalog (fetch, cache, state)

**Files:**
- Create: `aftermath/Streams/StreamCatalog.swift`
- Create: `Tests/StreamLogic/Tests/StreamLogicTests/StreamCatalogTests.swift`

**Interfaces:**
- Consumes: `IPTVStream`, `PlaylistParser.parse`, `StreamFilter.apply/categories/countries`.
- Produces: `@Observable final class StreamCatalog` with:
  - `enum State: Equatable { case idle, loading, loaded, failed(String) }`
  - `private(set) var state: State`, `private(set) var streams: [IPTVStream]`, `private(set) var categories: [String]`, `private(set) var countries: [String]`
  - `var query: String`, `var category: String?`, `var country: String?`
  - `var filtered: [IPTVStream]`
  - `init(cacheURL: URL = URL.cachesDirectory.appending(path: "iptv-index.m3u"), fetch: @escaping @Sendable () async throws -> String = StreamCatalog.fetchIndex)`
  - `func load() async`
  - `nonisolated static func fetchIndex() async throws -> String`

- [ ] **Step 1: Write the failing tests**

Create `StreamCatalogTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Tests/StreamLogic && swift test 2>&1 | tail -20`
Expected: build failure, `cannot find 'StreamCatalog' in scope`.

- [ ] **Step 3: Implement the catalog**

Create `aftermath/Streams/StreamCatalog.swift`:

```swift
import Foundation
import Observation

@Observable
final class StreamCatalog {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private struct EmptyPlaylistError: LocalizedError {
        var errorDescription: String? { "The stream list was empty." }
    }

    private(set) var state: State = .idle
    private(set) var streams: [IPTVStream] = []
    private(set) var categories: [String] = []
    private(set) var countries: [String] = []

    var query = ""
    var category: String?
    var country: String?

    var filtered: [IPTVStream] {
        StreamFilter.apply(streams, query: query, category: category, country: country)
    }

    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private let fetch: @Sendable () async throws -> String

    init(
        cacheURL: URL = URL.cachesDirectory.appending(path: "iptv-index.m3u"),
        fetch: @escaping @Sendable () async throws -> String = StreamCatalog.fetchIndex
    ) {
        self.cacheURL = cacheURL
        self.fetch = fetch
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading

        do {
            let text = try await fetch()
            let parsed = await Task.detached { PlaylistParser.parse(text) }.value
            guard !parsed.isEmpty else { throw EmptyPlaylistError() }
            apply(parsed)
            try? text.write(to: cacheURL, atomically: true, encoding: .utf8)
        } catch {
            if !streams.isEmpty {
                state = .loaded
                return
            }
            if let cached = try? String(contentsOf: cacheURL, encoding: .utf8) {
                let parsed = await Task.detached { PlaylistParser.parse(cached) }.value
                if !parsed.isEmpty {
                    apply(parsed)
                    return
                }
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func apply(_ parsed: [IPTVStream]) {
        streams = parsed
        categories = StreamFilter.categories(in: parsed)
        countries = StreamFilter.countries(in: parsed)
        state = .loaded
    }

    nonisolated static func fetchIndex() async throws -> String {
        let url = URL(string: "https://iptv-org.github.io/iptv/index.m3u")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return text
    }
}
```
- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Tests/StreamLogic && swift test 2>&1 | tail -20`
Expected: all tests pass, 0 failures. If a concurrency warning or error appears in the `fetch:` closures, fix it in the test file or implementation. Do not weaken the assertions.

- [ ] **Step 5: Commit**

```bash
git add aftermath/Streams Tests
git commit -m "feat: add stream catalog with fetch, cache fallback and filtering"
```

---

### Task 4: Browser UI and ContentView rework

This task needs Xcode (`xcodebuild` and the visionOS simulator). The environment that planned this has only Command Line Tools. If Xcode is not available, implement the code, then stop and tell the user the build and manual check are unverified. Do not claim success.

**Files:**
- Create: `aftermath/Views/StreamArtwork.swift`
- Create: `aftermath/Views/StreamBrowserView.swift`
- Modify: `aftermath/ContentView.swift`

**Interfaces:**
- Consumes: `IPTVStream`, `StreamCatalog` (all members above), `FavoritesStore` (`streams`, `contains`, `toggle`).
- Produces:
  - `StreamArtwork(stream: IPTVStream, size: CGFloat)`
  - `StreamBrowserView(catalog: StreamCatalog, favorites: FavoritesStore, onSelect: (IPTVStream) -> Void)`

- [ ] **Step 1: Create `StreamArtwork`**

Create `aftermath/Views/StreamArtwork.swift`:

```swift
import SwiftUI

struct StreamArtwork: View {
    let stream: IPTVStream
    let size: CGFloat

    var body: some View {
        Group {
            if let logoURL = stream.logoURL {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.12)
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Color.gray.opacity(0.3)))
        .clipShape(Circle())
    }

    private var initials: some View {
        Text(String(stream.name.prefix(2)).uppercased())
            .font(.system(size: size * 0.32, weight: .semibold))
            .foregroundColor(.white.opacity(0.8))
    }
}
```

- [ ] **Step 2: Create `StreamBrowserView`**

Create `aftermath/Views/StreamBrowserView.swift`:

```swift
import SwiftUI

struct StreamBrowserView: View {
    @Bindable var catalog: StreamCatalog
    var favorites: FavoritesStore
    var onSelect: (IPTVStream) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Streams")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .frame(width: 700, height: 600)
        .task {
            if catalog.streams.isEmpty { await catalog.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if catalog.streams.isEmpty {
            switch catalog.state {
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load streams", systemImage: "wifi.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await catalog.load() } }
                }
            default:
                ProgressView("Loading streams…")
            }
        } else {
            list
        }
    }

    private var list: some View {
        List(catalog.filtered) { stream in
            HStack(spacing: 12) {
                Button {
                    onSelect(stream)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        StreamArtwork(stream: stream, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stream.name).lineLimit(1)
                            Text(subtitle(for: stream))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    favorites.toggle(stream)
                } label: {
                    Image(systemName: favorites.contains(stream) ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
            }
        }
        .searchable(text: $catalog.query, prompt: "Search streams")
        .overlay {
            if catalog.filtered.isEmpty {
                ContentUnavailableView.search(text: catalog.query)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Menu {
                    Picker("Category", selection: $catalog.category) {
                        Text("All categories").tag(String?.none)
                        ForEach(catalog.categories, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: {
                    Label(catalog.category ?? "Category", systemImage: "square.grid.2x2")
                }

                Menu {
                    Picker("Country", selection: $catalog.country) {
                        Text("All countries").tag(String?.none)
                        ForEach(catalog.countries, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: {
                    Label(catalog.country ?? "Country", systemImage: "globe")
                }
            }
        }
    }

    private func subtitle(for stream: IPTVStream) -> String {
        ([stream.country].compactMap { $0 } + stream.categories).joined(separator: " · ")
    }
}
```

- [ ] **Step 3: Rework `ContentView.swift` state**

In `aftermath/ContentView.swift`:

1. Delete the `Channel` enum (lines 14-22).
2. Replace the state declarations at lines 28 and 31-33 and 40-41 (`selectedChannel`, `showSettings`, `showURLAlert`, `alertMessage`, `estURL`, `pstURL`) with:

```swift
    @State private var currentStream: IPTVStream?
    @State private var showBrowser: Bool = false
    @State private var playbackFailed: Bool = false
    @State private var statusObservation: NSKeyValueObservation?
    @State private var catalog = StreamCatalog()
    @State private var favorites = FavoritesStore()
```

- [ ] **Step 4: Rework the video area and ornament**

Inside the main `ZStack`, after the play/pause `Image` and before the closing brace, add:

```swift
            if currentStream == nil {
                Text("Browse streams")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
                    .allowsHitTesting(false)
            } else if playbackFailed {
                Text("Stream unavailable")
                    .font(.title2)
                    .padding(12)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.white)
                    .allowsHitTesting(false)
            }
```

In the ornament, replace the `ForEach(Channel.allCases...)` block and the gear `Button` (old lines 123-159) with:

```swift
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(favorites.streams) { stream in
                            Button(action: { play(stream) }) {
                                StreamArtwork(stream: stream, size: 60)
                                    .overlay(
                                        Circle().stroke(
                                            currentStream?.id == stream.id ? Color.blue : Color.white.opacity(0.2),
                                            lineWidth: currentStream?.id == stream.id ? 3 : 1
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: 420)

                Button(action: { showBrowser = true }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.gray.opacity(0.3)))
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
```

- [ ] **Step 5: Replace sheet, alert, onChange, and channel switching**

Replace the `.sheet(isPresented: $showSettings)`, `.alert(...)`, and `.onChange(of: selectedChannel)` modifiers (old lines 177-190) with:

```swift
        .sheet(isPresented: $showBrowser) {
            StreamBrowserView(catalog: catalog, favorites: favorites, onSelect: play)
        }
```

Replace `switchChannel(to:)` (old lines 257-283) with:

```swift
    private func play(_ stream: IPTVStream) {
        currentStream = stream
        playbackFailed = false

        let newItem = AVPlayerItem(url: stream.url)
        statusObservation = newItem.observe(\.status, options: [.new]) { item, _ in
            let failed = item.status == .failed
            Task { @MainActor in playbackFailed = failed }
        }

        player.replaceCurrentItem(with: newItem)
        player.volume = Float(volume)
        player.play()
        isPlaying = true
        showIcon = true
        hideIconAfterDelay()

        setupMetadataObservers()
    }
```

- [ ] **Step 6: Remove `SettingsView`**

Delete the whole `struct SettingsView: View { ... }` (old lines 352-386). Leave `MetadataDelegate` and the `#Preview` in place.

- [ ] **Step 7: Build**

Run: `xcodebuild -project aftermath.xcodeproj -scheme aftermath -destination 'generic/platform=visionOS Simulator' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`. Fix any compile errors in the files above. If `xcodebuild` is unavailable, report that and stop.

- [ ] **Step 8: Manual check in the visionOS simulator**

Confirm each:
1. First launch shows "Browse streams" and a browse button with no favorites.
2. The browser loads the list, search narrows it, and category and country menus filter it.
3. Starring a row adds it to the ornament, and the star state persists after relaunch.
4. Tapping a row plays it, and the playing favorite's ring is highlighted.
5. Playing a known-dead URL (star any entry, or temporarily use `https://example.invalid/x.m3u8`) shows "Stream unavailable".
6. With networking disabled after one successful load, the browser still opens from cache.

- [ ] **Step 9: Commit**

```bash
git add aftermath
git commit -m "feat: replace manual URL settings with iptv-org stream browser and favorites"
```

---

### Task 5: Remove Toonami references and update docs

**Files:**
- Modify: `README.md`
- Modify: `.claude/settings.local.json` (remove the `WebFetch(domain:api.toonamiaftermath.com)` entry; the file is untracked, so no commit applies to it)

- [ ] **Step 1: Rewrite the README feature and usage sections**

Replace the intro line, the note, "Features", and "Usage" (`README.md` lines 7-38) with:

```markdown
A minimal 4:3 aspect ratio visionOS streaming app for Apple Vision Pro. Browse and watch live streams from the community-maintained [iptv-org](https://github.com/iptv-org/iptv) playlist.

**Note:** This app does not host or provide any video. It loads the public iptv-org playlist, which, in their words, "simply contains user-submitted links to publicly available video stream URLs." Many streams are geo-blocked or offline.

## Features

- **Stream Browser** - Search the full iptv-org index and filter by category and country
- **Favorites** - Star streams to pin them to the ornament for one-tap switching
- **Offline-Tolerant Catalog** - The last downloaded playlist is cached for when the network is unavailable
- **4:3 Aspect Ratio** - Window perfectly hugs the video content with no wasted space
- **Ornament Controls** - Volume, favorites and the stream browser float outside the video window

# Usage

## First Launch

1. Tap the **list icon** in the ornament above the video
2. Search or filter, then tap a stream to play it
3. Tap the **star** on any stream to add it to your favorites

## Controls

- **Favorite Buttons** - Switch between your starred streams
- **List Button** - Open the stream browser
- **Tap Video** - Show/hide pause/play control
- **Pause/Play Icon** - Auto-hides after 2 seconds while playing
```

- [ ] **Step 2: Remove the stale settings entry and verify**

Edit `.claude/settings.local.json` to delete the `"WebFetch(domain:api.toonamiaftermath.com)",` line, keeping the JSON valid.

Run:
```bash
python3 -c "import json; json.load(open('.claude/settings.local.json'))" && echo valid
grep -rniE 'toonami' --exclude-dir=.git --exclude-dir=.build --exclude-dir=docs . || echo "no toonami references"
```
Expected: `valid`, then `no toonami references`. (`docs/` is excluded because the spec and plan describe the change and necessarily mention the old wording.)

- [ ] **Step 3: Run the full logic suite once more**

Run: `cd Tests/StreamLogic && swift test 2>&1 | tail -5`
Expected: all tests pass, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: describe iptv-org stream browser and drop Toonami references"
```
