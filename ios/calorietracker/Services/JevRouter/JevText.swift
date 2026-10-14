import CryptoKit
import Foundation

nonisolated enum JevText {
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let spaced = folded.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(spaced).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    static func tokenDice(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(tokens(lhs))
        let right = Set(tokens(rhs))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let overlap = left.intersection(right).count
        return (2 * Double(overlap)) / Double(left.count + right.count)
    }

    static func trigramJaccard(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(trigrams(normalize(lhs)))
        let right = Set(trigrams(normalize(rhs)))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let union = left.union(right).count
        guard union > 0 else { return 0 }
        return Double(left.intersection(right).count) / Double(union)
    }

    static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func trigrams(_ text: String) -> [String] {
        let padded = "  \(text) "
        let characters = Array(padded)
        guard characters.count >= 3 else { return [] }
        return (0...(characters.count - 3)).map { index in
            String(characters[index..<(index + 3)])
        }
    }
}
