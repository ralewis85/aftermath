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

    var query = "" { didSet { refilter() } }
    var category: String? { didSet { refilter() } }
    var country: String? { didSet { refilter() } }

    /// Cached so view bodies can read it repeatedly without re-scanning the whole index.
    private(set) var filtered: [IPTVStream] = []

    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private let fetch: @Sendable () async throws -> String
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    init(
        cacheURL: URL = URL.cachesDirectory.appending(path: "iptv-index.m3u"),
        fetch: @escaping @Sendable () async throws -> String = { try await StreamCatalog.fetchIndex() }
    ) {
        self.cacheURL = cacheURL
        self.fetch = fetch
    }

    /// Joins an in-flight download if there is one. The download runs in its own task, so
    /// cancelling the caller (e.g. dismissing the browser sheet) does not abort it.
    func load() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await self.performLoad() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performLoad() async {
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
        refilter()
        state = .loaded
    }

    private func refilter() {
        filtered = StreamFilter.apply(streams, query: query, category: category, country: country)
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
