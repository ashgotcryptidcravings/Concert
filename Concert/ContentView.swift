//
//  ContentView.swift
//  Concert
//

import SwiftUI
import UIKit
import AVKit
import CoreData

private enum ConcertTab: String, CaseIterable {
    case discover = "Discover"
    case favorites = "Favorites"
    case search = "Search"

    var symbol: String {
        switch self {
        case .discover: return "sparkle.magnifyingglass"
        case .favorites: return "heart"
        case .search: return "magnifyingglass"
        }
    }
}

private let equalizerPresets: [String: [Double]] = [
    "Flat":              [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    "Acoustic":           [4, 3, 2, 1, 1, 2, 3, 3, 2, 2],
    "Bass Booster":       [8, 7, 6, 4, 2, 0, 0, 0, 1, 1],
    "Bass Reducer":       [-7, -6, -4, -2, 0, 1, 2, 2, 2, 2],
    "Classical":          [4, 3, 2, 1, -1, -2, 0, 2, 3, 4],
    "Dance":              [5, 4, 1, 0, 1, 3, 4, 3, 1, 0],
    "Electronic":         [5, 4, 2, 0, -1, 2, 1, 2, 4, 5],
    "Hip-Hop":            [6, 5, 2, 3, -1, -1, 1, 2, 3, 3],
    "Jazz":               [4, 3, 1, 2, -2, -2, 0, 2, 4, 5],
    "Late Night":         [3, 2, 1, 0, 1, 2, 3, 2, 1, 0],
    "Pop":                [-1, 1, 3, 4, 2, 0, -1, -1, 1, 2],
    "R&B":                [4, 3, 1, 2, -1, 0, 1, 2, 3, 4],
    "Rock":               [5, 4, 3, 1, -1, 1, 3, 4, 4, 4],
    "Vocal Booster":      [-2, -1, 0, 2, 4, 4, 3, 2, 1, 0]
]

private enum AlbumSheet: Identifiable {
    case all
    case detail(AlbumCollection)

    var id: String {
        switch self {
        case .all: return "all-albums"
        case .detail(let album): return "album-\(album.id)"
        }
    }
}

private struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .secondaryLabel
        picker.activeTintColor = UIColor(Color.accentColor)
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}

private let loadingTrack = Track(
    title: "",
    artist: "",
    album: "",
    duration: "0:00",
    artwork: "music.note",
    tint: Color(uiColor: .tertiarySystemFill),
    quality: ""
)

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: ConcertTab = .discover
    @State private var libraryTracks: [Track]
    @State private var currentTrack: Track
    @State private var favorites: Set<String> = []
    @State private var noteworthyKeys: [String] = []
    @State private var showingNoteworthy = false
    @State private var settingsLoaded = false
    @State private var isLoadingLibrary = true
    @State private var showingPlayer = false
    @State private var playerDetent: PresentationDetent = .medium
    @State private var isSeeking = false
    @State private var seekPreviewProgress: Double = 0
    @State private var showingSettings = false
    @State private var albumSheet: AlbumSheet?
    @State private var searchText = ""
    @State private var audioQuality = "All qualities"
    @State private var equalizerPreset = "Flat"
    @State private var playerBackground = Color(uiColor: .systemGroupedBackground)
    @StateObject private var playback = ConcertPlayback()

    private var tracks: [Track] {
        guard audioQuality != "All qualities" else { return libraryTracks }
        return libraryTracks.filter { $0.quality == audioQuality.uppercased() }
    }
    private var albums: [AlbumCollection] {
        makeAlbums(from: tracks)
    }
    private var allLibraryAlbums: [AlbumCollection] {
        makeAlbums(from: libraryTracks)
    }
    private func makeAlbums(from source: [Track]) -> [AlbumCollection] {
        Dictionary(grouping: source, by: \.albumID).compactMap { id, albumTracks in
            let ordered = albumTracks.sorted {
                if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
                if $0.trackNumber != $1.trackNumber { return $0.trackNumber < $1.trackNumber }
                let qualityRank: (String) -> Int = { quality in
                    if quality.localizedCaseInsensitiveContains("spatial") { return 3 }
                    if quality.localizedCaseInsensitiveContains("lossless") { return 2 }
                    return 1
                }
                if qualityRank($0.quality) != qualityRank($1.quality) { return qualityRank($0.quality) > qualityRank($1.quality) }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            var seenTitles = Set<String>()
            let uniqueTracks = ordered.filter {
                seenTitles.insert("\($0.discNumber)|\($0.trackNumber)|\($0.title.lowercased())").inserted
            }
            guard let first = uniqueTracks.first else { return nil }
            return AlbumCollection(id: id, title: first.album, artist: first.artist, tracks: uniqueTracks)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var isPlaying: Bool { playback.isPlaying }

    init() {
        _libraryTracks = State(initialValue: [])
        _currentTrack = State(initialValue: loadingTrack)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            discoverView
                .safeAreaInset(edge: .bottom, spacing: 0) { nowPlayingBar }
                .tabItem { Label(ConcertTab.discover.rawValue, systemImage: ConcertTab.discover.symbol) }
                .tag(ConcertTab.discover)
            favoritesView
                .safeAreaInset(edge: .bottom, spacing: 0) { nowPlayingBar }
                .tabItem { Label(ConcertTab.favorites.rawValue, systemImage: ConcertTab.favorites.symbol) }
                .tag(ConcertTab.favorites)
            searchView
                .safeAreaInset(edge: .bottom, spacing: 0) { nowPlayingBar }
                .tabItem { Label(ConcertTab.search.rawValue, systemImage: ConcertTab.search.symbol) }
                .tag(ConcertTab.search)
        }
        .tint(.accentColor)
        .task {
            guard libraryTracks.isEmpty else { return }
            restorePersistedState()
            let loadedTracks = await SongLibrary.load()
            libraryTracks = loadedTracks
            playback.updateLibrary(loadedTracks)
            noteworthyKeys = recordAndOrderNewTracks(loadedTracks)
            if let firstTrack = loadedTracks.first { currentTrack = firstTrack }
            isLoadingLibrary = false
        }
        .sheet(isPresented: $showingPlayer) {
            fullPlayer
                .presentationDetents([.medium, .large], selection: $playerDetent)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSettings) {
            settingsView
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingNoteworthy) {
            noteworthyView
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(playback.$currentTrackID.compactMap { $0 }) { trackID in
            if let track = libraryTracks.first(where: { $0.id == trackID }) {
                withAnimation(.easeInOut(duration: 0.28)) { currentTrack = track }
            }
        }
        .onChange(of: currentTrack.id) { _ in
            withAnimation(.easeInOut(duration: 0.8)) {
                playerBackground = artworkColor(for: currentTrack)
            }
        }
        .onAppear {
            playerBackground = artworkColor(for: currentTrack)
        }
        .onChange(of: audioQuality) { _ in persistSettings() }
        .onChange(of: playback.crossfadeDuration) { _ in persistSettings() }
        .onChange(of: playback.autoplayEnabled) { _ in persistSettings() }
        .onChange(of: equalizerPreset) { preset in
            if let bands = equalizerPresets[preset] { playback.equalizerBandValues = bands }
            persistSettings()
        }
        .onChange(of: playback.equalizerBandValues) { _ in persistSettings() }
        .onChange(of: playback.equalizerPreamp) { _ in persistSettings() }
    }

    private var discoverView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header(title: "Discover", subtitle: "Good music, right on time.")

                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("Discover", action: "See all") {
                        guard !isLoadingLibrary else { return }
                        albumSheet = .all
                    }
                    if isLoadingLibrary {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) { ForEach(0..<3, id: \.self) { _ in skeletonAlbumCard } }
                        }
                    } else if albums.isEmpty {
                        emptyLibraryMessage
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(albums) { album in
                                    Button { albumSheet = .detail(album) } label: { albumCard(album) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("New and noteworthy", action: "See all") { showingNoteworthy = true }
                    if isLoadingLibrary {
                        ForEach(0..<2, id: \.self) { _ in skeletonTrackRow }
                    } else {
                        ForEach(noteworthyTracks.prefix(2)) { track in trackRow(track) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .sheet(item: $albumSheet) { destination in
            Group {
                switch destination {
                case .all:
                    allAlbumsView
                case .detail(let album):
                    albumDetail(album)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var favoritesView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header(title: "Favorites", subtitle: "Your keepers, all in one place.")
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [.pink.opacity(0.8), .purple.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "heart.fill").font(.system(size: 34)).foregroundColor(.white)
                    }
                    .frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Loved Songs").font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("\(favorites.count) songs · Your personal collection").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        let favoriteTracks = tracks.filter { favorites.contains($0.libraryKey) }
                        if let track = favoriteTracks.first ?? tracks.first { play(track, queue: favoriteTracks.isEmpty ? tracks : favoriteTracks) }
                    } label: {
                        Image(systemName: "play.fill").font(.system(size: 15, weight: .bold)).foregroundColor(.white).frame(width: 44, height: 44).background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Divider()
                    VStack(spacing: 4) {
                    if isLoadingLibrary {
                        ForEach(0..<4, id: \.self) { _ in skeletonTrackRow }
                    } else {
                        ForEach(tracks.filter { favorites.contains($0.libraryKey) }) { track in
                            trackRow(track, showFavorite: true)
                        }
                    }
                    if favorites.isEmpty && !isLoadingLibrary {
                        VStack(spacing: 10) {
                            Image(systemName: "heart").font(.system(size: 28)).foregroundColor(.secondary)
                            Text("No favorites yet").font(.headline)
                            Text("Tap the heart beside a song to keep it here.").font(.subheadline).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private var searchView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header(title: "Search", subtitle: "Find your next favorite.")
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Songs, artists, albums", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(13)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                if isLoadingLibrary {
                    ForEach(0..<5, id: \.self) { _ in skeletonTrackRow }
                } else if searchText.isEmpty {
                    Text("TRENDING IN CONCERT")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(.secondary)
                    ForEach(tracks) { track in trackRow(track) }
                } else {
                    let searchableTracks = libraryTracks
                    let results = searchableTracks.filter {
                        $0.title.localizedCaseInsensitiveContains(searchText) ||
                        $0.artist.localizedCaseInsensitiveContains(searchText) ||
                        $0.album.localizedCaseInsensitiveContains(searchText)
                    }
                    if results.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "music.note.list").font(.system(size: 28)).foregroundColor(.secondary)
                            Text("No matches").font(.headline)
                            Text("Try another song, artist, or album.").font(.subheadline).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        Text("\(results.count) \(results.count == 1 ? "RESULT" : "RESULTS")")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundColor(.secondary)
                        ForEach(results) { track in trackRow(track) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private var settingsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Tune Concert to your listening.").font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button { showingSettings = false } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(.secondary)
                            .frame(width: 34, height: 34).background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close settings")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("PLAYBACK").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.2).foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Audio quality", systemImage: "waveform")
                            .font(.system(size: 15, weight: .medium))
                        Picker("Audio quality", selection: $audioQuality) {
                            Text("All").tag("All qualities")
                            Text("Standard").tag("Standard")
                            Text("Lossless").tag("Standard Lossless")
                            Text("Spatial").tag("Full Spatial Lossless")
                        }
                        .pickerStyle(.segmented)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Equalizer", systemImage: "slider.vertical.3")
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                                Picker("Equalizer preset", selection: $equalizerPreset) {
                                    ForEach(equalizerPresets.keys.sorted(), id: \.self) { preset in
                                        Text(preset).tag(preset)
                                    }
                                    Text("Custom").tag("Custom")
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            HStack(alignment: .center, spacing: 2) {
                                ForEach(ConcertPlayback.equalizerFrequencies.indices, id: \.self) { index in
                                    VStack(spacing: 7) {
                                        Text(equalizerBandLabel(index))
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                        Slider(value: equalizerBandBinding(index), in: -12...12)
                                            .rotationEffect(.degrees(-90))
                                            .frame(width: 94, height: 22)
                                            .frame(width: 26, height: 94)
                                        Text(String(format: "%+.0f", playback.equalizerBandValues[index]))
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(height: 11)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.vertical, 4)
                            HStack {
                                Text("10 bands · ±12 dB")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Button("Reset") { resetEqualizer() }
                                    .font(.caption.weight(.semibold))
                            }
                            VStack(spacing: 4) {
                                HStack {
                                    Text("Preamp").font(.caption.weight(.medium))
                                    Spacer()
                                    Text(String(format: "%+.0f dB", playback.equalizerPreamp))
                                        .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                                }
                                Slider(value: $playback.equalizerPreamp, in: -12...12)
                            }
                        }
                        .padding(12)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Crossfade").font(.system(size: 15, weight: .medium))
                                Spacer()
                                Text(playback.crossfadeDuration == 0 ? "Off" : "\(Int(playback.crossfadeDuration)) sec")
                                    .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                            }
                            Slider(value: $playback.crossfadeDuration, in: 0...12, step: 1)
                            Text("Blend the end of a song into the next.").font(.caption).foregroundColor(.secondary)
                        }
                        Toggle(isOn: $playback.autoplayEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Autoplay").font(.system(size: 15, weight: .medium))
                                Text(playback.autoplayEnabled ? "The next library song starts automatically." : "Playback stops at the end of a song.").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.accentColor)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private var noteworthyTracks: [Track] {
        let indexed = Dictionary(uniqueKeysWithValues: libraryTracks.map { ($0.libraryKey, $0) })
        let ordered = noteworthyKeys.compactMap { indexed[$0] }
        return ordered.isEmpty ? libraryTracks.shuffled() : ordered
    }

    private var noteworthyView: some View {
        NavigationView {
            List(noteworthyTracks) { track in
                trackRow(track, queue: noteworthyTracks)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .navigationTitle("New and noteworthy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingNoteworthy = false }
                }
            }
        }
    }

    private func restorePersistedState() {
        let favoritesRequest = NSFetchRequest<NSManagedObject>(entityName: "FavoriteSong")
        if let records = try? viewContext.fetch(favoritesRequest) {
            favorites = Set(records.compactMap { $0.value(forKey: "trackKey") as? String })
        }

        let settingsRequest = NSFetchRequest<NSManagedObject>(entityName: "AppSettings")
        settingsRequest.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        settingsRequest.fetchLimit = 1
        if let settings = try? viewContext.fetch(settingsRequest).first {
            audioQuality = settings.value(forKey: "audioQuality") as? String ?? "All qualities"
            playback.crossfadeDuration = settings.value(forKey: "crossfadeDuration") as? Double ?? 0
            playback.autoplayEnabled = settings.value(forKey: "autoplayEnabled") as? Bool ?? false
            playback.equalizerPreamp = settings.value(forKey: "equalizerPreamp") as? Double ?? 0
            equalizerPreset = settings.value(forKey: "equalizerPreset") as? String ?? "Flat"
            if let savedBands = settings.value(forKey: "equalizerBandValues") as? String {
                let values = savedBands.split(separator: ",").compactMap { Double($0) }
                if values.count == ConcertPlayback.equalizerFrequencies.count {
                    playback.equalizerBandValues = values
                }
            } else if let presetBands = equalizerPresets[equalizerPreset] {
                playback.equalizerBandValues = presetBands
            }
        }
        settingsLoaded = true
    }

    private func persistSettings() {
        guard settingsLoaded else { return }
        let request = NSFetchRequest<NSManagedObject>(entityName: "AppSettings")
        request.predicate = NSPredicate(format: "recordKey == %@", "default")
        request.fetchLimit = 1
        let record = (try? viewContext.fetch(request).first) ?? NSEntityDescription.insertNewObject(forEntityName: "AppSettings", into: viewContext)
        record.setValue("default", forKey: "recordKey")
        record.setValue(audioQuality, forKey: "audioQuality")
        record.setValue(playback.crossfadeDuration, forKey: "crossfadeDuration")
        record.setValue(playback.autoplayEnabled, forKey: "autoplayEnabled")
        record.setValue(equalizerPreset, forKey: "equalizerPreset")
        record.setValue(playback.equalizerBandValues.map { String(format: "%.2f", $0) }.joined(separator: ","), forKey: "equalizerBandValues")
        record.setValue(playback.equalizerPreamp, forKey: "equalizerPreamp")
        record.setValue(Date(), forKey: "updatedAt")
        saveContext()
    }

    private func recordAndOrderNewTracks(_ tracks: [Track]) -> [String] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "LibraryTrackRecord")
        let existingRecords = (try? viewContext.fetch(request)) ?? []
        var firstSeen = [String: Date]()
        for record in existingRecords {
            if let key = record.value(forKey: "trackKey") as? String,
               let date = record.value(forKey: "firstSeenAt") as? Date,
               firstSeen[key] == nil {
                firstSeen[key] = date
            }
        }
        let now = Date()
        for track in tracks where firstSeen[track.libraryKey] == nil {
            let record = NSEntityDescription.insertNewObject(forEntityName: "LibraryTrackRecord", into: viewContext)
            record.setValue(track.libraryKey, forKey: "trackKey")
            record.setValue(now, forKey: "firstSeenAt")
            firstSeen[track.libraryKey] = now
        }
        saveContext()

        let grouped = Dictionary(grouping: tracks, by: { Calendar.current.startOfDay(for: firstSeen[$0.libraryKey] ?? now) })
        return grouped.keys.sorted(by: >).flatMap { day in
            (grouped[day] ?? []).shuffled().map(\.libraryKey)
        }
    }

    private func saveContext() {
        guard viewContext.hasChanges else { return }
        do { try viewContext.save() }
        catch { NSLog("Concert Core Data save failed: %@", error.localizedDescription) }
    }

    private func equalizerBandBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { playback.equalizerBandValues[index] },
            set: { value in
                equalizerPreset = "Custom"
                playback.equalizerBandValues[index] = value
            }
        )
    }

    private func equalizerBandLabel(_ index: Int) -> String {
        ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"][index]
    }

    private func selectEqualizerPreset(_ preset: String) {
        guard let bands = equalizerPresets[preset] else { return }
        equalizerPreset = preset
        playback.equalizerBandValues = bands
    }

    private func resetEqualizer() {
        selectEqualizerPreset("Flat")
        playback.equalizerPreamp = 0
    }

    private var nowPlayingBar: some View {
        HStack(spacing: 12) {
            if isLoadingLibrary {
                Circle().fill(Color(uiColor: .tertiarySystemFill)).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(width: 124, height: 11)
                    Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(width: 82, height: 9)
                }
                Spacer()
                Circle().fill(Color(uiColor: .tertiarySystemFill)).frame(width: 28, height: 28)
                Circle().fill(Color(uiColor: .tertiarySystemFill)).frame(width: 28, height: 28)
            } else {
                Button { showingPlayer = true } label: {
                    HStack(spacing: 12) {
                        artwork(currentTrack, size: 44)
                            .id(currentTrack.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                            .animation(.easeInOut(duration: 0.28), value: currentTrack.id)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(currentTrack.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.primary).lineLimit(1).contentTransition(.opacity)
                            Text(currentTrack.artist).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1).contentTransition(.opacity)
                        }
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open now playing")
                Spacer(minLength: 4)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    AirPlayRouteButton().frame(width: 38, height: 40)
                    Button { playback.togglePlayback(currentTrack: currentTrack, queue: tracks) } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 19, weight: .semibold)).foregroundColor(.primary).frame(width: 38, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")
                    Button { playback.next() } label: {
                        Image(systemName: "forward.end.fill").font(.system(size: 17)).foregroundColor(.primary).frame(width: 38, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next track")
                }
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                let progress = !isLoadingLibrary && playback.duration > 0 ? playback.currentTime / playback.duration : 0
                Capsule().fill(Color.accentColor).frame(width: proxy.size.width * progress, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 4)
    }

    private var fullPlayer: some View {
        GeometryReader { geometry in
            let expansion = min(1, max(0, (geometry.size.height - 360) / 440))
            let artworkSize = min(geometry.size.width * 0.68, max(132, geometry.size.height * (0.36 + expansion * 0.05)))
            ZStack {
                ScrollView(showsIndicators: false) {
                VStack(spacing: 10 + expansion * 8) {
                    artwork(currentTrack, size: artworkSize)
                        .id(currentTrack.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .animation(.easeInOut(duration: 0.3), value: currentTrack.id)
                        .shadow(color: playerBackground.opacity(0.45), radius: 24, y: 14)
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(currentTrack.title).font(.system(size: 23, weight: .bold, design: .rounded)).lineLimit(1).contentTransition(.opacity)
                            Text(currentTrack.artist).font(.system(size: 16)).foregroundColor(.secondary).lineLimit(1).contentTransition(.opacity)
                        }
                        Spacer()
                        Button { toggleFavorite(currentTrack) } label: {
                            Image(systemName: favorites.contains(currentTrack.libraryKey) ? "heart.fill" : "heart")
                                .font(.system(size: 23)).foregroundColor(favorites.contains(currentTrack.libraryKey) ? .pink : .secondary)
                        }.buttonStyle(.plain)
                    }
                    VStack(spacing: 4) {
                        GeometryReader { proxy in
                            let liveProgress = min(1, max(0, playback.currentTime / max(playback.duration, 1)))
                            let progress = isSeeking ? seekPreviewProgress : liveProgress
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.14)).frame(height: 4)
                                Capsule().fill(Color.primary).frame(width: max(4, proxy.size.width * progress), height: 4)
                                Circle().fill(Color(uiColor: .systemBackground)).frame(width: 22, height: 22)
                                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                                    .offset(x: max(0, min(proxy.size.width - 22, proxy.size.width * progress - 11)))
                            }
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isSeeking = true
                                    seekPreviewProgress = max(0, min(1, value.location.x / max(proxy.size.width, 1)))
                                }
                                .onEnded { value in
                                    let progress = max(0, min(1, value.location.x / max(proxy.size.width, 1)))
                                    playback.seek(to: progress * max(playback.duration, 0))
                                    isSeeking = false
                                })
                        }
                        .frame(height: 30)
                        .accessibilityElement()
                        .accessibilityLabel("Playback position")
                        .accessibilityValue(timeString(playback.currentTime))
                        HStack {
                            Text(timeString(playback.currentTime))
                            Spacer()
                            Text(timeString(playback.duration > 0 ? playback.duration : duration(for: currentTrack)))
                        }
                        .font(.caption2).foregroundColor(.secondary)
                    }
                    HStack(spacing: 18 + expansion * 20) {
                        Button { playback.toggleShuffle() } label: {
                            Image(systemName: "shuffle").font(.system(size: 19))
                                .foregroundColor(playback.shuffleEnabled ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(playback.shuffleEnabled ? "Turn shuffle off" : "Turn shuffle on")
                        Button { playback.previous() } label: { Image(systemName: "backward.end.fill").font(.system(size: 26)) }.buttonStyle(.plain)
                        Button { playback.togglePlayback(currentTrack: currentTrack, queue: tracks) } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 52 + expansion * 10))
                        }.buttonStyle(.plain)
                        Button { playback.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 26)) }.buttonStyle(.plain)
                        Button { playback.cycleRepeatMode() } label: {
                            Image(systemName: playback.repeatMode == .one ? "repeat.1" : "repeat").font(.system(size: 19))
                                .foregroundColor(playback.repeatMode == .off ? .secondary : .accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(repeatAccessibilityLabel)
                    }
                    .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 8) {
                            Text("UP NEXT")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            let upcoming = Array(playback.upcomingTracks.prefix(5))
                            if upcoming.isEmpty {
                                Text("End of queue")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(upcoming) { track in
                                    trackRow(track, queue: playback.currentQueue)
                                }
                            }
                    }
                    .padding(.top, 12)
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 18)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                playerAtmosphere
                    .ignoresSafeArea()
            }
        }
    }

    private var playerAtmosphere: some View {
        GeometryReader { backgroundGeometry in
            let audioPulse = CGFloat(playback.audioLevel)
            let darkMode = colorScheme == .dark
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                LinearGradient(
                    colors: [
                        playerBackground.opacity(darkMode ? 0.28 : 0.48),
                        playerBackground.opacity(darkMode ? 0.12 : 0.20),
                        Color(uiColor: .systemGroupedBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle()
                    .fill(playerBackground.opacity(isPlaying ? (darkMode ? 0.24 : 0.18) + playback.audioLevel * 0.34 : 0.08))
                    .frame(width: backgroundGeometry.size.width * 1.25)
                    .blur(radius: 76)
                    .scaleEffect(isPlaying ? 0.94 + audioPulse * 0.46 : 0.88)
                    .offset(
                        x: (isPlaying ? backgroundGeometry.size.width * 0.20 : -backgroundGeometry.size.width * 0.22) + backgroundGeometry.size.width * audioPulse * 0.18,
                        y: (isPlaying ? -backgroundGeometry.size.height * 0.24 : -backgroundGeometry.size.height * 0.12) - backgroundGeometry.size.height * audioPulse * 0.07
                    )
                Circle()
                    .fill(playerBackground.opacity(isPlaying ? (darkMode ? 0.16 : 0.10) + playback.audioLevel * 0.30 : 0.06))
                    .frame(width: backgroundGeometry.size.width * 0.94)
                    .blur(radius: 68)
                    .scaleEffect(isPlaying ? 1.05 - audioPulse * 0.32 : 1.08)
                    .offset(
                        x: (isPlaying ? -backgroundGeometry.size.width * 0.20 : backgroundGeometry.size.width * 0.20) - backgroundGeometry.size.width * audioPulse * 0.16,
                        y: (isPlaying ? backgroundGeometry.size.height * 0.32 : backgroundGeometry.size.height * 0.42) + backgroundGeometry.size.height * audioPulse * 0.08
                    )
                Circle()
                    .fill(Color.accentColor.opacity(isPlaying ? 0.08 + playback.audioLevel * 0.24 : 0.035))
                    .frame(width: backgroundGeometry.size.width * 0.68)
                    .blur(radius: 54)
                    .scaleEffect(isPlaying ? 0.72 + audioPulse * 0.70 : 0.8)
                    .offset(
                        x: (isPlaying ? -backgroundGeometry.size.width * 0.12 : backgroundGeometry.size.width * 0.16) + backgroundGeometry.size.width * audioPulse * 0.22,
                        y: (isPlaying ? -backgroundGeometry.size.height * 0.02 : backgroundGeometry.size.height * 0.08) - backgroundGeometry.size.height * audioPulse * 0.18
                    )
            }
            .allowsHitTesting(false)
            .animation(
                isPlaying
                    ? Animation.easeInOut(duration: 9).repeatForever(autoreverses: true)
                    : Animation.easeOut(duration: 0.7),
                value: isPlaying
            )
            .animation(.easeOut(duration: 0.24), value: playback.audioLevel)
            .animation(.easeInOut(duration: 0.8), value: playerBackground)
            .animation(.easeInOut(duration: 0.5), value: colorScheme)
        }
    }

    private func header(title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-0.6)
                Text(subtitle).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundColor(.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")
        }
    }

    private var repeatAccessibilityLabel: String {
        switch playback.repeatMode {
        case .off: return "Repeat off. Tap to repeat all."
        case .all: return "Repeating all songs. Tap to repeat one."
        case .one: return "Repeating current song. Tap to turn repeat off."
        }
    }

    private func sectionTitle(_ title: String, action: String, perform: @escaping () -> Void = {}) -> some View {
        HStack {
            Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
            Spacer()
            Button(action, action: perform).font(.system(size: 13, weight: .semibold)).foregroundColor(.accentColor)
        }
    }

    private func albumCard(_ album: AlbumCollection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork(album.artworkTrack, size: 148)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(album.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
            Text("\(album.artist) · \(album.tracks.count) songs")
                .font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
        }
        .frame(width: 148, alignment: .leading)
    }

    private var skeletonAlbumCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 148, height: 148)
            Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(width: 124, height: 12)
            Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(width: 92, height: 10)
        }
        .frame(width: 148, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var skeletonTrackRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(width: 158, height: 12)
                Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(width: 104, height: 10)
                Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(width: 68, height: 8)
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .accessibilityHidden(true)
    }

    private var emptyLibraryMessage: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No music found").font(.headline)
            Text("Add audio files to the Songs folder to build your library.")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
    }

    private var allAlbumsView: some View {
        NavigationView {
            List(allLibraryAlbums) { album in
                NavigationLink {
                    albumDetail(album, showCloseButton: false)
                } label: {
                    HStack(spacing: 12) {
                        artwork(album.artworkTrack, size: 54)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            Text("\(album.artist) · \(album.tracks.count) songs")
                                .font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Albums")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { albumSheet = nil }
                }
            }
        }
    }

    private func albumDetail(_ album: AlbumCollection, showCloseButton: Bool = true) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("ALBUM").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.2).foregroundColor(.secondary)
                    Spacer()
                    if showCloseButton {
                        Button { albumSheet = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(.secondary)
                                .frame(width: 34, height: 34).background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close album")
                    }
                }
                HStack(spacing: 18) {
                    artwork(album.artworkTrack, size: 112)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(album.title).font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(album.artist).font(.subheadline).foregroundColor(.secondary)
                        Text("\(album.tracks.count) songs · \(album.discNumbers.count) \(album.discNumbers.count == 1 ? "disc" : "discs")")
                            .font(.caption).foregroundColor(.secondary)
                        Button { play(album.tracks[0], queue: album.tracks) } label: {
                            Label("Play album", systemImage: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Color.accentColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                ForEach(album.discNumbers, id: \.self) { disc in
                    VStack(alignment: .leading, spacing: 8) {
                        if album.discNumbers.count > 1 {
                            Text("DISC \(disc)").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.2).foregroundColor(.secondary)
                        }
                        ForEach(album.tracks.filter { $0.discNumber == disc }) { track in
                            trackRow(track, queue: album.tracks)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 20)
        }
        .background {
            albumAtmosphere(for: album).ignoresSafeArea()
        }
    }

    private func albumAtmosphere(for album: AlbumCollection) -> some View {
        let color = artworkColor(for: album.artworkTrack)
        return GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                LinearGradient(
                    colors: [color.opacity(colorScheme == .dark ? 0.30 : 0.44), color.opacity(0.18), Color(uiColor: .systemGroupedBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(color.opacity(colorScheme == .dark ? 0.20 : 0.14))
                    .frame(width: geometry.size.width * 1.25)
                    .blur(radius: 72)
                    .offset(x: geometry.size.width * 0.24, y: -geometry.size.height * 0.28)
                Circle()
                    .fill(color.opacity(colorScheme == .dark ? 0.13 : 0.10))
                    .frame(width: geometry.size.width * 0.9)
                    .blur(radius: 64)
                    .offset(x: -geometry.size.width * 0.22, y: geometry.size.height * 0.38)
            }
            .animation(.easeInOut(duration: 0.8), value: album.id)
            .allowsHitTesting(false)
        }
    }

    private func trackRow(_ track: Track, showFavorite: Bool = false, queue: [Track]? = nil) -> some View {
        let isCurrentTrack = playback.currentTrackID == track.id
        return HStack(spacing: 12) {
            Button { play(track, queue: queue ?? tracks) } label: { artwork(track, size: 52) }
                .buttonStyle(.plain)
            Button { play(track, queue: queue ?? tracks) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.system(size: 15, weight: .semibold)).foregroundColor(isCurrentTrack ? .accentColor : .primary).lineLimit(1)
                    Text(track.artist).font(.system(size: 12)).foregroundColor(isCurrentTrack ? .accentColor.opacity(0.8) : .secondary).lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: track.quality.localizedCaseInsensitiveContains("spatial") ? "dot.radiowaves.left.and.right" : "waveform")
                        Text(track.quality)
                    }
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.5).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showFavorite {
                Button { toggleFavorite(track) } label: {
                    Image(systemName: favorites.contains(track.libraryKey) ? "heart.fill" : "heart").foregroundColor(.pink).frame(width: 32, height: 40)
                }.buttonStyle(.plain)
            }
            Text(track.duration).font(.caption).foregroundColor(.secondary)
            Button {} label: { Image(systemName: "ellipsis").foregroundColor(.secondary).frame(width: 28, height: 40) }.buttonStyle(.plain)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isCurrentTrack ? Color.accentColor.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeInOut(duration: 0.24), value: isCurrentTrack)
    }

    private func artwork(_ track: Track, size: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [track.tint, track.tint.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().stroke(Color.white.opacity(0.18), lineWidth: size * 0.06).frame(width: size * 0.7, height: size * 0.7)
            Image(systemName: track.artwork).font(.system(size: size * 0.31, weight: .light)).foregroundColor(.white.opacity(0.9))
            let coverImage: UIImage? = {
                if let artworkURL = track.artworkURL, let image = UIImage(contentsOfFile: artworkURL.path) { return image }
                if let artworkData = track.artworkData { return UIImage(data: artworkData) }
                return nil
            }()
            if let coverImage {
                Image(uiImage: coverImage).resizable().scaledToFill().frame(width: size, height: size).clipped()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.13, style: .continuous))
    }

    private func artworkColor(for track: Track) -> Color {
        let image: UIImage?
        if let artworkURL = track.artworkURL, let fileImage = UIImage(contentsOfFile: artworkURL.path) {
            image = fileImage
        } else if let artworkData = track.artworkData {
            image = UIImage(data: artworkData)
        } else {
            image = nil
        }
        guard let cgImage = image?.cgImage else { return track.tint }

        var pixel = [UInt8](repeating: 0, count: 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            ) else { return }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Color(.sRGB, red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255, opacity: 1)
    }

    private func duration(for track: Track) -> TimeInterval {
        let parts = track.duration.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    private func timeString(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func play(_ track: Track) {
        play(track, queue: tracks)
    }

    private func play(_ track: Track, queue: [Track]) {
        withAnimation(.easeInOut(duration: 0.28)) { currentTrack = track }
        playback.play(track, queue: queue)
    }

    private func toggleFavorite(_ track: Track) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "FavoriteSong")
        request.predicate = NSPredicate(format: "trackKey == %@", track.libraryKey)
        request.fetchLimit = 1
        if let existing = (try? viewContext.fetch(request))?.first {
            viewContext.delete(existing)
            favorites.remove(track.libraryKey)
        } else {
            let record = NSEntityDescription.insertNewObject(forEntityName: "FavoriteSong", into: viewContext)
            record.setValue(track.libraryKey, forKey: "trackKey")
            record.setValue(track.title, forKey: "title")
            record.setValue(track.artist, forKey: "artist")
            record.setValue(track.album, forKey: "album")
            record.setValue(track.quality, forKey: "quality")
            record.setValue(Date(), forKey: "createdAt")
            favorites.insert(track.libraryKey)
        }
        saveContext()
    }

}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
