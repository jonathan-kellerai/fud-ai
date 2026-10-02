import Foundation
import Testing
@testable import calorietracker

@Suite("Weekly Challenge")
struct WeeklyChallengeTests {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    @Test("Local aggregation uses Monday weeks, qualifying days, and daily activity cap")
    func aggregateWeeklyScore() {
        let score = WeeklyChallengeAggregator.score(
            now: date("2026-08-26T12:00:00Z"),
            calendar: utcCalendar,
            foods: [
                .init(date: date("2026-08-24T08:00:00Z"), calories: 2_000),
                .init(date: date("2026-08-25T08:00:00Z"), calories: 1_000),
                .init(date: date("2026-08-27T08:00:00Z"), calories: 2_000), // future
                .init(date: date("2026-08-23T08:00:00Z"), calories: 2_000), // prior week
            ],
            water: [
                .init(date: date("2026-08-24T08:00:00Z"), milliliters: 1_000),
                .init(date: date("2026-08-24T18:00:00Z"), milliliters: 1_000),
                .init(date: date("2026-08-25T18:00:00Z"), milliliters: 1_999),
            ],
            activities: [
                .init(date: date("2026-08-24T08:00:00Z"), calories: 1_500),
                .init(date: date("2026-08-24T18:00:00Z"), calories: 1_000),
                .init(date: date("2026-08-25T08:00:00Z"), calories: nil),
                .init(date: date("2026-08-25T18:00:00Z"), calories: 0),
                .init(date: date("2026-08-26T08:00:00Z"), calories: 500),
            ],
            calorieGoal: 2_000,
            hydrationEnabled: true,
            hydrationGoalMilliliters: 2_000
        )

        #expect(score.weekStart == "2026-08-24")
        #expect(score.activityDays == 2)
        #expect(score.activityKcal == 2_500)
        #expect(score.nutritionDays == 1)
        #expect(score.consistencyDays == 2)
        #expect(score.hydrationDays == 1)
        #expect(score.overallPoints == 6)
    }

    @Test("Hydration points stay disabled when hydration tracking is off")
    func disabledHydrationDoesNotScore() {
        let score = WeeklyChallengeAggregator.score(
            now: date("2026-08-24T12:00:00Z"),
            calendar: utcCalendar,
            foods: [],
            water: [.init(date: date("2026-08-24T08:00:00Z"), milliliters: 4_000)],
            activities: [],
            calorieGoal: 2_000,
            hydrationEnabled: false,
            hydrationGoalMilliliters: 2_000
        )

        #expect(score.hydrationDays == 0)
        #expect(score.overallPoints == 0)
    }

    @Test("Profile validation matches public-name and social-handle contract")
    func profileValidation() {
        #expect(WeeklyChallengeProfileValidator.isValidDisplayName("Apoorv D."))
        #expect(WeeklyChallengeProfileValidator.isValidDisplayName("李 明"))
        #expect(!WeeklyChallengeProfileValidator.isValidDisplayName("A"))
        #expect(!WeeklyChallengeProfileValidator.isValidDisplayName("Runner 🏃"))
        #expect(!WeeklyChallengeProfileValidator.isValidDisplayName("Admin"))
        #expect(!WeeklyChallengeProfileValidator.isValidDisplayName("Fud AI"))
        #expect(!WeeklyChallengeProfileValidator.isValidDisplayName("fud.ai"))
        #expect(!WeeklyChallengeProfileValidator.isValidDisplayName("runner.example"))
        #expect(WeeklyChallengeProfileValidator.isValid(handle: "fud_ai", for: .x))
        #expect(!WeeklyChallengeProfileValidator.isValid(handle: "@fud_ai", for: .x))
        #expect(WeeklyChallengeProfileValidator.isValid(handle: "fud.ai", for: .instagram))
        #expect(!WeeklyChallengeProfileValidator.isValid(handle: "fud..ai", for: .instagram))
        #expect(!WeeklyChallengeProfileValidator.isValid(handle: "fudai.", for: .instagram))
    }

    @Test("Report details match the service plain-text and code-point contract")
    func reportDetailsValidation() {
        let sanitized = WeeklyChallengeReportDetailsValidator.sanitizedInput(
            "  First line\n\nSecond\tline\u{200B}  "
        )
        #expect(sanitized == "First line Second line ")
        #expect(WeeklyChallengeReportDetailsValidator.submissionValue(sanitized) == "First line Second line")

        let multiScalarEmoji = "👨‍👩‍👧‍👦"
        let bounded = WeeklyChallengeReportDetailsValidator.sanitizedInput(
            String(repeating: multiScalarEmoji, count: 100)
        )
        #expect(bounded.unicodeScalars.count == 300)
    }

    @Test("Create request explicitly encodes eligibility, rules, and paired null social fields")
    func createRequestEncoding() throws {
        let profile = WeeklyChallengeProfileInput(
            displayName: "Apoorv",
            socialPlatform: nil,
            socialHandle: nil
        )
        let request = WeeklyChallengeCreateProfileRequest(
            profile: profile,
            acceptedRules: true,
            eligibilityAccepted: true
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )

        #expect(object["displayName"] as? String == "Apoorv")
        #expect(object["acceptedRules"] as? Bool == true)
        #expect(object["eligibilityAccepted"] as? Bool == true)
        #expect(object["socialPlatform"] is NSNull)
        #expect(object["socialHandle"] is NSNull)
    }

    @Test("Score encoding contains only the bounded aggregate contract")
    func scoreEncoding() throws {
        let score = WeeklyChallengeScore(
            weekStart: "2026-08-24",
            activityDays: 9,
            nutritionDays: 2,
            consistencyDays: 3,
            hydrationDays: 4,
            activityKcal: 20_000
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(score)) as? [String: Any]
        )

        #expect(Set(object.keys) == Set([
            "weekStart", "overallPoints", "activityDays", "nutritionDays",
            "consistencyDays", "hydrationDays", "activityKcal",
        ]))
        #expect(object["activityDays"] as? Int == 7)
        #expect(object["activityKcal"] as? Int == 14_000)
        #expect(object["overallPoints"] as? Int == 16)
    }

    @Test("Leaderboard decodes rankings and a separately pinned viewer")
    func leaderboardDecoding() throws {
        let data = Data(
            #"{"weekStart":"2026-08-24","category":"overall","updatedAt":"2026-08-26T12:00:00Z","rankings":[],"viewer":{"rank":128,"participantId":"viewer-id","displayName":"Private Runner","socialPlatform":null,"socialHandle":null,"score":2,"overallPoints":2,"activityDays":1,"nutritionDays":1,"consistencyDays":0,"hydrationDays":0,"activityKcal":250,"updatedAt":"2026-08-26T12:00:00Z","isViewer":true}}"#.utf8
        )
        let response = try JSONDecoder().decode(WeeklyChallengeLeaderboardResponse.self, from: data)

        #expect(response.rankings.isEmpty)
        #expect(response.viewer?.rank == 128)
        #expect(response.viewer?.isViewer == true)
    }

    @Test("Offline cache keeps each week and category independently")
    func categoryCache() {
        let overall = WeeklyChallengeLeaderboardResponse(
            weekStart: "2026-08-24",
            category: .overall,
            updatedAt: "2026-08-26T12:00:00Z",
            rankings: [],
            viewer: nil
        )
        let activity = WeeklyChallengeLeaderboardResponse(
            weekStart: "2026-08-24",
            category: .activity,
            updatedAt: "2026-08-26T12:01:00Z",
            rankings: [],
            viewer: nil
        )
        var cache = WeeklyChallengeLeaderboardCache()
        cache.insert(overall, savedAt: date("2026-08-26T12:00:00Z"))
        cache.insert(activity, savedAt: date("2026-08-26T12:01:00Z"))

        #expect(cache.entry(category: .overall, weekStart: "2026-08-24")?.response == overall)
        #expect(cache.entry(category: .activity, weekStart: "2026-08-24")?.response == activity)
        #expect(cache.newestEntry?.response.category == .activity)
    }

    @Test("Expired challenge credentials cannot trap deletion or enrollment")
    func staleCredentialPolicy() {
        #expect(WeeklyChallengeSessionPolicy.deletionIsComplete(statusCode: 401))
        #expect(WeeklyChallengeSessionPolicy.deletionIsComplete(statusCode: 404))
        #expect(!WeeklyChallengeSessionPolicy.deletionIsComplete(statusCode: 500))
        #expect(
            WeeklyChallengeSessionPolicy.shouldClearLocalIdentity(
                after: WeeklyChallengeAPIError.server(
                    statusCode: 401,
                    code: "unauthorized",
                    message: "Expired"
                )
            )
        )
        #expect(
            !WeeklyChallengeSessionPolicy.shouldClearLocalIdentity(
                after: WeeklyChallengeAPIError.server(
                    statusCode: 403,
                    code: "forbidden",
                    message: "Forbidden"
                )
            )
        )
    }
}

@MainActor
@Suite("Weekly Challenge auto delete")
struct WeeklyChallengeAutoDeleteTests {
    @Test("Token present and not done deletes the remote profile")
    func tokenPresentDeletes() {
        #expect(WeeklyChallengeAutoDelete.decision(isDone: false, hasToken: true) == .delete)
    }

    @Test("Done skips, with or without a token")
    func doneSkips() {
        #expect(WeeklyChallengeAutoDelete.decision(isDone: true, hasToken: true) == .skip)
        #expect(WeeklyChallengeAutoDelete.decision(isDone: true, hasToken: false) == .skip)
    }

    @Test("No token marks done with nothing to delete")
    func noTokenMarksNothingToDelete() {
        #expect(WeeklyChallengeAutoDelete.decision(isDone: false, hasToken: false) == .markNothingToDelete)
    }

    @Test("Status line and failure reasons never carry a token or server message")
    func statusLineText() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let day = date.formatted(date: .abbreviated, time: .omitted)
        let deleted = WeeklyChallengeAutoDelete.Outcome(date: date, participantID: "p-123", result: .deleted, reason: nil)
        #expect(WeeklyChallengeAutoDelete.statusLine(deleted) == "Old Weekly Challenge profile (participant p-123) deleted from fud-ai.app on \(day).")
        let nothing = WeeklyChallengeAutoDelete.Outcome(date: date, participantID: nil, result: .nothingToDelete, reason: nil)
        #expect(WeeklyChallengeAutoDelete.statusLine(nothing) == "No Weekly Challenge profile to delete (checked \(day)).")
        let failed = WeeklyChallengeAutoDelete.Outcome(date: date, participantID: nil, result: .failed, reason: "offline")
        #expect(WeeklyChallengeAutoDelete.statusLine(failed).contains("failed on \(day): offline"))

        let serverError = WeeklyChallengeAPIError.server(statusCode: 500, code: "x", message: "server body")
        #expect(WeeklyChallengeAutoDelete.shortReason(for: serverError) == "HTTP 500")
        let offline = WeeklyChallengeAPIError.transport(URLError(.notConnectedToInternet))
        #expect(WeeklyChallengeAutoDelete.shortReason(for: offline) == "offline")
        #expect(WeeklyChallengeAutoDelete.shortReason(for: WeeklyChallengeAPIError.invalidResponse) == "invalid response")
    }

    @Test("404 counts as deleted; 401/403 is token rejected, never labeled deleted")
    func deleteStatusOutcomes() {
        func server(_ status: Int) -> WeeklyChallengeAPIError {
            .server(statusCode: status, code: "x", message: "server body")
        }
        #expect(WeeklyChallengeAutoDelete.completedResult(for: server(404)) == .deleted)
        #expect(WeeklyChallengeAutoDelete.completedResult(for: server(401)) == .tokenRejected)
        #expect(WeeklyChallengeAutoDelete.completedResult(for: server(403)) == .tokenRejected)
        #expect(WeeklyChallengeAutoDelete.completedResult(for: server(500)) == nil)
        #expect(WeeklyChallengeAutoDelete.completedResult(for: WeeklyChallengeAPIError.transport(URLError(.notConnectedToInternet))) == nil)

        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let day = date.formatted(date: .abbreviated, time: .omitted)
        let rejected = WeeklyChallengeAutoDelete.Outcome(date: date, participantID: "p-123", result: .tokenRejected, reason: nil)
        let line = WeeklyChallengeAutoDelete.statusLine(rejected)
        #expect(line == "Old Weekly Challenge profile (participant p-123): token rejected (profile likely already removed by the 90-day inactivity purge) on \(day). The local credential was cleared.")
        #expect(!line.contains("deleted from"))
    }

    @Test("Outcome round-trips through its UserDefaults JSON")
    func outcomeCodable() throws {
        let outcome = WeeklyChallengeAutoDelete.Outcome(
            date: Date(timeIntervalSince1970: 1_790_000_000),
            participantID: "p-1",
            result: .failed,
            reason: "HTTP 503"
        )
        let data = try JSONEncoder().encode(outcome)
        #expect(try JSONDecoder().decode(WeeklyChallengeAutoDelete.Outcome.self, from: data) == outcome)
    }
}
