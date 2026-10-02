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
import UIKit

struct ContentView: View {
    @State private var player: AVPlayer
    @State private var isPlaying: Bool = false
    @State private var showIcon: Bool = true
    @State private var currentStream: IPTVStream?
    @State private var metadata: [String: String] = [:]
    @State private var timedMetadata: String = ""
    @State private var showBrowser: Bool = false
    @State private var playbackFailed: Bool = false
    @State private var statusObservation: NSKeyValueObservation?
    @State private var catalog = StreamCatalog()
    @State private var favorites = FavoritesStore()
    @State private var volume: Double = 1.0
    @State private var previousVolume: Double = 1.0
    @State private var showOrnaments: Bool = true
    @State private var ornamentHideTask: Task<Void, Never>?
    @State private var isInteractingWithOrnaments: Bool = false

    init() {
        // Create player with a blank item initially
        // User picks a stream from the browser or a favorite
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

            Button(action: {
                if showOrnaments {
                    togglePlayPause()
                } else {
                    showOrnamentsTemporarily()
                }
            }) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.8))
                .shadow(radius: 10)
                .animation(nil, value: isPlaying)
                .opacity(showIcon && currentStream != nil ? 1 : 0)
                .animation(.easeInOut, value: showIcon)
                .allowsHitTesting(false)

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
        }
        .onAppear {
            setupMetadataObservers()

            // Set uniform resizing to maintain aspect ratio
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            let preferences = UIWindowScene.GeometryPreferences.Vision(
                resizingRestrictions: .uniform
            )
            windowScene.requestGeometryUpdate(preferences)
        }
        .ornament(
            visibility: .visible,
            attachmentAnchor: .scene(.top),
            contentAlignment: .bottom
        ) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: toggleMute) {
                        Image(systemName: volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 40, height: 40)

                    Slider(value: $volume, in: 0...1)
                        .frame(width: 180)
                        .onChange(of: volume) { oldValue, newValue in
                            if newValue > 0 {
                                previousVolume = newValue
                            }
                            player.volume = Float(newValue)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.gray.opacity(0.3))
                )

                Spacer(minLength: 200)

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
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .opacity(showOrnaments ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: showOrnaments)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    keepOrnamentsVisible()
                case .ended:
                    releaseOrnamentInteraction()
                }
            }
            .onAppear {
                scheduleOrnamentHide()
            }
        }
        .sheet(isPresented: $showBrowser) {
            StreamBrowserView(catalog: catalog, favorites: favorites, onSelect: play)
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

    private func toggleMute() {
        if volume > 0 {
            previousVolume = volume
            volume = 0
        } else {
            volume = previousVolume > 0 ? previousVolume : 1.0
        }
        player.volume = Float(volume)
    }

    private func hideIconAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                showIcon = false
            }
        }
    }

    private func scheduleOrnamentHide() {
        ornamentHideTask?.cancel()
        ornamentHideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !isInteractingWithOrnaments {
                withAnimation {
                    showOrnaments = false
                }
            }
        }
    }

    private func showOrnamentsTemporarily() {
        withAnimation {
            showOrnaments = true
        }
        scheduleOrnamentHide()
    }

    private func keepOrnamentsVisible() {
        ornamentHideTask?.cancel()
        isInteractingWithOrnaments = true
        withAnimation {
            showOrnaments = true
        }
    }

    private func releaseOrnamentInteraction() {
        isInteractingWithOrnaments = false
        scheduleOrnamentHide()
    }

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
