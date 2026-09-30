import Foundation

// MARK: - Tolerant bridge decoding

/// Number that may arrive as a JSON number, a numeric string (Postgres
/// `numeric` comes back as a string through node-postgres) or null.
nonisolated struct ProgressFlexibleNumber: Decodable, Equatable, Sendable {
    let value: Double?

    init(_ value: Double?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let number = try? container.decode(Double.self) {
            value = number.isFinite ? number : nil
        } else if let text = try? container.decode(String.self) {
            let parsed = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            value = parsed.flatMap { $0.isFinite ? $0 : nil }
        } else {
            value = nil
        }
    }
}

/// Decodes one array element, turning a malformed row into nil instead of
/// failing the whole response.
nonisolated struct ProgressLossy<Element: Decodable & Sendable>: Decodable, Sendable {
    let value: Element?

    init(from decoder: Decoder) throws {
        value = try? Element(from: decoder)
    }
}

/// One row of GET /api/workouts. The list has no sets.
nonisolated struct ProgressBridgeWorkout: Decodable, Equatable, Sendable {
    let id: String
    /// "COMPLETED" for real saved sessions.
    let kind: String?
    let programDay: String?
    let title: String?
    let sessionDate: String?
    let recordedAt: String?
    let synthetic: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case programDay = "program_day"
        case title
        case sessionDate = "session_date"
        case recordedAt = "recorded_at"
        case synthetic
    }

    init(
        id: String,
        kind: String? = "COMPLETED",
        programDay: String? = nil,
        title: String? = nil,
        sessionDate: String?,
        recordedAt: String? = nil,
        synthetic: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.programDay = programDay
        self.title = title
        self.sessionDate = sessionDate
        self.recordedAt = recordedAt
        self.synthetic = synthetic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .id) {
            id = text
        } else if let number = try? container.decode(Int.self, forKey: .id) {
            id = String(number)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Workout row has no id")
        }
        kind = try? container.decodeIfPresent(String.self, forKey: .kind)
        programDay = try? container.decodeIfPresent(String.self, forKey: .programDay)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        sessionDate = try? container.decodeIfPresent(String.self, forKey: .sessionDate)
        recordedAt = try? container.decodeIfPresent(String.self, forKey: .recordedAt)
        synthetic = try? container.decodeIfPresent(Bool.self, forKey: .synthetic)
    }
}

nonisolated struct ProgressBridgeWorkoutList: Decodable, Sendable {
    let workouts: [ProgressBridgeWorkout]

    enum CodingKeys: String, CodingKey {
        case workouts
    }

    init(workouts: [ProgressBridgeWorkout]) {
        self.workouts = workouts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try container.decode([ProgressLossy<ProgressBridgeWorkout>].self, forKey: .workouts)
        workouts = rows.compactMap(\.value)
    }
}

/// One row of `sets` in GET /api/workouts/{id}.
nonisolated struct ProgressBridgeSet: Decodable, Equatable, Sendable {
    let id: String?
    let exercise: String?
    let loadLb: Double?
    let reps: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case exercise
        case loadLb = "load_lb"
        case reps
    }

    init(id: String? = nil, exercise: String? = nil, loadLb: Double?, reps: Double?) {
        self.id = id
        self.exercise = exercise
        self.loadLb = loadLb
        self.reps = reps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .id)).map { String($0) }
        exercise = try? container.decodeIfPresent(String.self, forKey: .exercise)
        loadLb = (try? container.decodeIfPresent(ProgressFlexibleNumber.self, forKey: .loadLb))?.value
        reps = (try? container.decodeIfPresent(ProgressFlexibleNumber.self, forKey: .reps))?.value
    }

    /// load_lb × reps; a missing load or rep count adds nothing.
    var volumeLb: Double {
        guard let loadLb, let reps else { return 0 }
        return loadLb * reps
    }
}

/// GET /api/workouts/{id} → {"workout": {...}, "sets": [...]}.
nonisolated struct ProgressBridgeWorkoutDetail: Decodable, Sendable {
    let sets: [ProgressBridgeSet]

    enum CodingKeys: String, CodingKey {
        case sets
    }

    init(sets: [ProgressBridgeSet]) {
        self.sets = sets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try container.decode([ProgressLossy<ProgressBridgeSet>].self, forKey: .sets)
        sets = rows.compactMap(\.value)
    }

    var totals: ProgressWorkoutTotals {
        ProgressWorkoutTotals(sets: sets.count, volumeLb: sets.reduce(0) { $0 + $1.volumeLb })
    }
}

/// Sets and volume of one completed workout.
nonisolated struct ProgressWorkoutTotals: Equatable, Sendable {
    let sets: Int
    /// Σ load_lb × reps.
    let volumeLb: Double
}

// MARK: - Weekly summary

/// A completed workout with its day key and the Monday of its week.
nonisolated struct ProgressCompletedSession: Equatable, Sendable {
    let workout: ProgressBridgeWorkout
    let day: String
    let week: String
}

nonisolated struct ProgressTrainingWeek: Equatable, Sendable, Identifiable {
    /// Monday of the week, YYYY-MM-DD.
    let weekStart: String
    let sessions: Int
    /// Nil when the week has sessions but none of their sets were loaded.
    let sets: Int?
    /// Pounds lifted (load_lb × reps). Nil like `sets`.
    let volumeLb: Double?

    var id: String { weekStart }
}

nonisolated struct ProgressTrainingSummary: Equatable, Sendable {
    let weeks: [ProgressTrainingWeek]
    /// Weeks overlapping the selected range, before the week cap.
    let weeksInRange: Int
    let weekLimit: Int
    /// /api/workouts returned its full limit, so older sessions may be missing.
    let listTruncated: Bool
    /// Oldest day in a truncated list, when that is inside the shown weeks.
    let sessionListCutoff: String?
    /// Completed sessions in the shown weeks.
    let sessionsInRange: Int
    /// Most recent sessions whose sets were requested (at most the detail limit).
    let detailSessions: Int
    let detailLimit: Int
    /// Requested sessions whose sets could not be loaded.
    let failedDetails: Int

    var isTruncated: Bool { weeksInRange > weeks.count }
    /// Sets and volume only cover the most recent `detailLimit` sessions.
    var isDetailLimited: Bool { sessionsInRange > detailSessions }
    var totalSessions: Int { weeks.reduce(0) { $0 + $1.sessions } }
    var totalSets: Int? {
        let loaded = weeks.compactMap(\.sets)
        return loaded.isEmpty ? nil : loaded.reduce(0, +)
    }
    var totalVolumeLb: Double? {
        let loaded = weeks.compactMap(\.volumeLb)
        return loaded.isEmpty ? nil : loaded.reduce(0, +)
    }
    var averageSessionsPerWeek: Double? {
        weeks.isEmpty ? nil : Double(totalSessions) / Double(weeks.count)
    }
    var isEmpty: Bool {
        weeks.allSatisfy { $0.sessions == 0 }
    }
}

nonisolated enum ProgressTrainingMath {
    static let workoutListLimit = 200
    /// Most recent completed sessions per range whose sets are fetched.
    static let maxDetailSessions = 60
    /// Weeks drawn; a year of bars. Older weeks in All are summarized in a note.
    static let maxWeeks = 53
    static let maxConcurrentRequests = 4

    static var eastern: TimeZone { TimeZone(identifier: "America/New_York") ?? .gmt }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// Real saved sessions: kind "COMPLETED" (any case) and not synthetic.
    static func isCompleted(_ workout: ProgressBridgeWorkout) -> Bool {
        guard workout.synthetic != true else { return false }
        return workout.kind?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "COMPLETED"
    }

    /// session_date's YYYY-MM-DD (it may be "2026-09-28" or
    /// "2026-09-28T00:00:00.000Z"), else recorded_at as an Eastern day.
    static func dayKey(for workout: ProgressBridgeWorkout, timeZone: TimeZone = ProgressTrainingMath.eastern) -> String? {
        if let raw = workout.sessionDate?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 10 {
            let key = String(raw.prefix(10))
            if parseDayKey(key) != nil { return key }
        }
        if let raw = workout.recordedAt, let date = parseTimestamp(raw) {
            return dayKey(for: date, timeZone: timeZone)
        }
        return nil
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    /// Strict YYYY-MM-DD, as midnight UTC.
    static func parseDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        let calendar = utcCalendar
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    static func dayKey(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Local calendar day (the user's day) as YYYY-MM-DD.
    static func dayKey(forLocalDay date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Monday on or before the given day.
    static func mondayKey(for dayKey: String) -> String? {
        guard let date = parseDayKey(dayKey) else { return nil }
        let calendar = utcCalendar
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        let back = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -back, to: date) else { return nil }
        return Self.dayKey(for: monday, timeZone: .gmt)
    }

    /// Monday keys of every week overlapping `startDayKey...endDayKey`, oldest first.
    static func weekKeys(from startDayKey: String, through endDayKey: String) -> [String] {
        guard let firstMonday = mondayKey(for: startDayKey).flatMap(parseDayKey),
              let lastMonday = mondayKey(for: endDayKey).flatMap(parseDayKey),
              firstMonday <= lastMonday else { return [] }
        let calendar = utcCalendar
        var keys: [String] = []
        var cursor = firstMonday
        while cursor <= lastMonday {
            keys.append(dayKey(for: cursor, timeZone: .gmt))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return keys
    }

    /// The most recent `limit` week keys in range; these are the only weeks
    /// the card counts and draws.
    static func displayedWeekKeys(from startDayKey: String, through endDayKey: String, limit: Int = ProgressTrainingMath.maxWeeks) -> (shown: [String], total: Int) {
        let all = weekKeys(from: startDayKey, through: endDayKey)
        return (Array(all.suffix(max(0, limit))), all.count)
    }

    /// Completed sessions in the shown weeks (up to today), most recent first.
    static func completedSessions(
        _ workouts: [ProgressBridgeWorkout],
        shownWeeks: [String],
        todayKey: String,
        timeZone: TimeZone = ProgressTrainingMath.eastern
    ) -> [ProgressCompletedSession] {
        let shownSet = Set(shownWeeks)
        var seen: Set<String> = []
        var rows: [ProgressCompletedSession] = []
        for workout in workouts where isCompleted(workout) {
            guard !seen.contains(workout.id),
                  let day = dayKey(for: workout, timeZone: timeZone),
                  day <= todayKey,
                  let monday = mondayKey(for: day),
                  shownSet.contains(monday) else { continue }
            seen.insert(workout.id)
            rows.append(ProgressCompletedSession(workout: workout, day: day, week: monday))
        }
        rows.sort { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day > rhs.day }
            let lhsRecorded = lhs.workout.recordedAt ?? ""
            let rhsRecorded = rhs.workout.recordedAt ?? ""
            if lhsRecorded != rhsRecorded { return lhsRecorded > rhsRecorded }
            return lhs.workout.id > rhs.workout.id
        }
        return rows
    }

    /// Ids of the workouts whose sets should be loaded: the most recent
    /// `detailLimit` completed sessions in the shown weeks.
    static func detailWorkoutIDs(
        workouts: [ProgressBridgeWorkout],
        startDayKey: String,
        todayKey: String,
        weekLimit: Int = ProgressTrainingMath.maxWeeks,
        detailLimit: Int = ProgressTrainingMath.maxDetailSessions,
        timeZone: TimeZone = ProgressTrainingMath.eastern
    ) -> [String] {
        let shown = displayedWeekKeys(from: startDayKey, through: todayKey, limit: weekLimit).shown
        return completedSessions(workouts, shownWeeks: shown, todayKey: todayKey, timeZone: timeZone)
            .prefix(max(0, detailLimit))
            .map { $0.workout.id }
    }

    /// Sessions, sets and volume per Monday–Sunday week. `details` holds the
    /// loaded sets per workout id; ids requested but missing from it count as
    /// `failedDetails` (passed by the loader).
    static func summary(
        workouts: [ProgressBridgeWorkout],
        details: [String: ProgressWorkoutTotals],
        startDayKey: String,
        todayKey: String,
        failedDetails: Int = 0,
        listLimit: Int = ProgressTrainingMath.workoutListLimit,
        weekLimit: Int = ProgressTrainingMath.maxWeeks,
        detailLimit: Int = ProgressTrainingMath.maxDetailSessions,
        timeZone: TimeZone = ProgressTrainingMath.eastern
    ) -> ProgressTrainingSummary {
        let (shown, total) = displayedWeekKeys(from: startDayKey, through: todayKey, limit: weekLimit)
        let sessions = completedSessions(workouts, shownWeeks: shown, todayKey: todayKey, timeZone: timeZone)
        let requested = Set(sessions.prefix(max(0, detailLimit)).map { $0.workout.id })

        var sessionsByWeek: [String: Int] = [:]
        var setsByWeek: [String: Int] = [:]
        var volumeByWeek: [String: Double] = [:]
        for row in sessions {
            sessionsByWeek[row.week, default: 0] += 1
            guard requested.contains(row.workout.id), let totals = details[row.workout.id] else { continue }
            setsByWeek[row.week, default: 0] += totals.sets
            volumeByWeek[row.week, default: 0] += totals.volumeLb
        }
        let weeks = shown.map { key in
            let count = sessionsByWeek[key] ?? 0
            // A week without sessions truly has zero sets; a week whose
            // sessions have no loaded sets is unknown.
            let known = count == 0 || setsByWeek[key] != nil
            return ProgressTrainingWeek(
                weekStart: key,
                sessions: count,
                sets: known ? (setsByWeek[key] ?? 0) : nil,
                volumeLb: known ? (volumeByWeek[key] ?? 0) : nil
            )
        }

        let listTruncated = workouts.count >= listLimit
        var cutoff: String?
        if listTruncated,
           let oldest = workouts.compactMap({ dayKey(for: $0, timeZone: timeZone) }).min(),
           let firstShown = shown.first,
           oldest > firstShown {
            cutoff = oldest
        }
        return ProgressTrainingSummary(
            weeks: weeks,
            weeksInRange: total,
            weekLimit: weekLimit,
            listTruncated: listTruncated,
            sessionListCutoff: cutoff,
            sessionsInRange: sessions.count,
            detailSessions: requested.count,
            detailLimit: detailLimit,
            failedDetails: failedDetails
        )
    }

    static func decodeWorkouts(_ data: Data) throws -> [ProgressBridgeWorkout] {
        try JSONDecoder().decode(ProgressBridgeWorkoutList.self, from: data).workouts
    }

    static func decodeWorkoutDetail(_ data: Data) throws -> ProgressBridgeWorkoutDetail {
        try JSONDecoder().decode(ProgressBridgeWorkoutDetail.self, from: data)
    }
}

// MARK: - Network

/// Same URL and header rules as NeonBridgeService.makeURL / makeRequest,
/// built from its settings so Progress follows whatever bridge the user set.
nonisolated struct ProgressBridgeConfig: Equatable, Sendable {
    let baseURL: String
    let apiKey: String?

    var isConfigured: Bool {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return false }
        return true
    }

    func request(path: String, queryItems: [URLQueryItem]) -> URLRequest? {
        guard isConfigured else { return nil }
        var components = URLComponents(string: baseURL + path)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// "/api/workouts/{id}" with the id percent-encoded as one path segment.
    static func workoutPath(id: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return "/api/workouts/" + (id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id)
    }
}

nonisolated enum ProgressTrainingError: Error, Equatable {
    case notConfigured
    case offline
    case http(Int)
    case badResponse
    case transport
}

nonisolated enum ProgressTrainingAPI {
    static func fetchWorkouts(config: ProgressBridgeConfig, limit: Int = ProgressTrainingMath.workoutListLimit) async throws -> [ProgressBridgeWorkout] {
        let data = try await get(config: config, path: "/api/workouts", queryItems: [URLQueryItem(name: "limit", value: "\(limit)")])
        do {
            return try ProgressTrainingMath.decodeWorkouts(data)
        } catch {
            throw ProgressTrainingError.badResponse
        }
    }

    static func fetchWorkoutTotals(config: ProgressBridgeConfig, id: String) async throws -> ProgressWorkoutTotals {
        let data = try await get(config: config, path: ProgressBridgeConfig.workoutPath(id: id), queryItems: [])
        do {
            return try ProgressTrainingMath.decodeWorkoutDetail(data).totals
        } catch {
            throw ProgressTrainingError.badResponse
        }
    }

    private static func get(config: ProgressBridgeConfig, path: String, queryItems: [URLQueryItem]) async throws -> Data {
        guard let request = config.request(path: path, queryItems: queryItems) else {
            throw ProgressTrainingError.notConfigured
        }
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .timedOut, .cannotConnectToHost, .cannotFindHost:
                throw ProgressTrainingError.offline
            default:
                throw ProgressTrainingError.transport
            }
        } catch {
            throw ProgressTrainingError.transport
        }
        let (data, response) = result
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ProgressTrainingError.http(http.statusCode)
        }
        return data
    }
}
