import SwiftUI

struct LoggerReorderControls: View {
    let name: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("REORDER").font(.caption.bold()).fontWidth(.condensed).foregroundStyle(IronTheme.textSecondary)
            Spacer(minLength: 0)
            Button(action: onMoveUp) {
                Image(systemName: "arrow.up").frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!canMoveUp).accessibilityLabel("Move \(name) up")
            Button(action: onMoveDown) {
                Image(systemName: "arrow.down").frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!canMoveDown).accessibilityLabel("Move \(name) down")
        }.foregroundStyle(IronTheme.brass)
    }
}
