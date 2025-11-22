//
//  ContentView.swift
//  aftermath
//
//  Created by Robert Lewis on 11/22/25.
//

import SwiftUI
import AVKit
import AVFoundation
import CoreMedia

enum Channel: String, CaseIterable {
    case est = "EST"
    case pst = "PST"

    func streamURL(estURL: String, pstURL: String) -> URL? {
        let urlString = self == .est ? estURL : pstURL
        return URL(string: urlString)
    }
}

struct ContentView: View {
    @State private var player: AVPlayer
    @State private var isPlaying: Bool = false
    @State private var showIcon: Bool = true
    @State private var selectedChannel: Channel = .est
    @State private var metadata: [String: String] = [:]
    @State private var timedMetadata: String = ""
    @State private var showSettings: Bool = false
    @State private var showURLAlert: Bool = false
    @State private var alertMessage: String = ""

    @AppStorage("estURL") private var estURL: String = ""
    @AppStorage("pstURL") private var pstURL: String = ""

    init() {
        // Create player with a blank item initially
        // User will need to configure URLs and select a channel
        let dummyURL = URL(string: "about:blank")!
        let playerItem = AVPlayerItem(url: dummyURL)
        _player = State(initialValue: AVPlayer(playerItem: playerItem))
    }

    var body: some View {
        ZStack {
            VideoPlayer(player: player)
                .disabled(true)
                .aspectRatio(4.0/3.0, contentMode: .fit)
                .ignoresSafeArea()

            Button(action: togglePlayPause) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.8))
                .shadow(radius: 10)
                .animation(nil, value: isPlaying)
                .opacity(showIcon ? 1 : 0)
                .animation(.easeInOut, value: showIcon)
                .allowsHitTesting(false)
        }
        .frame(width: 800, height: 600)
        .aspectRatio(4.0/3.0, contentMode: .fit)
        .onAppear {
            setupMetadataObservers()
        }
        .ornament(
            visibility: .visible,
            attachmentAnchor: .scene(.top),
            contentAlignment: .bottom
        ) {
            HStack(spacing: 12) {
                ForEach(Channel.allCases, id: \.self) { channel in
                    Button(action: {
                        selectedChannel = channel
                    }) {
                        Text(channel.rawValue)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedChannel == channel ? .white : .white.opacity(0.6))
                            .frame(width: 60, height: 60)
                            .background(
                                Circle()
                                    .fill(selectedChannel == channel ? Color.blue : Color.gray.opacity(0.3))
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(estURL: $estURL, pstURL: $pstURL)
        }
        .alert("URL Required", isPresented: $showURLAlert) {
            Button("Open Settings") {
                showSettings = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onChange(of: selectedChannel) { oldValue, newValue in
            switchChannel(to: newValue)
        }
    }

    private func togglePlayPause() {
        isPlaying.toggle()

        if isPlaying {
            player.play()
            showIcon = true
            hideIconAfterDelay()
        } else {
            player.pause()
            showIcon = true
        }
    }

    private func hideIconAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                showIcon = false
            }
        }
    }

    private func switchChannel(to channel: Channel) {
        let channelURL = channel == .est ? estURL : pstURL

        // Check if URL is empty or invalid
        if channelURL.trimmingCharacters(in: .whitespaces).isEmpty {
            alertMessage = "No URL configured for \(channel.rawValue) channel.\n\nPlease tap the settings icon (⚙️) to configure the stream URL."
            showURLAlert = true
            return
        }

        guard let url = channel.streamURL(estURL: estURL, pstURL: pstURL) else {
            alertMessage = "Invalid URL for \(channel.rawValue) channel.\n\nPlease check the URL in settings and try again."
            showURLAlert = true
            return
        }

        let wasPlaying = isPlaying
        let newItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: newItem)

        if wasPlaying {
            player.play()
        }

        setupMetadataObservers()
    }

    private func setupMetadataObservers() {
        guard let currentItem = player.currentItem else { return }

        // Extract basic metadata
        Task {
            let commonMetadata = try? await currentItem.asset.load(.commonMetadata)
            var extractedMetadata: [String: String] = [:]

            for item in commonMetadata ?? [] {
                if let key = item.commonKey?.rawValue,
                   let value = try? await item.load(.stringValue) {
                    extractedMetadata[key] = value
                }
            }

            await MainActor.run {
                self.metadata = extractedMetadata
            }
        }

        // Observe timed metadata
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newAccessLogEntryNotification,
            object: currentItem,
            queue: .main
        ) { _ in
            // Log access entry updates
        }

        // Check for timed metadata tracks
        Task {
            if let tracks = try? await currentItem.asset.load(.tracks) {
                for track in tracks {
                    if let formatDescriptions = try? await track.load(.formatDescriptions) {
                        for description in formatDescriptions {
                            let mediaType = CMFormatDescriptionGetMediaType(description)
                            if mediaType == kCMMediaType_Metadata {
                                print("Found metadata track")
                            }
                        }
                    }
                }
            }
        }

        // Observe metadata output
        let metadataOutput = AVPlayerItemMetadataOutput()
        let delegate = MetadataDelegate { items in
            Task {
                var metadataStrings: [String] = []
                for item in items {
                    if let value = try? await item.load(.value) as? String {
                        metadataStrings.append(value)
                    }
                }
                if !metadataStrings.isEmpty {
                    await MainActor.run {
                        self.timedMetadata = metadataStrings.joined(separator: ", ")
                    }
                }
            }
        }
        metadataOutput.setDelegate(delegate, queue: DispatchQueue.main)
        currentItem.add(metadataOutput)
    }
}

struct SettingsView: View {
    @Binding var estURL: String
    @Binding var pstURL: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("EST Channel URL") {
                    TextField("http://api.toonamiaftermath.com:3000/est/playlist.m3u8", text: $estURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("PST Channel URL") {
                    TextField("http://api.toonamiaftermath.com:3000/pst/playlist.m3u8", text: $pstURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Button("Use Toonami Aftermath URLs") {
                        estURL = "http://api.toonamiaftermath.com:3000/est/playlist.m3u8"
                        pstURL = "http://api.toonamiaftermath.com:3000/pst/playlist.m3u8"
                    }
                }
            }
            .navigationTitle("Stream Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 400)
    }
}

class MetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    let onMetadata: ([AVMetadataItem]) -> Void

    init(onMetadata: @escaping ([AVMetadataItem]) -> Void) {
        self.onMetadata = onMetadata
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        let items = groups.flatMap { $0.items }
        if !items.isEmpty {
            onMetadata(items)
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
