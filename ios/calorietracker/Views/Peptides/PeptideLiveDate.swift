//
//  PeptideLiveDate.swift
//  calorietracker
//
//  Keeps a Peptides screen's "now" current: on appear, when the app becomes
//  active and when the calendar day changes. A fixed reference date (Visual
//  QA) is never replaced.
//

import Combine
import SwiftUI

struct PeptideLiveDateModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var now: Date
    /// True when the screen was given a fixed reference date.
    let isFixed: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                tick()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { tick() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)) { _ in
                tick()
            }
    }

    private func tick() {
        guard !isFixed else { return }
        now = Date()
    }
}

extension View {
    /// Updates `now` with the live date unless `fixed` is true.
    func peptideLiveDate(_ now: Binding<Date>, fixed: Bool) -> some View {
        modifier(PeptideLiveDateModifier(now: now, isFixed: fixed))
    }
}
