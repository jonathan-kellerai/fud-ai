import Foundation

nonisolated enum JevGates {
    static func acceptChoice(
        _ answer: TypeSafeAnswer?,
        minP: Double,
        minConfidence: Double,
        minMargin: Double,
        reject: Set<String> = ["none"]
    ) -> String? {
        guard case .choice(let choice, let confidence, let probabilities) = answer else { return nil }
        guard !reject.contains(choice), confidence >= minConfidence, !probabilities.isEmpty else { return nil }
        let chosen = probabilities[choice] ?? 0
        guard chosen >= minP else { return nil }
        let second = probabilities.filter { $0.key != choice }.map(\.value).max() ?? 0
        guard chosen - second >= minMargin else { return nil }
        return choice
    }

    static func noulAtLeast(_ answer: TypeSafeAnswer?, _ threshold: Double) -> Bool {
        guard case .noul(let value) = answer else { return false }
        return value >= threshold
    }

    static func scoreIfConfident(_ answer: TypeSafeAnswer?, minConfidence: Double) -> Double? {
        guard case .score(let score, let confidence, _) = answer, confidence >= minConfidence else { return nil }
        return score
    }
}
