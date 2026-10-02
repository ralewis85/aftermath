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
