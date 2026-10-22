import SwiftUI
import UIKit

// MARK: - Workouts theme bridge
// The Workouts exercise library is ported from Delts (github.com/apoorvdarshan/delts).
// Delts styles its views through a small set of `delts*` palette tokens and view
// modifiers; this file re-implements that surface on the Iron & Blood tokens.

extension Color {
    /// Screen background — iron canvas.
    static var workoutBackground: Color { AppColors.appBackground }

    /// Card surface behind rows and hero imagery.
    static var workoutCard: Color { AppColors.appCard }

    /// Elevated panel behind menus.
    static var workoutPanel: Color { IronTheme.surfaceRaised }

    /// Hairline strokes.
    static var workoutHairline: Color { IronTheme.hairline }

    /// Accent text and thin marks.
    static var workoutAccent: Color { IronTheme.bloodText }

    /// Fill companion for bars and pressed states.
    static var workoutSecondaryAccent: Color { IronTheme.blood }

    /// Delts aliased "inferno" to its secondary accent; keep the alias.
    static var workoutInferno: Color { Color.workoutSecondaryAccent }

    /// Strong text.
    static var workoutCharcoal: Color { IronTheme.textPrimary }

    /// Muted/supporting text.
    static var workoutMutedText: Color { IronTheme.textSecondary }

    /// Text/icons rendered on top of the accent fill.
    static var workoutOnAccent: Color { IronTheme.textPrimary }
}

struct WorkoutBackground: View {
    var body: some View {
        Color.workoutBackground
            .ignoresSafeArea()
    }
}

extension View {
    func workoutScreen() -> some View {
        background(WorkoutBackground())
            .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    func workoutLiquidBarSurface(cornerRadius: CGFloat = IronTheme.cardRadius) -> some View {
        modifier(WorkoutLiquidBarSurfaceModifier(cornerRadius: cornerRadius))
    }

    func workoutPressable() -> some View {
        buttonStyle(WorkoutPressableButtonStyle())
    }
}

private struct WorkoutLiquidBarSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Color.workoutPanel, in: shape)
            .overlay(shape.stroke(Color.workoutHairline, lineWidth: 1))
    }
}

struct WorkoutPressableButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled

        configuration.label
            .scaleEffect(isPressed ? 0.975 : 1)
            .opacity(isEnabled ? (isPressed ? 0.90 : 1) : 0.55)
            .animation(.easeOut(duration: 0.14), value: isPressed)
    }
}
