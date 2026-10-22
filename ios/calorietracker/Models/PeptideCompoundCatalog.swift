//
//  PeptideCompoundCatalog.swift
//  calorietracker
//
//  Compound names the app knows: whether one is a prescription, and the unit
//  the schedule editor starts on. No doses: every amount is the user's.
//

import Foundation

nonisolated enum PeptideCompoundCatalog {
    struct Compound: Equatable, Identifiable {
        var name: String
        /// Shows a "Prescription" badge.
        var prescription = false
        /// The unit the schedule editor picks for this compound until the user picks another.
        var defaultUnit: PeptideDoseUnit
        /// Shown with the name, e.g. "identity unverified".
        var note: String?

        var id: String { PeptideMath.compoundKey(name) }
    }

    static let compounds: [Compound] = [
        Compound(name: "Testosterone", prescription: true, defaultUnit: .milliliters),
        Compound(name: "hCG", defaultUnit: .iu),
        Compound(name: "MT2", defaultUnit: .mcg),
        Compound(name: "BPC-157", defaultUnit: .mcg),
        Compound(name: "Tesamorelin", defaultUnit: .mg),
        Compound(name: "GLP3", defaultUnit: .mg, note: "identity unverified"),
    ]

    static func compound(named name: String) -> Compound? {
        compounds.first { PeptideMath.sameCompound($0.name, name) }
    }

    static func isPrescription(_ name: String) -> Bool {
        compound(named: name)?.prescription ?? false
    }

    /// The catalog's names not already in `options` (the user's own), for a second chip row.
    static func names(notIn options: [String]) -> [String] {
        compounds.map(\.name).filter { name in !options.contains { PeptideMath.sameCompound($0, name) } }
    }
}
