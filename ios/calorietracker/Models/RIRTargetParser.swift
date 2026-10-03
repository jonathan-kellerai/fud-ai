import Foundation

enum RIRTargetParser {
    /// Set indices are zero-based, as in the logger. Only defaults are clamped;
    /// an explicitly entered or historical 0 RIR remains a real value.
    static func defaultRIR(for rirTarget: String, setIndex: Int, setCount: Int) -> Int? {
        guard setIndex >= 0, setCount > 0 else { return nil }
        var fallback: Int?
        for raw in rirTarget.components(separatedBy: CharacterSet(charactersIn: ";,")) {
            let segment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if segment.lowercased().hasPrefix("no set") { continue }
            if let scope = match(#"^last\s+set\s*:?[\s]*(.*)$"#, in: segment) {
                if setIndex == setCount - 1, let value = value(in: scope[1], allowsBare: true) {
                    return value
                }
            } else if let scope = match(#"^sets?\s+(\d+)(?:\s*[-–]\s*(\d+))?\s*:?[\s]*(.*)$"#, in: segment),
                      let low = Int(scope[1]) {
                let high = Int(scope[2]) ?? low
                if (min(low, high)...max(low, high)).contains(setIndex + 1),
                   let value = value(in: scope[3], allowsBare: true) {
                    return value
                }
            } else if fallback == nil {
                fallback = value(in: segment, allowsBare: true)
            }
        }
        return fallback
    }

    static func target(for exercise: ProgramV2Exercise) -> String {
        let target = exercise.rirTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.isEmpty { return target }
        return match(#"RIR\s+target:\s*([^\.\n]+)"#, in: exercise.notes)?[1]
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func value(in text: String, allowsBare: Bool) -> Int? {
        let withUnit = match(#"(\d+)(?:\s*[-–]\s*(\d+))?\s*RIR"#, in: text)
        let bare = allowsBare ? match(#"^\s*~?(\d+)(?:\s*[-–]\s*(\d+))?\s*$"#, in: text) : nil
        guard let numbers = withUnit ?? bare, let low = Int(numbers[1]) else { return nil }
        return max(1, min(low, Int(numbers[2]) ?? low))
    }

    private static func match(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<result.numberOfRanges).map { index in
            guard let range = Range(result.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
