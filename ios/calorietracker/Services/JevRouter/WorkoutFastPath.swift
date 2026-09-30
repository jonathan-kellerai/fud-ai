import Foundation

struct ParsedWorkoutLine: Equatable, Sendable {
    var name: String
    var sets: Int
    var reps: Int
    var weight: String
    var unit: String?
    var rpe: String
    var minutes: String
    var timed: Bool
}

enum WorkoutLineParser {
    private static let dateWords: Set<String> = [
        "yesterday", "today", "tomorrow", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ]
    private static let knownUnits: Set<String> = ["kg", "kgs", "lb", "lbs"]

    static func parse(_ description: String) -> [ParsedWorkoutLine]? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("{") else { return nil }
        let tokens = JevText.tokens(trimmed)
        if tokens.contains(where: { dateWords.contains($0) }) { return nil }
        let rows = split(trimmed)
        guard (1...8).contains(rows.count) else { return nil }
        var parsed: [ParsedWorkoutLine] = []
        for row in rows {
            guard let line = parseLine(row) else { return nil }
            if line.sets > 12 { return nil }
            parsed.append(line)
        }
        return parsed
    }

    private static func split(_ text: String) -> [String] {
        let broken = text.replacingOccurrences(of: ";", with: "\n")
        var lines: [String] = []
        for part in broken.components(separatedBy: .newlines) {
            lines.append(contentsOf: splitCommaBeforeLetter(part))
        }
        return lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func splitCommaBeforeLetter(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: ", (?=[A-Za-z])") else { return [text] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "\n")
            .components(separatedBy: .newlines)
    }

    private static func parseLine(_ line: String) -> ParsedWorkoutLine? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timed = firstMatch(#"^(.+?)\s+(\d+)\s+(?:min|mins|minutes)$"#, text), timed.count == 3 {
            return ParsedWorkoutLine(name: timed[1], sets: 0, reps: 0, weight: "", unit: nil, rpe: "", minutes: timed[2], timed: true)
        }
        if let setsOf = firstMatch(#"^(.+?)\s+(\d+)\s+sets?(?:\s+of|\s+x)\s+(\d+)(?:\s+reps)?(?:\s+at\s+(\d+(?:\.\d+)?)\s*(kg|kgs|lb|lbs)?)?$"#, text) {
            guard let sets = Int(setsOf[2]), let reps = Int(setsOf[3]) else { return nil }
            let weight = setsOf.count > 4 ? setsOf[4] : ""
            let unit = setsOf.count > 5 ? normalizeUnit(setsOf[5]) : nil
            if setsOf.count > 5, !setsOf[5].isEmpty, unit == nil { return nil }
            return ParsedWorkoutLine(name: setsOf[1], sets: sets, reps: reps, weight: weight, unit: unit, rpe: "", minutes: "", timed: false)
        }
        if let leading = firstMatch(#"^(\d+)x(\d+)\s+(.+)$"#, text), leading.count >= 4 {
            guard let sets = Int(leading[1]), let reps = Int(leading[2]) else { return nil }
            return strengthLine(nameAndRest: leading[3], sets: sets, reps: reps, weightFirst: false)
        }
        if let trailing = firstMatch(#"^(.+?)\s+(\d+)x(\d+)(?:\s+(.*))?$"#, text), trailing.count >= 4 {
            guard let sets = Int(trailing[2]), let reps = Int(trailing[3]) else { return nil }
            let rest = trailing.count > 4 ? trailing[4] : ""
            return finish(name: trailing[1], sets: sets, reps: reps, rest: rest)
        }
        return nil
    }

    private static func strengthLine(nameAndRest: String, sets: Int, reps: Int, weightFirst: Bool) -> ParsedWorkoutLine? {
        _ = weightFirst
        let parts = nameAndRest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard let name = parts.first, !name.isEmpty else { return nil }
        let rest = parts.count > 1 ? parts[1] : ""
        if rest.contains(where: \.isNumber) || rest.contains("@") {
            return finish(name: name, sets: sets, reps: reps, rest: rest)
        }
        let nameAll = rest.isEmpty ? name : "\(name) \(rest)"
        return finish(name: nameAll, sets: sets, reps: reps, rest: "")
    }

    private static func finish(name: String, sets: Int, reps: Int, rest: String) -> ParsedWorkoutLine? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, (1...12).contains(sets), (1...999).contains(reps) else { return nil }
        let remainder = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if remainder.isEmpty {
            return ParsedWorkoutLine(name: cleaned, sets: sets, reps: reps, weight: "", unit: nil, rpe: "", minutes: "", timed: false)
        }
        let lower = remainder.lowercased()
        if lower.hasPrefix("@") || lower.hasPrefix("rpe"), !containsUnit(lower) {
            guard let rpe = firstMatch(#"^(?:@|rpe)\s*(\d+(?:\.\d+)?)$"#, remainder), rpe.count == 2 else { return nil }
            return ParsedWorkoutLine(name: cleaned, sets: sets, reps: reps, weight: "", unit: nil, rpe: rpe[1], minutes: "", timed: false)
        }
        guard let match = firstMatch(#"^(?:(?:@|at)\s+)?(\d+(?:\.\d+)?)(?:\s*(kg|kgs|lb|lbs))?(?:\s+(?:@|rpe)\s*(\d+(?:\.\d+)?))?$"#, remainder) else {
            return nil
        }
        let unitToken = match.count > 2 ? match[2] : ""
        if !unitToken.isEmpty && normalizeUnit(unitToken) == nil { return nil }
        if containsUnknownUnit(remainder) { return nil }
        return ParsedWorkoutLine(
            name: cleaned,
            sets: sets,
            reps: reps,
            weight: match[1],
            unit: normalizeUnit(unitToken),
            rpe: match.count > 3 ? match[3] : "",
            minutes: "",
            timed: false
        )
    }

    private static func containsUnit(_ text: String) -> Bool {
        knownUnits.contains { text.contains($0) }
    }

    private static func containsUnknownUnit(_ text: String) -> Bool {
        let tokens = JevText.tokens(text)
        let blocked = ["stone", "stones", "st"]
        return tokens.contains { blocked.contains($0) }
    }

    private static func normalizeUnit(_ token: String) -> String? {
        switch token.lowercased() {
        case "kg", "kgs": "kg"
        case "lb", "lbs": "lbs"
        case "": nil
        default: nil
        }
    }

    private static func firstMatch(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.range.location != NSNotFound else { return nil }
        var parts: [String] = []
        for index in 0..<match.numberOfRanges {
            let piece = match.range(at: index)
            if piece.location == NSNotFound {
                parts.append("")
            } else if let swiftRange = Range(piece, in: text) {
                parts.append(String(text[swiftRange]))
            } else {
                parts.append("")
            }
        }
        return parts
    }
}

enum WorkoutFastPath {
    static func draft(
        description: String,
        date: Date,
        unit: WeightUnit,
        library: [ExerciseLibraryItem],
        router: JevRouter = .shared,
        aliases: ExerciseAliasCache = .shared,
        isEnabled: (() -> Bool)? = nil
    ) async -> WorkoutTextDraft? {
        let isEnabled = isEnabled ?? { JevRouterSettings.isActive(.exerciseMatch) }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled(), !trimmed.hasPrefix("{") else { return nil }
        guard let lines = WorkoutLineParser.parse(trimmed) else {
            await router.report(.exerciseMatch, .fellBack(.parseFailed), preview: trimmed)
            return nil
        }
        var resolved: [String?] = Array(repeating: nil, count: lines.count)
        var pending: [(index: Int, line: ParsedWorkoutLine, options: [ExerciseLibraryItem])] = []
        for (index, line) in lines.enumerated() {
            if let id = resolveLocally(line.name, library: library, aliases: aliases) {
                resolved[index] = id
            } else {
                let options = Array(
                    WorkoutTextDraft.candidates(description: line.name, library: library)
                        .filter { sharesNameWord(line.name, $0) }
                        .prefix(12)
                )
                guard !options.isEmpty else {
                    await router.report(.exerciseMatch, .fellBack(.noCandidates), preview: trimmed)
                    return nil
                }
                pending.append((index, line, options))
            }
        }
        if pending.isEmpty {
            guard let draft = assemble(lines, ids: resolved, date: date, unit: unit, library: library) else {
                await router.report(.exerciseMatch, .fellBack(.validationFailed), preview: trimmed)
                return nil
            }
            await router.report(.exerciseMatch, .localShortcut(label: "alias", llmCallsAvoided: 2), preview: trimmed)
            return draft
        }
        let outcome = await ask(pending, workout: trimmed, router: router)
        guard case .answered(let response, _, let latency) = outcome else {
            await router.report(.exerciseMatch, .fellBack(.skipped), preview: trimmed)
            return nil
        }
        for (offset, item) in pending.enumerated() {
            let key = "ex_\(offset + 1)"
            guard let choice = JevGates.acceptChoice(response.answers[key], minP: 0.75, minConfidence: 0.60, minMargin: 0.25),
                  choice != "none",
                  item.options.contains(where: { $0.id == choice }) || library.contains(where: { $0.id == choice }) else {
                await router.report(.exerciseMatch, .fellBack(.lowConfidence), preview: trimmed, latencyMs: latency, model: response.model)
                return nil
            }
            resolved[item.index] = choice
            aliases.store(fragment: item.line.name, id: choice)
        }
        guard let draft = assemble(lines, ids: resolved, date: date, unit: unit, library: library) else {
            await router.report(.exerciseMatch, .fellBack(.validationFailed), preview: trimmed, latencyMs: latency, model: response.model)
            return nil
        }
        await router.report(
            .exerciseMatch,
            .accepted(label: "draft", confidence: nil, llmCallsAvoided: 2),
            preview: trimmed,
            latencyMs: latency,
            model: response.model
        )
        return draft
    }

    private static func resolveLocally(_ name: String, library: [ExerciseLibraryItem], aliases: ExerciseAliasCache) -> String? {
        let normalized = JevText.normalize(name)
        if let cached = aliases.id(for: normalized, library: library) { return cached }
        if let alias = ExerciseSearchMatcher.aliases[normalized], library.contains(where: { $0.id == alias }) {
            return alias
        }
        if let exact = library.first(where: { JevText.normalize($0.name) == normalized }) {
            return exact.id
        }
        return nil
    }

    /// `candidates` also ranks every cardio item and common lift, even with no word in common.
    /// Jev only chooses among exercises whose name shares a word with the entry.
    private static func sharesNameWord(_ fragment: String, _ item: ExerciseLibraryItem) -> Bool {
        let words = JevText.tokens(fragment).filter { $0.count >= 3 }
        guard !words.isEmpty else { return false }
        let name = JevText.normalize("\(item.name) \(item.id.replacingOccurrences(of: "_", with: " "))")
        return words.contains { name.contains($0) }
    }

    private static func ask(
        _ pending: [(index: Int, line: ParsedWorkoutLine, options: [ExerciseLibraryItem])],
        workout: String,
        router: JevRouter
    ) async -> JevOutcome {
        var questions: [String: TypeSafeQuestion] = [:]
        for (offset, item) in pending.enumerated() {
            var criteria: [(key: String, value: TypeSafeJSON)] = []
            var used = Set<String>()
            for (optionIndex, option) in item.options.enumerated() {
                let key = safeKey(option.id, fallback: "e\(optionIndex + 1)", used: &used)
                criteria.append((key, .object([
                    "name": .string(option.name),
                    "equipment": .string(option.rawEquipment)
                ])))
            }
            criteria.append(("none", .string("Not listed, or unclear which variant")))
            questions["ex_\(offset + 1)"] = .choiceJSON(
                instructions: .object([
                    "task": .string("Which catalog exercise is `entry`? Choose none if it is not listed or if it could be several different variants (for example barbell vs dumbbell)."),
                    "entry": .string(item.line.name)
                ]),
                criteria: criteria
            )
        }
        let fingerprint = pending.map { row in row.options.map(\.id).joined(separator: ",") }.joined(separator: "|")
        let cacheKey = JevText.normalize(workout) + "|" + JevText.sha256(fingerprint)
        let state = TypeSafeJSON.object(["workout": .string(workout)])
        return await router.ask(.exerciseMatch, cacheKey: cacheKey, preview: workout) { model in
            TypeSafeRequest(state: state, model: model, questions: questions)
        }
    }

    private static func safeKey(_ id: String, fallback: String, used: inout Set<String>) -> String {
        let allowed = id.unicodeScalars.allSatisfy { character in
            CharacterSet.alphanumerics.contains(character) || character == "_" || character == "-"
        }
        var key = allowed && !id.isEmpty ? id : fallback
        if used.contains(key) { key = fallback }
        used.insert(key)
        return key
    }

    private static func assemble(
        _ lines: [ParsedWorkoutLine],
        ids: [String?],
        date: Date,
        unit: WeightUnit,
        library: [ExerciseLibraryItem]
    ) -> WorkoutTextDraft? {
        let exercises: [WorkoutTextExercise] = lines.enumerated().map { index, line in
            let resolvedUnit = line.unit ?? (unit == .kg ? "kg" : "lbs")
            let item = ids[index].flatMap { id in library.first { $0.id == id } }
            let sets: [WorkoutTextSet] = line.timed ? [] : (0..<line.sets).map { _ in
                WorkoutTextSet(weight: line.weight, reps: String(line.reps), rpe: line.rpe)
            }
            return WorkoutTextExercise(
                exerciseID: item?.id,
                name: item?.name ?? line.name,
                minutes: line.minutes,
                unit: resolvedUnit,
                intensity: "moderate",
                sets: sets
            )
        }
        let draft = WorkoutTextDraft(date: StrengthWorkoutDate.key(for: date), exercises: exercises)
        guard (try? draft.planned(library: library, today: date)) != nil else { return nil }
        return draft
    }
}
