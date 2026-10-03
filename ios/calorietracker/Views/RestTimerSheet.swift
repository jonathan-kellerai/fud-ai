import SwiftUI

/// The logger owns the session. Legacy previews/callers own a private session.
struct RestTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: RestSession
    let defaultSeconds: Int
    private let ownsSession: Bool
    private let next: RestNextSet?
    private let onChange: ((inout LoggedSet) -> Void) -> Void
    private let onStep: (Bool, Int) -> Void
    private let onLog: () -> Void
    private let onSkip: () -> Void

    init(defaultSeconds: Int = 90, initiallyMuted: Bool = false) {
        self.defaultSeconds = defaultSeconds
        _session = State(initialValue: RestSession(driver: RestTimerService(), initiallyMuted: initiallyMuted))
        ownsSession = true
        next = nil
        onChange = { _ in }
        onStep = { _, _ in }
        onLog = {}
        onSkip = {}
    }

    init(session: RestSession, next: RestNextSet? = nil,
         onChange: @escaping ((inout LoggedSet) -> Void) -> Void = { _ in },
         onStep: @escaping (Bool, Int) -> Void = { _, _ in },
         onLog: @escaping () -> Void = {}, onSkip: @escaping () -> Void = {}) {
        defaultSeconds = session.duration
        _session = State(initialValue: session)
        ownsSession = false
        self.next = next
        self.onChange = onChange
        self.onStep = onStep
        self.onLog = onLog
        self.onSkip = onSkip
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    timer(compact: geometry.size.height < 700 || typeSize.isAccessibilitySize)
                }
                ScrollView {
                    if let next {
                        RestNextSetCard(next: next, onChange: onChange, onStep: onStep)
                    } else if !ownsSession {
                        Text("All planned sets complete")
                            .font(.title3.bold()).foregroundStyle(IronTheme.brass)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        quickDurations
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .background(IronTheme.canvas)
        .foregroundStyle(IronTheme.textPrimary)
        .onAppear { session.startIfNeeded(seconds: defaultSeconds) }
        .onDisappear { if ownsSession { session.stop() } }
    }

    private func timer(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REST\(session.rangeLabel.isEmpty ? "" : " · " + session.rangeLabel)")
                .font(.caption.bold()).fontWidth(.condensed).foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                if compact {
                    Text(session.formattedTime).font(.title2.bold().monospacedDigit())
                        .minimumScaleFactor(0.6).lineLimit(1).frame(maxWidth: .infinity, minHeight: 48)
                } else {
                    ZStack {
                        Circle().stroke(IronTheme.hairline, lineWidth: 5)
                        Circle().trim(from: 0, to: 1 - session.progressFraction)
                            .stroke(IronTheme.blood, lineWidth: 5).rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : .easeOut(duration: IronTheme.motionDuration), value: session.remainingSeconds)
                        Text(session.formattedTime).font(.system(size: 36, weight: .black).monospacedDigit())
                    }.frame(width: 112, height: 112)
                }
                timerButton("−15", label: "Subtract 15 seconds") { session.adjust(by: -15) }
                timerButton("+15", label: "Add 15 seconds") { session.adjust(by: 15) }
                Button {
                    if session.isPaused { session.resume() }
                    else if session.isActive { session.pause() }
                    else { session.start(seconds: defaultSeconds) }
                } label: {
                    Image(systemName: session.isPaused || !session.isActive ? "play.fill" : "pause.fill")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(session.isPaused ? "Resume rest" : "Pause rest")
                Button { session.muted.toggle() } label: {
                    Image(systemName: session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(session.muted ? IronTheme.textTertiary : IronTheme.brass)
                    .accessibilityLabel(session.muted ? "Unmute rest cues" : "Mute rest cues")
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    private func timerButton(_ text: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.body.bold().monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private var quickDurations: some View {
        VStack(alignment: .leading) {
            Text("QUICK SET").font(.caption.bold()).fontWidth(.condensed)
            ForEach([60, 90, 120, 180], id: \.self) { seconds in
                Button("\(seconds) s") { session.start(seconds: seconds) }
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    .buttonStyle(IronCompactButtonStyle())
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                if next != nil { onLog() }
                else { session.stop(); dismiss() }
            } label: {
                if let next {
                    ViewThatFits(in: .horizontal) {
                        Text(next.logLabel).fixedSize()
                        Text("Set done · \(LoggerFormatting.load(next.value.weight)) × \(next.value.reps)").fixedSize()
                        Text("Set done").fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                } else {
                    Text(ownsSession ? "Done" : "Finish → list")
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
            }
            .buttonStyle(IronPrimaryButtonStyle())
            .accessibilityLabel(next?.logLabel ?? (ownsSession ? "Done" : "Finish to list"))
            if !ownsSession {
                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        ViewThatFits(in: .horizontal) { Text("Back to list").fixedSize(); Text("List").fixedSize(horizontal: false, vertical: true) }
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(IronCompactButtonStyle()).accessibilityLabel("Back to list")
                    if next != nil {
                        Button(action: onSkip) {
                            ViewThatFits(in: .horizontal) { Text("Skip set").fixedSize(); Text("Skip").fixedSize(horizontal: false, vertical: true) }
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(IronCompactButtonStyle()).accessibilityLabel("Skip set")
                    }
                }
            }
        }.padding().background(IronTheme.canvas)
    }
}
