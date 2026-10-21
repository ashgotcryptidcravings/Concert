import AVFoundation
import ActivityKit
import Foundation
import GroupActivities
import MediaPlayer
import SwiftUI
import UIKit

struct Track: Identifiable {
    let id: UUID
    let libraryKey: String
    let title: String
    let artist: String
    let album: String
    let duration: String
    let artwork: String
    let tint: Color
    let quality: String
    let audioURL: URL?
    let artworkURL: URL?
    let artworkData: Data?
    let albumID: String
    let discNumber: Int
    let trackNumber: Int

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        duration: String,
        artwork: String,
        tint: Color,
        quality: String,
        albumID: String? = nil,
        discNumber: Int = 1,
        trackNumber: Int = 1,
        audioURL: URL? = nil,
        artworkURL: URL? = nil,
        artworkData: Data? = nil
    ) {
        self.id = id
        if let audioURL {
            let components = audioURL.standardizedFileURL.pathComponents
            if let songsIndex = components.lastIndex(of: "Songs") {
                self.libraryKey = components.dropFirst(songsIndex + 1).joined(separator: "/").lowercased()
            } else {
                self.libraryKey = audioURL.standardizedFileURL.path.lowercased()
            }
        } else {
            self.libraryKey = "\(quality.lowercased())|\(album.lowercased())|\(title.lowercased())"
        }
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artwork = artwork
        self.tint = tint
        self.quality = quality
        self.albumID = albumID ?? "\(artist.lowercased())|\(album.lowercased())"
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.audioURL = audioURL
        self.artworkURL = artworkURL
        self.artworkData = artworkData
    }
}

struct AlbumCollection: Identifiable {
    let id: String
    let title: String
    let artist: String
    let tracks: [Track]

    var artworkTrack: Track { tracks[0] }
    var discNumbers: [Int] { Array(Set(tracks.map(\.discNumber))).sorted() }
}

struct ConcertListeningActivity: GroupActivity {
    let title: String
    let artist: String
    let album: String
    let discNumber: Int
    let trackNumber: Int

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .listenTogether
        metadata.title = "Listen to \(title)"
        metadata.subtitle = "\(artist) · \(album)"
        return metadata
    }
}

private struct ConcertSharePlayState: Codable {
    let title: String
    let artist: String
    let album: String
    let discNumber: Int
    let trackNumber: Int
    let position: TimeInterval
    let isPlaying: Bool
}

enum SongLibrary {
    private static let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aiff", "aif", "caf", "alac", "flac"]
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff"]

    static func load() async -> [Track] {
        guard let songsURL = Bundle.main.resourceURL?.appendingPathComponent("Songs", isDirectory: true),
              let qualities = try? FileManager.default.contentsOfDirectory(at: songsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var tracks: [Track] = []
        for qualityURL in qualities.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let albumFolders = try? FileManager.default.contentsOfDirectory(at: qualityURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for albumFolder in albumFolders.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: albumFolder.path, isDirectory: &isDirectory), isDirectory.boolValue,
                      let albumContents = try? FileManager.default.contentsOfDirectory(at: albumFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                let albumArtwork = albumContents.first { imageExtensions.contains($0.pathExtension.lowercased()) }
                let discFolders = albumContents.compactMap { url -> (URL, Int)? in
                    guard let number = discNumber(in: url.lastPathComponent) else { return nil }
                    return (url, number)
                }.sorted { $0.1 < $1.1 }

                if !discFolders.isEmpty {
                    for (discFolder, discNumber) in discFolders {
                        tracks += await tracksIn(container: discFolder, albumFolder: albumFolder, quality: qualityURL.lastPathComponent, discNumber: discNumber, albumArtwork: albumArtwork)
                    }
                } else {
                    let directAudio = albumContents.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
                    if !directAudio.isEmpty {
                        tracks += await makeTracks(audioFiles: directAudio, songFolder: albumFolder, albumFolder: albumFolder, quality: qualityURL.lastPathComponent, discNumber: 1, albumArtwork: albumArtwork, forceFolderAlbumID: directAudio.count > 1)
                    } else {
                        let songFolders = albumContents.filter { url in
                            var childIsDirectory: ObjCBool = false
                            return FileManager.default.fileExists(atPath: url.path, isDirectory: &childIsDirectory) && childIsDirectory.boolValue
                        }
                        for songFolder in songFolders {
                            tracks += await tracksIn(container: songFolder, albumFolder: albumFolder, quality: qualityURL.lastPathComponent, discNumber: 1, albumArtwork: albumArtwork)
                        }
                    }
                }
            }
        }
        return tracks.sorted {
            if $0.albumID != $1.albumID { return $0.album.localizedStandardCompare($1.album) == .orderedAscending }
            if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
            if $0.trackNumber != $1.trackNumber { return $0.trackNumber < $1.trackNumber }
            if qualityRank($0.quality) != qualityRank($1.quality) { return qualityRank($0.quality) > qualityRank($1.quality) }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private static func tracksIn(container: URL, albumFolder: URL, quality: String, discNumber: Int, albumArtwork: URL?) async -> [Track] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: container, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        let localArtwork = contents.first { imageExtensions.contains($0.pathExtension.lowercased()) }
        let fallbackArtwork = albumArtwork ?? localArtwork
        let audioFiles = contents.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        if !audioFiles.isEmpty {
            return await makeTracks(audioFiles: audioFiles, songFolder: container, albumFolder: albumFolder, quality: quality, discNumber: discNumber, albumArtwork: fallbackArtwork, forceFolderAlbumID: true)
        }

        let trackFolders = contents.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var tracks: [Track] = []
        for trackFolder in trackFolders {
            guard let files = try? FileManager.default.contentsOfDirectory(at: trackFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            let nestedAudio = files.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            tracks += await makeTracks(audioFiles: nestedAudio, songFolder: trackFolder, albumFolder: albumFolder, quality: quality, discNumber: discNumber, albumArtwork: fallbackArtwork, forceFolderAlbumID: true)
        }
        return tracks
    }

    private static func makeTracks(audioFiles: [URL], songFolder: URL, albumFolder: URL, quality: String, discNumber: Int, albumArtwork: URL?, forceFolderAlbumID: Bool) async -> [Track] {
        let orderedFiles = audioFiles.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let songFiles = (try? FileManager.default.contentsOfDirectory(at: songFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let songArtwork = songFolder == albumFolder ? nil : songFiles.first { imageExtensions.contains($0.pathExtension.lowercased()) }
        var tracks: [Track] = []
        for (index, audioURL) in orderedFiles.enumerated() {
            let asset = AVURLAsset(url: audioURL)
            let embeddedTitle = await metadata(.commonIdentifierTitle, in: asset)
            var embeddedArtist = await metadata(.commonIdentifierArtist, in: asset)
            if embeddedArtist == nil {
                embeddedArtist = await metadata(in: asset, matching: ["TPE1", "TPE2", "©ART", "artist"])
            }
            let embeddedAlbum = await metadata(.commonIdentifierAlbumName, in: asset)
            let embeddedArtwork = await artwork(in: asset)
            let assetDuration = try? await asset.load(.duration)
            let durationSeconds = assetDuration?.seconds ?? 0
            let title = embeddedTitle ?? titleFromFilename(audioURL.deletingPathExtension().lastPathComponent)
            let artist = embeddedArtist ?? "Unknown Artist"
            let album = embeddedAlbum ?? albumFolder.lastPathComponent
            let albumID: String
            if forceFolderAlbumID {
                albumID = "folder|\(albumFolder.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            } else {
                albumID = "\(artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            }

            tracks.append(Track(
                id: UUID(),
                title: title,
                artist: artist,
                album: album,
                duration: formatDuration(durationSeconds),
                artwork: "music.note",
                tint: qualityColor(quality),
                quality: quality.uppercased(),
                albumID: albumID,
                discNumber: discNumber,
                trackNumber: trackNumber(audioURL.lastPathComponent) ?? index + 1,
                audioURL: audioURL,
                artworkURL: songArtwork ?? albumArtwork,
                artworkData: embeddedArtwork
            ))
        }
        return tracks
    }

    private static func discNumber(in name: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: "^(?:disc|disk|cd)\\s*[-_ ]*0*(\\d+)\\b", options: [.caseInsensitive]),
              let match = expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let numberRange = Range(match.range(at: 1), in: name) else { return nil }
        return Int(name[numberRange])
    }

    private static func trackNumber(_ name: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: "^\\s*0*(\\d+)(?:\\s*[.\\-_)]|\\s+)", options: []),
              let match = expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let numberRange = Range(match.range(at: 1), in: name) else { return nil }
        return Int(name[numberRange])
    }

    private static func titleFromFilename(_ name: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "^\\s*0*\\d+\\s*[.\\-_)]\\s*", options: []),
              let range = Range(expression.rangeOfFirstMatch(in: name, range: NSRange(name.startIndex..., in: name)), in: name) else { return name }
        let title = name.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? name : title
    }

    private static func metadata(_ identifier: AVMetadataIdentifier, in asset: AVAsset) async -> String? {
        guard let items = try? await asset.load(.commonMetadata),
              let item = items.first(where: { $0.identifier == identifier }) else { return nil }
        return try? await item.load(.stringValue)
    }

    private static func metadata(in asset: AVAsset, matching tokens: [String]) async -> String? {
        guard let formats = try? await asset.load(.availableMetadataFormats) else { return nil }
        for format in formats {
            guard let items = try? await asset.loadMetadata(for: format) else { continue }
            for item in items {
                let identifier = item.identifier?.rawValue.lowercased() ?? ""
                let key = String(describing: item.key).lowercased()
                guard tokens.contains(where: { identifier.contains($0.lowercased()) || key.contains($0.lowercased()) }),
                      let value = try? await item.load(.stringValue),
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                return value
            }
        }
        return nil
    }

    private static func artwork(in asset: AVAsset) async -> Data? {
        if let data = await metadataArtwork(in: asset, commonOnly: true) { return data }
        return await metadataArtwork(in: asset, commonOnly: false)
    }

    private static func metadataArtwork(in asset: AVAsset, commonOnly: Bool) async -> Data? {
        let formats: [AVMetadataFormat]
        if commonOnly {
            formats = [.iTunesMetadata]
        } else {
            guard let loaded = try? await asset.load(.availableMetadataFormats) else { return nil }
            formats = loaded
        }
        for format in formats {
            guard let items = try? await asset.loadMetadata(for: format) else { continue }
            for item in items {
                let identifier = item.identifier?.rawValue.lowercased() ?? ""
                let key = String(describing: item.key).lowercased()
                let isArtwork = identifier.contains("artwork") || identifier.contains("apic") || key.contains("artwork") || key.contains("apic")
                guard isArtwork, let data = try? await item.load(.dataValue), !data.isEmpty else { continue }
                return data
            }
        }
        return nil
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let value = Int(seconds.rounded())
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }

    private static func qualityColor(_ quality: String) -> Color {
        if quality.localizedCaseInsensitiveContains("spatial") { return Color(red: 0.38, green: 0.34, blue: 0.65) }
        if quality.localizedCaseInsensitiveContains("lossless") { return Color(red: 0.19, green: 0.49, blue: 0.43) }
        return Color(red: 0.89, green: 0.46, blue: 0.19)
    }

    private static func qualityRank(_ quality: String) -> Int {
        if quality.localizedCaseInsensitiveContains("spatial") { return 3 }
        if quality.localizedCaseInsensitiveContains("lossless") { return 2 }
        return 1
    }
}

private struct ConcertAudioDeck {
    let node: AVAudioPlayerNode
    let equalizer: AVAudioUnitEQ
    var file: AVAudioFile?
    var seekOffset: TimeInterval = 0
    var scheduleGeneration = 0

    var duration: TimeInterval {
        guard let file else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    func currentTime(in engine: AVAudioEngine) -> TimeInterval {
        guard let file, let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return seekOffset }
        let elapsed = Double(playerTime.sampleTime) / file.processingFormat.sampleRate
        return min(duration, max(0, seekOffset + elapsed))
    }
}

final class ConcertPlayback: ObservableObject {
    static let equalizerFrequencies: [Float] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTrackID: UUID?
    let metrics = ConcertPlaybackMetrics()
    var currentTime: TimeInterval {
        get { metrics.currentTime }
        set { metrics.currentTime = newValue }
    }
    var duration: TimeInterval {
        get { metrics.duration }
        set { metrics.duration = newValue }
    }
    var audioLevel: Double {
        get { metrics.audioLevel }
        set { metrics.audioLevel = newValue }
    }
    private var lastAudioLevelUpdate: UInt64 = 0
    @Published var crossfadeDuration: Double = 0
    @Published var autoplayEnabled = false
    @Published var equalizerBandValues = Array(repeating: 0.0, count: 10) {
        didSet { applyEqualizerSettings() }
    }
    @Published var equalizerPreamp = 0.0 {
        didSet { applyEqualizerSettings() }
    }
    @Published private(set) var shuffleEnabled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var sharePlayActive = false
    @Published var sharePlayError: String?

    private var queue: [Track] = []
    private var originalQueue: [Track] = []
    private var library: [Track] = []
    private var activeTrack: Track?
    private var groupSession: GroupSession<ConcertListeningActivity>?
    private var groupMessenger: GroupSessionMessenger?
    private var sharePlayReceiveTask: Task<Void, Never>?
    private var applyingSharePlayState = false
    private var lastSharePlaySyncInterval = -1
    private var queueIndex = 0
    private let audioEngine = AVAudioEngine()
    private var decks: [ConcertAudioDeck] = []
    private var activeDeckIndex: Int?
    private var incomingDeckIndex: Int?
    private var progressTimer: Timer?
    private var fadeTimer: Timer?
    private var fadeElapsed: Double = 0
    private var liveActivity: Activity<ConcertNowPlayingAttributes>?

    enum RepeatMode {
        case off, all, one
    }

    var currentQueue: [Track] { queue }
    var upcomingTracks: [Track] {
        guard !queue.isEmpty else { return [] }
        if repeatMode == .one { return [queue[queueIndex]] }
        let following = Array(queue.dropFirst(min(queueIndex + 1, queue.count)))
        return repeatMode == .all ? following + Array(queue.prefix(queueIndex)) : following
    }

    func addToQueue(_ track: Track) {
        guard !queue.contains(where: { $0.id == track.id }) else { return }
        queue.append(track)
        if !originalQueue.contains(where: { $0.id == track.id }) {
            originalQueue.append(track)
        }
    }

    func removeFromQueue(_ track: Track) {
        guard track.id != currentTrackID,
              let index = queue.firstIndex(where: { $0.id == track.id }) else { return }
        queue.remove(at: index)
        originalQueue.removeAll { $0.id == track.id }
        if index < queueIndex {
            queueIndex -= 1
        }
    }

    func updateLibrary(_ tracks: [Track]) {
        library = tracks
        if queue.isEmpty {
            queue = tracks
            originalQueue = tracks
        }
    }

    init() {
        configureAudioGraph()
        configureRemoteCommands()
        observeSharePlaySessions()
    }

    private func configureAudioGraph() {
        for _ in 0..<2 {
            let node = AVAudioPlayerNode()
            let equalizer = AVAudioUnitEQ(numberOfBands: Self.equalizerFrequencies.count)
            audioEngine.attach(node)
            audioEngine.attach(equalizer)
            for (index, band) in equalizer.bands.enumerated() {
                band.filterType = .parametric
                band.frequency = Self.equalizerFrequencies[index]
                band.bandwidth = 1.0
                band.gain = 0
                band.bypass = false
            }
            audioEngine.connect(node, to: equalizer, format: nil)
            audioEngine.connect(equalizer, to: audioEngine.mainMixerNode, format: nil)
            decks.append(ConcertAudioDeck(node: node, equalizer: equalizer))
        }
        applyEqualizerSettings()
        audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 2_048, format: nil) { [weak self] buffer, _ in
            guard let self, let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now &- self.lastAudioLevelUpdate >= 100_000_000 else { return }
            self.lastAudioLevelUpdate = now
            let channelCount = Int(buffer.format.channelCount)
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for frame in 0..<frameCount { sum += samples[frame] * samples[frame] }
            }
            let rms = sqrt(sum / Float(max(1, channelCount * frameCount)))
            let level = min(1, max(0, (Double(20 * log10(max(rms, 0.000_01))) + 55) / 50))
            DispatchQueue.main.async {
                self.metrics.audioLevel = self.metrics.audioLevel * 0.6 + level * 0.4
            }
        }
    }

    private func applyEqualizerSettings() {
        for deck in decks {
            deck.equalizer.globalGain = Float(min(12, max(-12, equalizerPreamp)))
            for (index, band) in deck.equalizer.bands.enumerated() where index < equalizerBandValues.count {
                band.gain = Float(min(12, max(-12, equalizerBandValues[index])))
            }
        }
    }

    func startSharePlay() {
        guard let track = activeTrack else { return }
        let activity = ConcertListeningActivity(
            title: track.title,
            artist: track.artist,
            album: track.album,
            discNumber: track.discNumber,
            trackNumber: track.trackNumber
        )
        Task {
            do {
                _ = try await activity.activate()
            } catch {
                sharePlayError = error.localizedDescription
            }
        }
    }

    private func observeSharePlaySessions() {
        Task {
            for await session in ConcertListeningActivity.sessions() {
                groupSession = session
                sharePlayActive = true
                session.join()
                let messenger = GroupSessionMessenger(session: session)
                groupMessenger = messenger
                sharePlayReceiveTask?.cancel()
                sharePlayReceiveTask = Task {
                    for await (message, _) in messenger.messages(of: ConcertSharePlayState.self) {
                        applySharePlayState(message)
                    }
                }
                publishSharePlayState()
            }
        }
    }

    private func publishSharePlayState() {
        guard !applyingSharePlayState, let messenger = groupMessenger, let track = activeTrack else { return }
        let state = ConcertSharePlayState(
            title: track.title,
            artist: track.artist,
            album: track.album,
            discNumber: track.discNumber,
            trackNumber: track.trackNumber,
            position: currentTime,
            isPlaying: isPlaying
        )
        Task { try? await messenger.send(state) }
    }

    private func applySharePlayState(_ state: ConcertSharePlayState) {
        let source = queue.isEmpty ? library : queue
        guard let track = source.first(where: {
            $0.title == state.title && $0.artist == state.artist && $0.album == state.album &&
            $0.discNumber == state.discNumber && $0.trackNumber == state.trackNumber
        }) else { return }
        applyingSharePlayState = true
        if currentTrackID != track.id {
            let configuredCrossfade = crossfadeDuration
            crossfadeDuration = 0
            play(track, queue: source)
            crossfadeDuration = configuredCrossfade
        }
        seek(to: state.position)
        if state.isPlaying != isPlaying { togglePlayback() }
        applyingSharePlayState = false
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            guard let self, self.activeTrack != nil else { return .commandFailed }
            if !self.isPlaying { self.togglePlayback() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.activeTrack != nil else { return .commandFailed }
            if self.isPlaying { self.togglePlayback() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.activeTrack != nil else { return .commandFailed }
            self.togglePlayback()
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.nextQueueIndex != nil else { return .noSuchContent }
            self.next()
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, !self.queue.isEmpty else { return .noSuchContent }
            self.previous()
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }
    }

    func play(_ track: Track, queue: [Track]) {
        guard track.audioURL != nil else { return }
        originalQueue = queue
        self.queue = shuffleEnabled ? shuffledQueue(queue, keeping: track) : queue
        queueIndex = self.queue.firstIndex(where: { $0.id == track.id }) ?? 0

        if isPlaying, activeDeckIndex != nil, currentTrackID != track.id {
            beginCrossfade(to: queueIndex, duration: 0.22)
        } else {
            start(track)
        }
    }

    func togglePlayback() {
        guard let activeDeckIndex else { return }
        if isPlaying {
            progressTimer?.invalidate()
            decks[activeDeckIndex].node.pause()
            if let incomingDeckIndex { decks[incomingDeckIndex].node.pause() }
            isPlaying = false
            audioLevel = 0
            updateNowPlayingInfo()
            publishSharePlayState()
        } else {
            if currentTime >= duration {
                seek(to: 0)
            }
            startAudioEngineIfNeeded()
            decks[activeDeckIndex].node.play()
            if let incomingDeckIndex { decks[incomingDeckIndex].node.play() }
            isPlaying = true
            startProgressTimer()
            updateNowPlayingInfo()
            publishSharePlayState()
        }
    }

    func togglePlayback(currentTrack: Track, queue: [Track]) {
        guard activeDeckIndex != nil else {
            play(currentTrack, queue: queue)
            return
        }
        togglePlayback()
    }

    func seek(to time: TimeInterval) {
        guard let activeDeckIndex, let activeTrack else { return }
        if let incomingDeckIndex {
            fadeTimer?.invalidate()
            decks[incomingDeckIndex].node.stop()
            decks[incomingDeckIndex].file = nil
            self.incomingDeckIndex = nil
            decks[activeDeckIndex].node.volume = 1
        }
        let target = min(max(0, time), max(0, duration - 0.01))
        let shouldResume = isPlaying
        decks[activeDeckIndex].node.stop()
        guard schedule(activeTrack, on: activeDeckIndex, from: target) else { return }
        startAudioEngineIfNeeded()
        if shouldResume { decks[activeDeckIndex].node.play() }
        currentTime = target
        updateNowPlayingInfo()
        publishSharePlayState()
    }

    func next() {
        guard let nextIndex = nextQueueIndex else { return }
        transition(to: nextIndex)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        let previousIndex = max(0, queueIndex - 1)
        transition(to: previousIndex)
    }

    private func transition(to index: Int) {
        guard queue.indices.contains(index) else { return }
        if isPlaying, activeDeckIndex != nil, index != queueIndex {
            beginCrossfade(to: index, duration: 0.22)
        } else {
            start(queue[index])
        }
    }

    func toggleShuffle() {
        guard !queue.isEmpty else { shuffleEnabled.toggle(); return }
        let currentID = currentTrackID
        shuffleEnabled.toggle()
        if shuffleEnabled {
            queue = shuffledQueue(originalQueue.isEmpty ? queue : originalQueue, keeping: currentID.flatMap { id in queue.first { $0.id == id } })
        } else {
            queue = originalQueue.isEmpty ? queue : originalQueue
        }
        queueIndex = currentID.flatMap { id in queue.firstIndex { $0.id == id } } ?? 0
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    private var nextQueueIndex: Int? {
        if repeatMode == .one { return queueIndex }
        if queueIndex + 1 < queue.count { return queueIndex + 1 }
        if repeatMode == .all { return queue.isEmpty ? nil : 0 }
        return nil
    }

    private func shuffledQueue(_ source: [Track], keeping current: Track?) -> [Track] {
        guard let current, let index = source.firstIndex(where: { $0.id == current.id }) else { return source.shuffled() }
        return [current] + source.enumerated().filter { $0.offset != index }.map(\.element).shuffled()
    }

    private func audioDeckDidFinish(_ deckIndex: Int, generation: Int) {
        guard decks.indices.contains(deckIndex), decks[deckIndex].scheduleGeneration == generation,
              deckIndex == activeDeckIndex, incomingDeckIndex == nil else { return }
        if repeatMode == .one {
            seek(to: 0)
            if !isPlaying { togglePlayback() }
            return
        }
        guard let nextIndex = nextQueueIndex,
              autoplayEnabled || repeatMode == .all || crossfadeDuration > 0 else {
            isPlaying = false
            progressTimer?.invalidate()
            currentTime = duration
            updateNowPlayingInfo()
            publishSharePlayState()
            return
        }
        start(queue[nextIndex])
    }

    private func start(_ track: Track) {
        guard track.audioURL != nil else { return }
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        try? audioSession.setActive(true)
        progressTimer?.invalidate()
        fadeTimer?.invalidate()
        for deck in decks { deck.node.stop() }
        incomingDeckIndex = nil
        let deckIndex = activeDeckIndex ?? 0
        guard schedule(track, on: deckIndex, from: 0) else { return }
        for index in decks.indices where index != deckIndex { decks[index].file = nil }
        activeDeckIndex = deckIndex
        decks[deckIndex].node.volume = 1
        startAudioEngineIfNeeded()
        activeTrack = track
        currentTrackID = track.id
        currentTime = 0
        duration = decks[deckIndex].duration
        queueIndex = queue.firstIndex(where: { $0.id == track.id }) ?? queueIndex
        lastSharePlaySyncInterval = -1
        decks[deckIndex].node.play()
        isPlaying = true
        updateNowPlayingInfo()
        publishSharePlayState()
        startProgressTimer()
    }

    private func schedule(_ track: Track, on deckIndex: Int, from time: TimeInterval) -> Bool {
        guard decks.indices.contains(deckIndex), let url = track.audioURL,
              let file = try? AVAudioFile(forReading: url) else { return false }
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(min(Double(file.length), max(0, time * sampleRate)))
        let remainingFrames = file.length - startFrame
        guard remainingFrames > 0 else { return false }
        decks[deckIndex].scheduleGeneration += 1
        let generation = decks[deckIndex].scheduleGeneration
        decks[deckIndex].file = file
        decks[deckIndex].seekOffset = Double(startFrame) / sampleRate
        decks[deckIndex].node.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.audioDeckDidFinish(deckIndex, generation: generation) }
        }
        return true
    }

    private func startAudioEngineIfNeeded() {
        guard !audioEngine.isRunning else { return }
        do {
            try audioEngine.start()
        } catch {
            NSLog("Concert audio engine failed to start: %@", error.localizedDescription)
        }
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying, let activeDeckIndex = self.activeDeckIndex else { return }
            self.currentTime = self.decks[activeDeckIndex].currentTime(in: self.audioEngine)
            self.duration = self.decks[activeDeckIndex].duration
            if self.groupMessenger != nil {
                let syncInterval = Int(self.currentTime / 10)
                if syncInterval != self.lastSharePlaySyncInterval {
                    self.lastSharePlaySyncInterval = syncInterval
                    self.publishSharePlayState()
                }
            }
            guard self.incomingDeckIndex == nil,
                  self.crossfadeDuration > 0, let nextIndex = self.nextQueueIndex, nextIndex != self.queueIndex,
                  self.duration - self.currentTime <= self.crossfadeDuration else { return }
            self.beginCrossfade(to: nextIndex, duration: max(0.1, self.duration - self.currentTime))
        }
    }

    private func beginCrossfade(to index: Int, duration: Double) {
        guard queue.indices.contains(index), let activeDeckIndex,
              queue[index].audioURL != nil else { return }
        fadeTimer?.invalidate()
        if let incomingDeckIndex {
            decks[incomingDeckIndex].node.stop()
            decks[incomingDeckIndex].file = nil
            self.incomingDeckIndex = nil
            decks[activeDeckIndex].node.volume = 1
        }
        let incomingDeckIndex = 1 - activeDeckIndex
        guard schedule(queue[index], on: incomingDeckIndex, from: 0) else { return }
        let incomingDuration = decks[incomingDeckIndex].duration
        let outgoingRemaining = max(0.1, self.duration - currentTime)
        let fadeDuration = max(0.1, min(duration, outgoingRemaining, incomingDuration))
        decks[incomingDeckIndex].node.volume = 0
        self.incomingDeckIndex = incomingDeckIndex
        startAudioEngineIfNeeded()
        fadeElapsed = 0
        decks[incomingDeckIndex].node.play()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self, let activeDeckIndex = self.activeDeckIndex,
                  let incomingDeckIndex = self.incomingDeckIndex else {
                timer.invalidate()
                return
            }
            self.fadeElapsed += 1.0 / 30.0
            let progress = min(1, self.fadeElapsed / fadeDuration)
            let fadeAngle = progress * .pi / 2
            self.decks[activeDeckIndex].node.volume = Float(cos(fadeAngle))
            self.decks[incomingDeckIndex].node.volume = Float(sin(fadeAngle))
            if progress >= 1 {
                timer.invalidate()
                self.decks[activeDeckIndex].node.stop()
                self.decks[activeDeckIndex].file = nil
                self.decks[incomingDeckIndex].node.volume = 1
                self.activeDeckIndex = incomingDeckIndex
                self.incomingDeckIndex = nil
                self.queueIndex = index
                self.currentTrackID = self.queue[index].id
                self.currentTime = self.decks[incomingDeckIndex].currentTime(in: self.audioEngine)
                self.duration = self.decks[incomingDeckIndex].duration
                self.activeTrack = self.queue[index]
                self.updateNowPlayingInfo()
                self.publishSharePlayState()
                self.startProgressTimer()
            }
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = activeTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        let image: UIImage?
        if let artworkURL = track.artworkURL, let fileImage = UIImage(contentsOfFile: artworkURL.path) {
            image = fileImage
        } else if let artworkData = track.artworkData, let embeddedImage = UIImage(data: artworkData) {
            image = embeddedImage
        } else {
            image = nil
        }
        if let image {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        updateLiveActivity()
    }

    private func updateLiveActivity() {
        guard let track = activeTrack, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ConcertNowPlayingAttributes(trackIdentifier: track.id.uuidString)
        let now = Date()
        let playbackStartedAt = now.addingTimeInterval(-currentTime)
        let state = ConcertNowPlayingAttributes.ContentState(
            title: track.title,
            artist: track.artist,
            album: track.album,
            isPlaying: isPlaying,
            progress: duration > 0 ? min(1, max(0, currentTime / duration)) : 0,
            playbackStartedAt: playbackStartedAt,
            playbackEndsAt: playbackStartedAt.addingTimeInterval(duration)
        )
        let content = ActivityContent(state: state, staleDate: nil)
        if let liveActivity, liveActivity.attributes.trackIdentifier == attributes.trackIdentifier {
            Task { await liveActivity.update(content) }
            return
        }
        if let liveActivity {
            Task { await liveActivity.end(nil, dismissalPolicy: .immediate) }
        }
        do {
            liveActivity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            liveActivity = nil
        }
    }
}

final class ConcertPlaybackMetrics: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var audioLevel: Double = 0
}

