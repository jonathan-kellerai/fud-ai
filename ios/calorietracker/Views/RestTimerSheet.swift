//
//  RestTimerSheet.swift
//  calorietracker
//
//  Rest timer overlay for between sets
//

import SwiftUI

struct RestTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var timer: RestTimerService
    let defaultSeconds: Int
    
    init(defaultSeconds: Int = 90) {
        self.defaultSeconds = defaultSeconds
        _timer = State(initialValue: RestTimerService())
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Timer Display
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    .frame(width: 250, height: 250)
                
                Circle()
                    .trim(from: 0, to: 1.0 - timer.progressFraction)
                    .stroke(
                        timer.remainingSeconds <= 10 ? Color.red : Color.blue,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 250, height: 250)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0), value: timer.remainingSeconds)
                
                Text(timer.formattedTime)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(height: 280)
            
            // Controls
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
                        .foregroundStyle(.blue)
                }
                
                Button {
                    timer.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.red)
                }
                .disabled(!timer.isRunning && !timer.isPaused)
                
                Button {
                    timer.reset(to: defaultSeconds)
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.gray)
                }
            }
            
            // Preset Buttons
            VStack(spacing: 12) {
                Text("Quick Set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    ForEach([60, 90, 120, 180], id: \.self) { seconds in
                        Button {
                            timer.start(seconds: seconds)
                        } label: {
                            Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .frame(width: 70, height: 40)
                        }
                        .buttonStyle(.bordered)
                        .tint(timer.totalSeconds == seconds ? .blue : .gray)
                    }
                }
            }
            
            Spacer()
            
            // Close Button
            Button {
                timer.stop()
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .onAppear {
            timer.start(seconds: defaultSeconds)
        }
        .onDisappear {
            timer.stop()
        }
    }
}
