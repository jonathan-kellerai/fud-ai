import SwiftUI

/// Progress ring: a blood arc on a hairline track.
struct ChallengeRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(IronTheme.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(IronTheme.blood, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// Cumulative progress as a polyline. `points` are 0...1 shares of the goal, one per elapsed day.
struct PaceChartShape: Shape {
    let points: [Double]
    let totalDays: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard totalDays > 0, !points.isEmpty else { return path }
        let step = rect.width / CGFloat(totalDays)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (index, value) in points.enumerated() {
            let x = rect.minX + step * CGFloat(index + 1)
            let y = rect.maxY - rect.height * CGFloat(value)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

/// The straight line a perfectly paced challenge would follow.
struct PaceTargetShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct ChallengePaceChart: View {
    let progress: ChallengeProgress
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 120

    var body: some View {
        ZStack {
            PaceTargetShape()
                .stroke(IronTheme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            PaceChartShape(points: ChallengePresentation.paceSeries(progress), totalDays: progress.durationDays)
                .stroke(IronTheme.bloodText, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .frame(height: height)
        .padding(12)
        .ironCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pace chart. \(ChallengePresentation.percent(progress.fraction)) of the goal on day \(progress.dayIndex).")
    }
}

/// One square per window day: hit, miss, grace, today, future.
struct ChallengeDayGrid: View {
    let progress: ChallengeProgress
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(progress.dayStates.enumerated()), id: \.offset) { _, state in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill(state))
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(state == .pending ? IronTheme.brass : IronTheme.hairline, lineWidth: 1)
                    }
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(12)
        .ironCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChallengePresentation.gridSummary(progress))
    }

    private func fill(_ state: ChallengeDayState) -> Color {
        switch state {
        case .hit: IronTheme.olive
        case .miss: IronTheme.blood
        case .grace: IronTheme.rust.opacity(IronTheme.borderTintOpacity)
        case .pending: IronTheme.surfaceRaised
        case .future: IronTheme.surface
        }
    }
}

extension IronStatusPill.Tone {
    init(_ status: ChallengeStatus) {
        switch status {
        case .onTrack: self = .olive
        case .behind: self = .rust
        case .complete: self = .brass
        case .failed: self = .blood
        case .ended, .notStarted, .noData, .invalid: self = .neutral
        }
    }
}

/// Compact row used by the list and the Home card.
struct ChallengeSummaryRow: View {
    let challenge: Challenge
    let progress: ChallengeProgress?
    let now: Date
    let calendar: Calendar
    @ScaledMetric(relativeTo: .body) private var ringSide: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            ChallengeRing(fraction: progress?.fraction ?? 0, lineWidth: 5)
                .frame(width: ringSide, height: ringSide)
            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title)
                    .font(.headline.weight(.heavy))
                    .fontWidth(.condensed)
                    .foregroundStyle(IronTheme.textPrimary)
                if let progress {
                    Text(ChallengePresentation.dayLabel(progress, challenge: challenge, now: now, calendar: calendar))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(IronTheme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let progress {
                IronStatusPill(
                    text: ChallengePresentation.statusLabel(progress.status, metric: challenge.metric),
                    tone: IronStatusPill.Tone(progress.status)
                )
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// Clear overlay so visual QA can measure a control's hit area.
extension View {
    func challengeHitAnchor(_ identifier: String) -> some View {
        overlay {
            SettingsHubRowAnchor(identifier: identifier)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }
}
