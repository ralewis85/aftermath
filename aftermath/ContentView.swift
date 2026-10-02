//
//  ContentView.swift
//  aftermath
//
//  Created by Robert Lewis on 11/22/25.
//

import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct ContentView: View {
    @State private var player: AVPlayer
    @State private var isPlaying: Bool = false
    @State private var showIcon: Bool = true
    @State private var currentStream: IPTVStream?
    @State private var showBrowser: Bool = false
    @State private var playbackFailed: Bool = false
    @State private var statusObservation: NSKeyValueObservation?
    @State private var timeControlObservation: NSKeyValueObservation?
    @State private var watchdog = StallWatchdog()
    @State private var catalog = StreamCatalog()
    @State private var favorites = FavoritesStore()
    @State private var volume: Double = 1.0
    @State private var previousVolume: Double = 1.0
    @State private var showOrnaments: Bool = true
    @State private var ornamentHideTask: Task<Void, Never>?
    @State private var isInteractingWithOrnaments: Bool = false

    private let lastStream = LastStreamStore()
    private let startupTimeout: Double = 15

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
                Button(action: { showBrowser = true }) {
                    Label("Browse streams", systemImage: "list.bullet")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
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
            observePlaybackStart()
            if currentStream == nil, let last = lastStream.load() {
                load(last, autoplay: false)
            }

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
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
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
        guard currentStream != nil else {
            showBrowser = true
            return
        }

        if isPlaying {
            player.pause()
            isPlaying = false
            showIcon = true
            watchdog.disarm()
        } else {
            startPlayback()
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

    /// User-initiated selection (browser row or favorite button).
    private func play(_ stream: IPTVStream) {
        if currentStream?.id == stream.id && !playbackFailed {
            if !isPlaying { startPlayback() }
            return
        }
        lastStream.save(stream)
        load(stream, autoplay: true)
    }

    private func load(_ stream: IPTVStream, autoplay: Bool) {
        currentStream = stream
        playbackFailed = false
        watchdog.disarm()

        let newItem = AVPlayerItem(url: stream.url)
        statusObservation = newItem.observe(\.status, options: [.new]) { item, _ in
            let failed = item.status == .failed
            Task { @MainActor in playbackFailed = failed }
        }

        player.replaceCurrentItem(with: newItem)
        player.volume = Float(volume)

        if autoplay {
            startPlayback()
        } else {
            isPlaying = false
            showIcon = true
        }
    }

    private func startPlayback() {
        player.play()
        isPlaying = true
        showIcon = true
        hideIconAfterDelay()
        watchdog.arm(after: startupTimeout) {
            if currentStream != nil && isPlaying { playbackFailed = true }
        }
    }

    /// Clears the stall timer and any failure overlay once video is actually playing.
    private func observePlaybackStart() {
        guard timeControlObservation == nil else { return }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor in
                if playing {
                    watchdog.disarm()
                    playbackFailed = false
                }
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
