import ActivityKit
import Foundation

struct ConcertNowPlayingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var progress: Double
        var playbackStartedAt: Date
        var playbackEndsAt: Date
    }

    var trackIdentifier: String
}
