//
//  RestTimerSheet.swift
//  calorietracker
//
//  Rest timer overlay for between sets
//

import SwiftUI

struct RestTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var timer: RestTimerService
    @State private var zeroFlash = false
    @State private var cuesMuted: Bool
    let defaultSeconds: Int
    
    init(defaultSeconds: Int = 90, initiallyMuted: Bool = false) {
        self.defaultSeconds = defaultSeconds
        _timer = State(initialValue: RestTimerService())
        _cuesMuted = State(initialValue: initiallyMuted)
    }

    private var inFinalSeconds: Bool {
        timer.remainingSeconds <= 10
    }
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(IronTheme.hairline, lineWidth: 8)
                    .frame(width: 250, height: 250)
                
                Circle()
                    .trim(from: 0, to: 1.0 - timer.progressFraction)
                    .stroke(
                        inFinalSeconds ? IronTheme.bloodText : IronTheme.blood,
                        style: StrokeStyle(lineWidth: 8, lineCap: .butt)
                    )
                    .frame(width: 250, height: 250)
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 1.0), value: timer.remainingSeconds)
                
                Text(timer.formattedTime)
                    .font(.system(size: 72, weight: .black))
                    .fontWidth(.compressed)
                    .monospacedDigit()
                    .foregroundStyle(inFinalSeconds ? IronTheme.bloodText : IronTheme.textPrimary)
            }
            .frame(height: 280)
            
            HStack(spacing: 20) {
                Button {
                    if timer.isRunning {
                        timer.pause()
                    } else if timer.isPaused {
                        timer.resume()
                    } else {
                        timer.start(seconds: defaultSeconds)
                    }
                } label: {
                    Image(systemName: timer.isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(IronTheme.bloodText)
                }
                
                Button {
                    timer.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(IronTheme.bloodText)
                }
                .disabled(!timer.isRunning && !timer.isPaused)
                
                Button {
                    timer.reset(to: defaultSeconds)
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(IronTheme.textTertiary)
                }

                Button {
                    cuesMuted.toggle()
                    timer.cuesMuted = cuesMuted
                } label: {
                    Image(systemName: cuesMuted ? "speaker.slash.circle.fill" : "speaker.wave.2.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(cuesMuted ? IronTheme.textTertiary : IronTheme.brass)
                }
                .accessibilityLabel(cuesMuted ? "Unmute rest cues" : "Mute rest cues")
            }
            
            VStack(spacing: 12) {
                Text("Quick Set")
                    .font(.system(size: 13, weight: .heavy))
                    .fontWidth(.condensed)
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(IronTheme.textSecondary)
                
                HStack(spacing: 12) {
                    ForEach([60, 90, 120, 180], id: \.self) { seconds in
                        Button {
                            timer.start(seconds: seconds)
                        } label: {
                            Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                                .font(.system(.body, weight: .semibold).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .padding(.horizontal, 4)
                                .frame(maxWidth: 88, minHeight: 44)
                                .foregroundStyle(IronTheme.textPrimary)
                                .background(
                                    timer.totalSeconds == seconds ? IronTheme.blood : IronTheme.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                                        .strokeBorder(IronTheme.hairline, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            
            Spacer()
            
            Button {
                timer.stop()
                dismiss()
            } label: {
                Text("Done")
            }
            .buttonStyle(IronPrimaryButtonStyle())
        }
        .padding()
        .background(zeroFlash ? IronTheme.blood : IronTheme.canvas)
        .foregroundStyle(IronTheme.textPrimary)
        .onAppear {
            timer.cuesMuted = cuesMuted
            timer.start(seconds: defaultSeconds)
        }
        .onDisappear {
            timer.stop()
        }
        .onChange(of: timer.remainingSeconds) { _, seconds in
            guard seconds == 0, !reduceMotion else { return }
            zeroFlash = true
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                zeroFlash = false
            }
        }
    }
}
