import SwiftUI

struct LoggerRestBar: View {
    let session: RestSession
    let onOpen: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if session.isActive {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        Text(session.formattedTime).font(.headline.monospacedDigit())
                        Text(session.stepLabel).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up")
                    }
                    .foregroundStyle(IronTheme.textPrimary)
                    .padding(.horizontal).frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle()).background(IronTheme.surfaceRaised)
                }.buttonStyle(.plain).accessibilityLabel("Open rest timer, \(session.formattedTime), \(session.stepLabel)")
            }
        }
    }
}
