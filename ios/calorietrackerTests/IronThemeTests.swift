import CoreFoundation
import UIKit
import Testing
@testable import calorietracker

struct IronThemeTests {
    @Test func bodyTextPairsClearWCAGAA() {
        let pairs: [(String, UInt, UInt)] = [
            ("textPrimary on canvas", IronTheme.Hex.textPrimary, IronTheme.Hex.canvas),
            ("textPrimary on surface", IronTheme.Hex.textPrimary, IronTheme.Hex.surface),
            ("textPrimary on surfaceRaised", IronTheme.Hex.textPrimary, IronTheme.Hex.surfaceRaised),
            ("textPrimary on blood", IronTheme.Hex.textPrimary, IronTheme.Hex.blood),
            ("textPrimary on bloodPressed", IronTheme.Hex.textPrimary, IronTheme.Hex.bloodPressed),
            ("textSecondary on canvas", IronTheme.Hex.textSecondary, IronTheme.Hex.canvas),
            ("textSecondary on surface", IronTheme.Hex.textSecondary, IronTheme.Hex.surface),
            ("textTertiary on canvas", IronTheme.Hex.textTertiary, IronTheme.Hex.canvas),
            ("textTertiary on surface", IronTheme.Hex.textTertiary, IronTheme.Hex.surface),
            ("textTertiary on surfaceRaised", IronTheme.Hex.textTertiary, IronTheme.Hex.surfaceRaised),
            ("bloodText on canvas", IronTheme.Hex.bloodText, IronTheme.Hex.canvas),
            ("bloodText on surface", IronTheme.Hex.bloodText, IronTheme.Hex.surface),
            ("brass on canvas", IronTheme.Hex.brass, IronTheme.Hex.canvas),
            ("brass on surface", IronTheme.Hex.brass, IronTheme.Hex.surface),
            ("rust on canvas", IronTheme.Hex.rust, IronTheme.Hex.canvas),
            ("rust on surface", IronTheme.Hex.rust, IronTheme.Hex.surface),
            ("olive on canvas", IronTheme.Hex.olive, IronTheme.Hex.canvas),
            ("olive on surface", IronTheme.Hex.olive, IronTheme.Hex.surface),
        ]
        for pair in pairs {
            let ratio = IronTheme.contrastRatio(foreground: pair.1, on: pair.2)
            #expect(ratio >= 4.5, "\(pair.0) is \(ratio)")
        }
    }

    @Test func grainHashStaysInRangeForEverySpeck() {
        for index in 0..<1_600 {
            for salt in [1, 3, 7, 13] {
                let mixed = IronGrainTile.mix(index, salt: salt)
                #expect(mixed >= 0)
                #expect(mixed <= 0x7fff_ffff)
            }
        }
        #expect(IronGrainTile.image.size.width > 0)
        #expect(IronGrainTile.image.size.height > 0)
    }

    @Test func adjustedTokensStayNearTheSpec() {
        #expect(IronTheme.Hex.bloodText == 0xE2464A)
        #expect(IronTheme.Hex.rust == 0xC9642F)
        #expect(IronTheme.Hex.textTertiary == 0x8C867D)
        #expect(IronTheme.Hex.brass == 0xC9A227)
        #expect(IronTheme.Hex.blood == 0xB3121B)
    }
}
