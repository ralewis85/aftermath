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
