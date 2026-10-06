//
//  TodaysWorkoutCard.swift
//  calorietracker
//
//  The Train tab's Today's Workout card: the resolved session, rest day, or
//  upcoming program start, with the Start button and the Change control.
//

import SwiftUI

struct TodaysWorkoutCard: View {
    let resolution: TrainingDayResolution
    let programBody: TrainingProgramBody
    /// The session date the card's week rules and Start use.
    let date: Date
    let bridgeNotice: String?
    let onStart: (TrainingProgramDay) -> Void
    let onChangeWorkout: () -> Void
    let onBackToSuggested: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var plan: ResolvedTrainingDay { resolution.plan }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch plan {
            case .session(_, let name, _):
                sessionCard(name: name, day: TrainingProgramSchedule.programDay(in: programBody, matching: plan))
            case .rest(let stepsTarget, _, _):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rest Day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(stepsTarget.formatted()) steps")
                        .font(.title2.bold())
                    if let nextLabel = plan.nextLabel {
                        Text(nextLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let subtitle = resolution.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(IronTheme.textSecondary)
                    }
                }
            case .upcoming(let name, let weekday, let stepsTarget):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Upcoming")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.title2.bold())
                    Text(weekday)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(stepsTarget.formatted()) steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if resolution.canChange {
                changeControls
            }

            if let bridgeNotice {
                Text(bridgeNotice)
                    .font(.caption)
                    .foregroundStyle(AppColors.calorie)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func sessionCard(name: String, day: TrainingProgramDay?) -> some View {
        let title = VStack(alignment: .leading) {
            Text("Today's Workout")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = resolution.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(resolution.isChanged ? IronTheme.brass : IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let nextLabel = resolution.nextLabel {
                Text(nextLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // At accessibility sizes the Start button no longer fits beside the
        // session name on small phones, so stack it full-width underneath
        // instead of squeezing "Start" into a one-letter-wide column.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                title
                if let day {
                    startButton(day, fullWidth: true)
                }
            }
        } else {
            HStack {
                title
                Spacer(minLength: 12)
                if let day {
                    startButton(day, fullWidth: false)
                }
            }
        }
        if let day {
            let datedDay = programBody.programV2Day(for: day, on: date)
            if let weekNote = datedDay.weekNote {
                Text(weekNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(AppColors.calorie)
                    Text("Conditioning: \(datedDay.conditioning)")
                        .font(.subheadline)
                }
                HStack {
                    Image(systemName: "dumbbell.fill")
                    Text("\(datedDay.exercises.count) exercises")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(.secondary)
        }
    }
    
    private func startButton(_ day: TrainingProgramDay, fullWidth: Bool) -> some View {
        Button {
            onStart(day)
        } label: {
            Label("Start", systemImage: "play.fill")
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: !fullWidth, vertical: false)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(AppColors.calorie)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// Change sits on session and rest cards alike (a rest day can be a makeup
    /// session). At accessibility sizes the buttons stack full-width.
    @ViewBuilder
    private var changeControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                changeButton(fullWidth: true)
                if resolution.isChanged {
                    backToSuggestedButton(fullWidth: true)
                }
            }
        } else {
            HStack(spacing: 12) {
                changeButton(fullWidth: false)
                if resolution.isChanged {
                    backToSuggestedButton(fullWidth: false)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func changeButton(fullWidth: Bool) -> some View {
        Button(action: onChangeWorkout) {
            secondaryLabel("Change", systemImage: "arrow.triangle.2.circlepath", fullWidth: fullWidth)
        }
        .accessibilityLabel("Change workout")
        .accessibilityHint("Pick a different program day for today")
        .accessibilityIdentifier("train.changeWorkout")
    }

    private func backToSuggestedButton(fullWidth: Bool) -> some View {
        Button(action: onBackToSuggested) {
            secondaryLabel("Back to suggested", systemImage: "arrow.uturn.backward", fullWidth: fullWidth)
        }
        .accessibilityHint("Show the next workout in the cycle again")
        .accessibilityIdentifier("train.backToSuggested")
    }

    private func secondaryLabel(_ title: String, systemImage: String, fullWidth: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(IronTheme.bloodText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .overlay {
                RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                    .strokeBorder(IronTheme.hairline, lineWidth: 1)
            }
            .contentShape(Rectangle())
    }
}
