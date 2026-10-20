import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ConcertLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        ConcertNowPlayingLiveActivity()
    }
}

struct ConcertNowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConcertNowPlayingAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 42, height: 42)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                    Text(context.state.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    progressView(for: context.state)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemGroupedBackground))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isPlaying ? "Playing" : "Paused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.state.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        progressView(for: context.state)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text(context.state.title).font(.caption2).lineLimit(1)
            } minimal: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.tint)
            }
            .keylineTint(.accentColor)
        }
    }

    @ViewBuilder
    private func progressView(for state: ConcertNowPlayingAttributes.ContentState) -> some View {
        if state.isPlaying {
            ProgressView(timerInterval: state.playbackStartedAt...state.playbackEndsAt, countsDown: false)
                .tint(.accentColor)
        } else {
            ProgressView(value: state.progress).tint(.accentColor)
        }
    }
}
