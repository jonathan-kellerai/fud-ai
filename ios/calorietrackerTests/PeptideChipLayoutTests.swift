import SwiftUI
import Testing
import UIKit
@testable import calorietracker

/// Peptide choice chips (compound, unit, syringe scale): text scales with
/// Dynamic Type, every chip is at least 44 pt tall, and a long title wraps
/// inside an iPhone SE row at AX5 instead of running off it.
///
/// xcodebuild test -project ios/calorietracker.xcodeproj -scheme calorietracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:calorietrackerTests/PeptideChipLayoutTests CODE_SIGNING_ALLOWED=NO
@MainActor
struct PeptideChipLayoutTests {
    /// iPhone SE width less the 16 pt screen padding on each side.
    private let seRowWidth: CGFloat = 288

    private func size(
        title: String,
        subtitle: String? = nil,
        dynamicType: DynamicTypeSize,
        width: CGFloat = 288
    ) -> CGSize {
        let chip = PeptideChoiceChip(title: title, subtitle: subtitle, selected: false) {}
            .environment(\.dynamicTypeSize, dynamicType)
        let host = UIHostingController(rootView: chip)
        return host.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    }

    @Test func everyChipIsAtLeast44PointsTall() {
        for dynamicType in [DynamicTypeSize.xSmall, .large, .accessibility1, .accessibility5] {
            #expect(size(title: "mL", dynamicType: dynamicType).height >= 44)
            #expect(size(title: "U-100", subtitle: "1 mL", dynamicType: dynamicType).height >= 44)
        }
    }

    @Test func chipTextGrowsWithDynamicType() {
        let large = size(title: "U-100", dynamicType: .large)
        let ax5 = size(title: "U-100", dynamicType: .accessibility5)
        #expect(ax5.height > large.height)
        #expect(ax5.width > large.width)
    }

    @Test func aLongTitleWrapsInsideAnSERowAtAX5() {
        let title = "BPC-157 and TB-500 blend from the pharmacy"
        let ax5 = size(title: title, subtitle: "Typed from the label", dynamicType: .accessibility5)
        let oneLine = size(title: "BPC", subtitle: "Typed", dynamicType: .accessibility5)
        #expect(ax5.width <= seRowWidth)
        #expect(ax5.height > oneLine.height)
    }
}
