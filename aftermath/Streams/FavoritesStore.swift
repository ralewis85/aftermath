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
