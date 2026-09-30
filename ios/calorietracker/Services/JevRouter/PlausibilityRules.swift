import Foundation

struct PlausibilityFlag: Identifiable, Equatable, Sendable {
    enum Severity: String, Sendable { case strong, grey }

    var id: String
    var severity: Severity
    var title: String
    var message: String
    /// Relative wording only. Never an absolute body weight.
    var fact: String
}

enum PlausibilityRules {
    private static let kgPerLb = 0.45359237
    private static let lbPerKg = 2.2046226218

    static func sets(
        name: String,
        loadKg: Double,
        reps: Int,
        referenceLoadsKg: [Double],
        referenceReps: [Int],
        sessionLoadsKg: [Double]
    ) -> [PlausibilityFlag] {
        var flags: [PlausibilityFlag] = []
        if reps > 100 || loadKg > 500 {
            flags.append(flag(name, .strong, "Check \(name)", "\(name): \(reps) reps at a very high load.", "This set is past the usual range for a single entry."))
        }
        if let reference = referenceLoadsKg.max(), reference > 0 {
            let ratio = loadKg / reference
            if near(ratio, lbPerKg) || near(ratio, kgPerLb) {
                flags.append(flag(name, .strong, "Check the unit", "\(name) looks like a kg/lb unit mix-up.", "\(name), the load is about \(percent(ratio)) of a recent set, close to a kg/lb conversion."))
            }
            let repsClose = referenceReps.isEmpty || referenceReps.contains { abs($0 - reps) <= 3 }
            if repsClose, (ratio >= 8 && ratio <= 12) || (ratio >= 0.08 && ratio <= 0.125) {
                flags.append(flag(name, .strong, "Check the digits", "\(name) is about 10× a recent load.", "\(name), the load is about \(Int(ratio.rounded()))× a recent set with similar reps."))
            }
            let current = epley(loadKg, reps)
            let best = zip(referenceLoadsKg, referenceReps.isEmpty ? Array(repeating: reps, count: referenceLoadsKg.count) : referenceReps)
                .map { epley($0.0, $0.1) }
                .max() ?? current
            if best > 0 {
                let epleyRatio = current / best
                if epleyRatio > 1.35 {
                    flags.append(flag(name, .strong, "Check this set", "\(name) is much heavier than recent work.", "\(name), \(reps) reps, about \(percent(epleyRatio - 1)) heavier than their best recent set."))
                } else if epleyRatio >= 1.15 {
                    flags.append(flag(name, .grey, "Check this set", "\(name) is heavier than recent work.", "\(name), \(reps) reps, about \(percent(epleyRatio - 1)) heavier than their best recent set."))
                }
            }
        }
        let others = sessionLoadsKg.filter { $0 > 0 }
        if let median = median(others), median > 0 {
            let ratio = loadKg / median
            if ratio > 2 || ratio < 0.5 {
                flags.append(flag(name, .grey, "Check this set", "\(name) is far from the other sets today.", "\(name), this set is about \(percent(ratio)) of the other sets today."))
            }
        }
        return flags
    }

    static func weight(newKg: Double, previousKg: Double?, days: Int) -> [PlausibilityFlag] {
        guard let previousKg, previousKg > 0 else { return [] }
        let ratio = newKg / previousKg
        let span = max(1, days)
        let delta = abs(newKg - previousKg)
        let perDay = delta / Double(span)
        var flags: [PlausibilityFlag] = []
        if near(ratio, lbPerKg, tolerance: 0.05) || near(ratio, kgPerLb, tolerance: 0.05) {
            flags.append(flag("weight", .strong, "Check the unit", "This weight looks like a kg/lb unit mix-up.", "Body weight changed by about a kg/lb conversion versus the last entry."))
        }
        if delta >= 2, perDay > 1.5 {
            flags.append(flag("weight", .strong, "Check this weight", "This weight jumped quickly.", "Body weight moved about \(percent(delta / previousKg)) over \(span) day\(span == 1 ? "" : "s")."))
        } else if delta >= 1.5, perDay > 0.75, perDay <= 1.5 {
            flags.append(flag("weight", .grey, "Check this weight", "This weight changed faster than usual.", "Body weight moved about \(percent(delta / previousKg)) over \(span) day\(span == 1 ? "" : "s")."))
        }
        return flags
    }

    static func bodyFat(newPercent: Double, previousPercent: Double?, days: Int) -> [PlausibilityFlag] {
        guard let previousPercent else { return [] }
        let delta = abs(newPercent - previousPercent)
        guard days <= 14 else { return [] }
        if delta >= 6 {
            return [flag("bodyfat", .strong, "Check body fat", "Body fat changed by \(Int(delta.rounded())) points.", "Body fat changed by about \(Int(delta.rounded())) points within two weeks.")]
        }
        if delta >= 3 {
            return [flag("bodyfat", .grey, "Check body fat", "Body fat changed by \(Int(delta.rounded())) points.", "Body fat changed by about \(Int(delta.rounded())) points within two weeks.")]
        }
        return []
    }

    static func measurement(newCm: Double, previousCm: Double?, days: Int) -> [PlausibilityFlag] {
        guard let previousCm, previousCm > 0 else { return [] }
        let ratio = newCm / previousCm
        var flags: [PlausibilityFlag] = []
        if near(ratio, 2.54, tolerance: 0.05) || near(ratio, 1 / 2.54, tolerance: 0.05) {
            flags.append(flag("measure", .strong, "Check the unit", "This measurement looks like a cm/inch unit mix-up.", "The measurement changed by about a cm/inch conversion versus the last entry."))
        }
        let change = abs(ratio - 1)
        if days <= 30, change >= 0.20 {
            flags.append(flag("measure", .strong, "Check this measurement", "This measurement changed a lot.", "The measurement changed by about \(percent(change)) within 30 days."))
        } else if days <= 30, change >= 0.10 {
            flags.append(flag("measure", .grey, "Check this measurement", "This measurement changed quickly.", "The measurement changed by about \(percent(change)) within 30 days."))
        }
        return flags
    }

    private static func epley(_ load: Double, _ reps: Int) -> Double {
        load * (1 + Double(reps) / 30)
    }

    private static func near(_ value: Double, _ target: Double, tolerance: Double = 0.08) -> Bool {
        abs(value - target) / target <= tolerance
    }

    private static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    private static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func flag(_ id: String, _ severity: PlausibilityFlag.Severity, _ title: String, _ message: String, _ fact: String) -> PlausibilityFlag {
        PlausibilityFlag(id: id, severity: severity, title: title, message: message, fact: fact)
    }
}

enum PlausibilityReview {
    static func visible(
        _ flags: [PlausibilityFlag],
        router: JevRouter = .shared,
        localActive: Bool? = nil,
        tieBreak: Bool? = nil
    ) async -> [PlausibilityFlag] {
        let localActive = localActive ?? JevRouterSettings.localPlausibilityActive
        let tieBreak = tieBreak ?? JevRouterSettings.isActive(.plausibility)
        guard localActive else { return [] }
        let strong = flags.filter { $0.severity == .strong }
        let grey = Array(flags.filter { $0.severity == .grey }.prefix(5))
        guard tieBreak, !grey.isEmpty else { return strong }
        var questions: [String: TypeSafeQuestion] = [:]
        for (index, flag) in grey.enumerated() {
            questions["flag_\(index + 1)"] = .noul(
                instructions: .object([
                    "task": .string("Is `entry` more likely a typing or unit mistake than a real result?"),
                    "entry": .string(flag.fact)
                ]),
                criteria: ("A typo, wrong unit, or number in the wrong field", "A plausible real result, such as a personal record or normal day-to-day variation")
            )
        }
        let cacheKey = grey.map(\.fact).joined(separator: "|")
        let outcome = await router.ask(.plausibility, cacheKey: JevText.normalize(cacheKey), preview: grey.first?.title ?? "") { model in
            TypeSafeRequest(state: .object(["log": .string("entry")]), model: model, questions: questions)
        }
        guard case .answered(let response, _, _) = outcome else { return strong }
        let confirmed = grey.enumerated().filter { index, _ in
            JevGates.noulAtLeast(response.answers["flag_\(index + 1)"], 0.60)
        }.map(\.element)
        return strong + confirmed
    }
}
