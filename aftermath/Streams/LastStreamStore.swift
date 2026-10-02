import Foundation

nonisolated struct LastStreamStore {
    private let defaults: UserDefaults
    private let key = "lastStream"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> IPTVStream? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(IPTVStream.self, from: data)
    }

    func save(_ stream: IPTVStream) {
        if let data = try? JSONEncoder().encode(stream) {
            defaults.set(data, forKey: key)
        }
    }
}
