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
