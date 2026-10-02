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
        for match in header.matches(of: #/([A-Za-z0-9_-]+)="([^"]*)"/#) {
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
