import SwiftUI
import AVKit

struct HistoricalFrigateView: View {
    @StateObject var store: HistoricalFrigateStore
    @State private var showingDatePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Video Player
            playerSection
                .frame(maxHeight: .infinity)

            Divider()

            // Timeline
            timelineSection
                .frame(height: 200)

            // Error banner
            if !store.errors.isEmpty {
                errorBanner
            }
        }
        .onAppear {
            store.loadTimeline()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Camera name
            Text(store.camera.name)
                .font(.headline)

            Spacer()

            // Date range button
            Button(action: { showingDatePicker.toggle() }) {
                Label(dateRangeText, systemImage: "calendar")
                    .font(.subheadline)
            }
            .popover(isPresented: $showingDatePicker) {
                DateRangePicker(range: $store.selectedRange, onApply: {
                    store.updateRange(store.selectedRange)
                    showingDatePicker = false
                }, onCancel: {
                    showingDatePicker = false
                })
                .frame(width: 400, height: 300)
            }

            // Auth status
            if store.authService.isAuthenticating {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding()
    }

    // MARK: - Player Section

    private var playerSection: some View {
        ZStack {
            Color.black

            if case .idle = store.playbackState {
                // Idle state
                VStack(spacing: 16) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("Select a time on the timeline to begin playback")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                // Video player
                VideoPlayer(player: store.playbackController.player)
                    .overlay(alignment: .bottom) {
                        playbackControls
                            .padding()
                    }

                // Loading overlay
                if case .loading = store.playbackState {
                    ProgressView("Loading video...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                // Buffering overlay
                if store.playbackController.isBuffering {
                    ProgressView("Buffering...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 20) {
            // Play/Pause
            Button(action: {
                if case .playing = store.playbackState {
                    store.pause()
                } else if case .paused = store.playbackState {
                    store.resume()
                }
            }) {
                Image(systemName: store.playbackState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(!store.playbackState.isPlaying && store.playbackState.currentTime == nil)

            // Current time
            if let currentTime = store.playbackState.currentTime {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .foregroundColor(.white)
                    .monospacedDigit()
            }

            Spacer()

            // Stop button
            Button(action: store.stop) {
                Image(systemName: "stop.circle")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(store.playbackState.currentTime == nil)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Timeline header
            HStack {
                Text("Timeline")
                    .font(.headline)

                Spacer()

                if store.isLoadingTimeline {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                Text("\(store.timelineSegments.count) segments")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // Timeline view
            if store.timelineSegments.isEmpty && !store.isLoadingTimeline {
                VStack {
                    Spacer()
                    Text("No recordings found for this time range")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                SimpleTimelineView(
                    segments: store.timelineSegments,
                    range: store.selectedRange,
                    onSelectTime: { time in
                        store.play(from: time)
                    }
                )
            }
        }
        .padding(.vertical)
    }

    // MARK: - Error Banner

    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(store.errors.enumerated()), id: \.offset) { _, error in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    Text(error.localizedDescription)
                        .font(.caption)

                    Spacer()

                    Button("Dismiss") {
                        store.clearErrors()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(formatter.string(from: store.selectedRange.start)) - \(formatter.string(from: store.selectedRange.end))"
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Date Range Picker

struct DateRangePicker: View {
    @Binding var range: DateInterval
    let onApply: () -> Void
    let onCancel: () -> Void

    @State private var startDate: Date
    @State private var endDate: Date

    init(range: Binding<DateInterval>, onApply: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self._range = range
        self.onApply = onApply
        self.onCancel = onCancel
        self._startDate = State(initialValue: range.wrappedValue.start)
        self._endDate = State(initialValue: range.wrappedValue.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Date Range")
                .font(.headline)

            DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
            DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])

            HStack {
                Button("Last Hour") {
                    endDate = Date()
                    startDate = endDate.addingTimeInterval(-3600)
                }
                .buttonStyle(.bordered)

                Button("Last 24 Hours") {
                    endDate = Date()
                    startDate = endDate.addingTimeInterval(-24 * 3600)
                }
                .buttonStyle(.bordered)

                Button("Last Week") {
                    endDate = Date()
                    startDate = endDate.addingTimeInterval(-7 * 24 * 3600)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }

                Spacer()

                Button("Apply") {
                    range = DateInterval(start: startDate, end: endDate)
                    onApply()
                }
                .buttonStyle(.borderedProminent)
                .disabled(startDate >= endDate)
            }
        }
        .padding()
    }
}

// MARK: - Simple Timeline View

struct SimpleTimelineView: View {
    let segments: [TimelineSegment]
    let range: DateInterval
    let onSelectTime: (Date) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: max(geometry.size.width, totalWidth), height: 100)

                    // Segments
                    ForEach(segments) { segment in
                        SegmentView(segment: segment, range: range, totalWidth: max(geometry.size.width, totalWidth))
                            .onTapGesture {
                                onSelectTime(segment.startTime)
                            }
                    }
                }
                .frame(width: max(geometry.size.width, totalWidth), height: 100)
            }
        }
        .padding(.horizontal)
    }

    private var totalWidth: CGFloat {
        1000 // Minimum width for scrollable timeline
    }
}

struct SegmentView: View {
    let segment: TimelineSegment
    let range: DateInterval
    let totalWidth: CGFloat

    var body: some View {
        Rectangle()
            .fill(segmentColor)
            .frame(width: segmentWidth, height: 80)
            .offset(x: segmentOffset)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
    }

    private var segmentColor: Color {
        if segment.motionScore > 0.5 {
            return Color.blue.opacity(0.7)
        } else if segment.motionScore > 0.2 {
            return Color.blue.opacity(0.4)
        } else {
            return Color.gray.opacity(0.3)
        }
    }

    private var segmentWidth: CGFloat {
        let segmentDuration = segment.duration
        let totalDuration = range.duration
        return (segmentDuration / totalDuration) * totalWidth
    }

    private var segmentOffset: CGFloat {
        let offsetDuration = segment.startTime.timeIntervalSince(range.start)
        let totalDuration = range.duration
        return (offsetDuration / totalDuration) * totalWidth
    }
}
