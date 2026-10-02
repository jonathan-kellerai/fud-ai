import Foundation
import Observation

enum WeeklyChallengeSessionPolicy {
    static func shouldClearLocalIdentity(after error: Error) -> Bool {
        guard let apiError = error as? WeeklyChallengeAPIError,
              case .server(let statusCode, _, _) = apiError
        else {
            return false
        }
        return statusCode == 401
    }

    static func deletionIsComplete(statusCode: Int) -> Bool {
        statusCode == 401 || statusCode == 404
    }
}

/// JL Physical does not use the upstream Weekly Challenge. A profile joined on
/// an earlier build is deleted from fud-ai.app once, automatically, at launch.
enum WeeklyChallengeAutoDelete {
    static let doneKey = "jl.weeklyChallengeAutoDelete.v1.done"
    static let outcomeKey = "jl.weeklyChallengeAutoDelete.v1.outcome"

    enum Decision: Equatable {
        /// Already finished on an earlier launch.
        case skip
        /// A bearer token is in Keychain: delete the remote profile.
        case delete
        /// No token, so nothing exists remotely that this device can reach.
        case markNothingToDelete
    }

    enum Result: String, Codable, Equatable {
        case deleted
        case nothingToDelete
        case failed
        /// 401/403: the server no longer accepts the token. Done, but not confirmed deleted.
        case tokenRejected
    }

    static let tokenRejectedText = "token rejected (profile likely already removed by the 90-day inactivity purge)"

    struct Outcome: Codable, Equatable {
        var date: Date
        var participantID: String?
        var result: Result
        /// Short, token-free reason for a failure.
        var reason: String?
    }

    static func decision(isDone: Bool, hasToken: Bool) -> Decision {
        if isDone { return .skip }
        return hasToken ? .delete : .markNothingToDelete
    }

    /// One read-only line for Settings.
    static func statusLine(_ outcome: Outcome) -> String {
        let date = outcome.date.formatted(date: .abbreviated, time: .omitted)
        let participant = outcome.participantID.map { " (participant \($0))" } ?? ""
        switch outcome.result {
        case .deleted:
            return "Old Weekly Challenge profile\(participant) deleted from fud-ai.app on \(date)."
        case .nothingToDelete:
            return "No Weekly Challenge profile to delete (checked \(date))."
        case .failed:
            let reason = outcome.reason.map { ": \($0)" } ?? ""
            return "Deleting the old Weekly Challenge profile\(participant) failed on \(date)\(reason). It retries at next launch."
        case .tokenRejected:
            return "Old Weekly Challenge profile\(participant): \(tokenRejectedText) on \(date). The local credential was cleared."
        }
    }

    /// A delete error that still finishes the cleanup: 404 means the profile is gone;
    /// 401/403 means the token can't be retried. Anything else is a failure that retries.
    static func completedResult(for error: Error) -> Result? {
        guard let apiError = error as? WeeklyChallengeAPIError,
              case .server(let statusCode, _, _) = apiError
        else {
            return nil
        }
        switch statusCode {
        case 404: return .deleted
        case 401, 403: return .tokenRejected
        default: return nil
        }
    }

    /// Never includes the token or a server message body.
    static func shortReason(for error: Error) -> String {
        guard let apiError = error as? WeeklyChallengeAPIError else { return "unexpected error" }
        switch apiError {
        case .invalidRequest: return "invalid request"
        case .invalidResponse: return "invalid response"
        case .transport(let urlError): return apiError.isOffline ? "offline" : "network error \(urlError.code.rawValue)"
        case .server(let statusCode, _, _): return "HTTP \(statusCode)"
        }
    }
}

struct WeeklyChallengeLeaderboardCache: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let response: WeeklyChallengeLeaderboardResponse
        let savedAt: Date
    }

    private(set) var entries: [String: Entry] = [:]

    static func key(category: WeeklyChallengeCategory, weekStart: String) -> String {
        "\(weekStart)|\(category.rawValue)"
    }

    func entry(category: WeeklyChallengeCategory, weekStart: String) -> Entry? {
        entries[Self.key(category: category, weekStart: weekStart)]
    }

    mutating func insert(_ response: WeeklyChallengeLeaderboardResponse, savedAt: Date) {
        entries[Self.key(category: response.category, weekStart: response.weekStart)] = Entry(
            response: response,
            savedAt: savedAt
        )
        if entries.count > 30 {
            let retainedKeys = Set(
                entries.sorted { $0.value.savedAt > $1.value.savedAt }
                    .prefix(30)
                    .map { $0.key }
            )
            entries = entries.filter { retainedKeys.contains($0.key) }
        }
    }

    var newestEntry: Entry? {
        entries.values.max { $0.savedAt < $1.savedAt }
    }

    var knownParticipants: [WeeklyChallengeParticipant] {
        var participants: [String: WeeklyChallengeParticipant] = [:]
        for entry in entries.values {
            for participant in entry.response.rankings {
                participants[participant.participantId] = participant
            }
            if let viewer = entry.response.viewer {
                participants[viewer.participantId] = viewer
            }
        }
        return Array(participants.values)
    }
}

@Observable
@MainActor
final class WeeklyChallengeStore {
    private struct CachedLeaderboard: Codable {
        let response: WeeklyChallengeLeaderboardResponse
        let savedAt: Date
    }

    private static let tokenKey = "weeklyChallenge.bearerToken.v1"
    private static let participantIDKey = "weeklyChallenge.participantID.v1"
    private static let publicProfileKey = "weeklyChallenge.publicProfile.v1"
    private static let cachedLeaderboardKey = "weeklyChallenge.cachedLeaderboard.v1"
    private static let pendingScoreKey = "weeklyChallenge.pendingScore.v1"
    private static let pendingDeletionKey = "weeklyChallenge.pendingDeletion.v1"
    private static let blockedParticipantIDsKey = "weeklyChallenge.blockedParticipantIDs.v1"

    private(set) var leaderboard: WeeklyChallengeLeaderboardResponse?
    private(set) var publicProfile: WeeklyChallengePublicProfile?
    private(set) var participantID: String?
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private(set) var isProfileMutationInProgress = false
    private(set) var isSubmittingReport = false
    private(set) var isOffline = false
    private(set) var errorMessage: String?
    private(set) var hasPendingDeletion = false
    private(set) var blockedParticipantIDs: Set<String> = []
    private(set) var autoDeleteOutcome: WeeklyChallengeAutoDelete.Outcome?

    private let defaults: UserDefaults
    private let api: WeeklyChallengeAPIClient
    private var pendingScore: WeeklyChallengeScore?
    private var leaderboardCache = WeeklyChallengeLeaderboardCache()
    private var refreshGeneration = 0

    init(
        defaults: UserDefaults = .standard,
        api: WeeklyChallengeAPIClient = WeeklyChallengeAPIClient()
    ) {
        self.defaults = defaults
        self.api = api
        participantID = defaults.string(forKey: Self.participantIDKey)
        publicProfile = Self.decode(
            WeeklyChallengePublicProfile.self,
            from: defaults.data(forKey: Self.publicProfileKey)
        )
        pendingScore = Self.decode(
            WeeklyChallengeScore.self,
            from: defaults.data(forKey: Self.pendingScoreKey)
        )
        hasPendingDeletion = KeychainHelper.load(key: Self.pendingDeletionKey) == "1"
        blockedParticipantIDs = Set(
            defaults.stringArray(forKey: Self.blockedParticipantIDsKey) ?? []
        )
        autoDeleteOutcome = Self.decode(
            WeeklyChallengeAutoDelete.Outcome.self,
            from: defaults.data(forKey: WeeklyChallengeAutoDelete.outcomeKey)
        )
        if let cache = Self.decode(
            WeeklyChallengeLeaderboardCache.self,
            from: defaults.data(forKey: Self.cachedLeaderboardKey)
        ) {
            leaderboardCache = cache
            if let newest = cache.newestEntry {
                leaderboard = newest.response
                lastUpdated = Self.serverDate(newest.response.updatedAt) ?? newest.savedAt
            }
        } else if let legacy = Self.decode(
            CachedLeaderboard.self,
            from: defaults.data(forKey: Self.cachedLeaderboardKey)
        ) {
            leaderboardCache.insert(legacy.response, savedAt: legacy.savedAt)
            leaderboard = legacy.response
            lastUpdated = Self.serverDate(legacy.response.updatedAt) ?? legacy.savedAt
            persist(leaderboardCache, key: Self.cachedLeaderboardKey)
        }

        // A public id without its private bearer cannot update or delete the
        // profile. Drop the incomplete local identity instead of presenting it
        // as a recoverable account.
        if hasPendingDeletion {
            if bearerToken == nil {
                KeychainHelper.delete(key: Self.pendingDeletionKey)
                hasPendingDeletion = false
                clearLocalIdentity(deleteCredential: false)
            }
        } else if participantID != nil, bearerToken == nil {
            clearLocalIdentity()
        } else if participantID == nil, bearerToken != nil {
            // JL Physical: keep the orphaned bearer and queue a remote delete
            // so the old fud-ai.app profile is removed instead of stranded.
            markDeletionPending()
        }
    }

    /// One-time launch cleanup. Returns true when it attempted a remote delete,
    /// so the caller can skip the separate pending-deletion retry this launch.
    @discardableResult
    func runOneTimeAutoDeleteIfNeeded() async -> Bool {
        let decision = WeeklyChallengeAutoDelete.decision(
            isDone: defaults.bool(forKey: WeeklyChallengeAutoDelete.doneKey),
            hasToken: bearerToken != nil
        )
        switch decision {
        case .skip:
            return false
        case .markNothingToDelete:
            clearLocalIdentity()
            recordAutoDelete(.nothingToDelete, participantID: nil, reason: nil, done: true)
            return false
        case .delete:
            guard let token = bearerToken else { return false }
            let knownParticipantID = participantID
            markDeletionPending()
            do {
                // Not deleteRemoteProfile: it treats 401 as deleted, and this records which it was.
                let response = try await api.deleteProfile(token: token)
                guard response.deleted else { throw WeeklyChallengeAPIError.invalidResponse }
                clearLocalIdentity()
                isOffline = false
                recordAutoDelete(.deleted, participantID: knownParticipantID, reason: nil, done: true)
            } catch is CancellationError {
                // The pending marker and credential stay in Keychain.
            } catch let error where WeeklyChallengeAutoDelete.completedResult(for: error) != nil {
                clearLocalIdentity()
                isOffline = false
                recordAutoDelete(
                    WeeklyChallengeAutoDelete.completedResult(for: error) ?? .failed,
                    participantID: knownParticipantID,
                    reason: nil,
                    done: true
                )
            } catch {
                // Not done: the pending marker and credential stay in Keychain
                // and the next launch tries again.
                if let apiError = error as? WeeklyChallengeAPIError, apiError.isOffline {
                    isOffline = true
                }
                recordAutoDelete(
                    .failed,
                    participantID: knownParticipantID,
                    reason: WeeklyChallengeAutoDelete.shortReason(for: error),
                    done: false
                )
            }
            return true
        }
    }

    private func recordAutoDelete(
        _ result: WeeklyChallengeAutoDelete.Result,
        participantID: String?,
        reason: String?,
        done: Bool
    ) {
        let outcome = WeeklyChallengeAutoDelete.Outcome(
            date: .now,
            participantID: participantID,
            result: result,
            reason: reason
        )
        autoDeleteOutcome = outcome
        persist(outcome, key: WeeklyChallengeAutoDelete.outcomeKey)
        if done {
            defaults.set(true, forKey: WeeklyChallengeAutoDelete.doneKey)
        }
    }

    var isJoined: Bool {
        !hasPendingDeletion && participantID != nil && bearerToken != nil
    }

    var viewer: WeeklyChallengeParticipant? {
        if let viewer = leaderboard?.viewer { return viewer }
        guard let participantID else { return nil }
        return leaderboard?.rankings.first {
            $0.participantId == participantID || $0.isViewer
        }
    }

    var knownParticipants: [WeeklyChallengeParticipant] {
        leaderboardCache.knownParticipants
    }

    func leaderboardFor(
        category: WeeklyChallengeCategory,
        weekStart: String
    ) -> WeeklyChallengeLeaderboardResponse? {
        if let leaderboard,
           leaderboard.category == category,
           leaderboard.weekStart == weekStart {
            return leaderboard
        }
        return leaderboardCache.entry(category: category, weekStart: weekStart)?.response
    }

    func viewerFor(
        category: WeeklyChallengeCategory,
        weekStart: String
    ) -> WeeklyChallengeParticipant? {
        guard let response = leaderboardFor(category: category, weekStart: weekStart) else {
            return nil
        }
        if let viewer = response.viewer { return viewer }
        guard let participantID else { return nil }
        return response.rankings.first {
            $0.participantId == participantID || $0.isViewer
        }
    }

    func lastUpdatedFor(
        category: WeeklyChallengeCategory,
        weekStart: String
    ) -> Date? {
        if let leaderboard,
           leaderboard.category == category,
           leaderboard.weekStart == weekStart {
            return lastUpdated
        }
        guard let entry = leaderboardCache.entry(category: category, weekStart: weekStart) else {
            return nil
        }
        return Self.serverDate(entry.response.updatedAt) ?? entry.savedAt
    }

    func refresh(
        category: WeeklyChallengeCategory,
        score: WeeklyChallengeScore
    ) async {
        guard isJoined, let token = bearerToken else {
            isRefreshing = false
            return
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true

        queueLatest(score)
        await syncPendingScore()
        guard isJoined else {
            if generation == refreshGeneration { isRefreshing = false }
            return
        }

        do {
            let response = try await api.leaderboard(
                category: category,
                weekStart: score.weekStart,
                token: token
            )
            guard generation == refreshGeneration else { return }
            leaderboard = response
            lastUpdated = Self.serverDate(response.updatedAt) ?? .now
            isOffline = false
            errorMessage = nil
            persistLeaderboard(response)
        } catch is CancellationError {
            return
        } catch {
            guard generation == refreshGeneration else { return }
            if WeeklyChallengeSessionPolicy.shouldClearLocalIdentity(after: error) {
                // The server may have removed an inactive profile. Discard an
                // unusable local enrollment so the person can opt in again.
                clearLocalIdentity()
                isOffline = false
            } else {
                record(
                    error,
                    fallback: WeeklyChallengeL10n.text("The leaderboard could not be updated. Pull down to try again.")
                )
            }
        }

        if generation == refreshGeneration {
            isRefreshing = false
        }
    }

    @discardableResult
    func join(
        input: WeeklyChallengeProfileInput,
        acceptedRules: Bool,
        eligibilityAccepted: Bool,
        score: WeeklyChallengeScore,
        category: WeeklyChallengeCategory
    ) async -> Bool {
        guard !isProfileMutationInProgress,
              !hasPendingDeletion,
              acceptedRules,
              eligibilityAccepted
        else {
            return false
        }
        isProfileMutationInProgress = true
        errorMessage = nil
        defer { isProfileMutationInProgress = false }

        do {
            let response = try await api.createProfile(
                WeeklyChallengeCreateProfileRequest(
                    profile: input,
                    acceptedRules: acceptedRules,
                    eligibilityAccepted: eligibilityAccepted
                )
            )
            guard !response.participantId.isEmpty, !response.bearerToken.isEmpty else {
                throw WeeklyChallengeAPIError.invalidResponse
            }
            participantID = response.participantId
            publicProfile = response.profile
            defaults.set(response.participantId, forKey: Self.participantIDKey)
            KeychainHelper.save(key: Self.tokenKey, value: response.bearerToken)
            persistPublicProfile(response.profile)
            // `refresh` queues and uploads the latest aggregate before fetching
            // rankings, so joining performs a single idempotent score PUT.
            await refresh(category: category, score: score)
            if isJoined { return true }
            errorMessage = WeeklyChallengeL10n.text("Fud AI could not join the challenge. Try again.")
            return false
        } catch {
            if WeeklyChallengeSessionPolicy.shouldClearLocalIdentity(after: error) {
                clearLocalIdentity()
                isOffline = false
            }
            record(
                error,
                fallback: WeeklyChallengeL10n.text("Fud AI could not join the challenge. Try again.")
            )
            return false
        }
    }

    @discardableResult
    func updateProfile(_ input: WeeklyChallengeProfileInput) async -> Bool {
        guard !isProfileMutationInProgress, let token = bearerToken else { return false }
        isProfileMutationInProgress = true
        errorMessage = nil
        defer { isProfileMutationInProgress = false }

        do {
            let response = try await api.updateProfile(input, token: token)
            publicProfile = response.profile
            persistPublicProfile(response.profile)
            isOffline = false
            return true
        } catch {
            if WeeklyChallengeSessionPolicy.shouldClearLocalIdentity(after: error) {
                clearLocalIdentity()
                isOffline = false
            }
            record(
                error,
                fallback: WeeklyChallengeL10n.text("Your public challenge profile could not be updated.")
            )
            return false
        }
    }

    @discardableResult
    func leaveAndDeleteRemoteData() async -> Bool {
        guard !isProfileMutationInProgress, let token = bearerToken else { return false }
        isProfileMutationInProgress = true
        errorMessage = nil
        markDeletionPending()
        defer { isProfileMutationInProgress = false }

        do {
            try await deleteRemoteProfile(token: token)
            clearLocalIdentity()
            isOffline = false
            return true
        } catch {
            // Keep the bearer credential when deletion fails. It is required to
            // retry and is safer than leaving an unreachable remote profile.
            record(
                error,
                fallback: WeeklyChallengeL10n.text("Remote challenge data was not deleted. Check your connection and try again.")
            )
            return false
        }
    }

    /// Used by Settings > Delete Everything. The pending marker and bearer live
    /// in Keychain so wiping UserDefaults cannot make a failed remote deletion
    /// impossible to retry on the next launch.
    @discardableResult
    func deleteRemoteProfileForFullReset() async -> Bool {
        guard let token = bearerToken else {
            clearLocalIdentity()
            return true
        }
        markDeletionPending()
        do {
            try await deleteRemoteProfile(token: token)
            clearLocalIdentity()
            isOffline = false
            return true
        } catch {
            record(
                error,
                fallback: WeeklyChallengeL10n.text("Challenge deletion is pending and will retry automatically when Fud AI is online.")
            )
            return false
        }
    }

    func retryPendingDeletionIfNeeded() async {
        guard hasPendingDeletion else { return }
        guard let token = bearerToken else {
            clearLocalIdentity()
            return
        }
        do {
            try await deleteRemoteProfile(token: token)
            clearLocalIdentity()
            isOffline = false
        } catch {
            // This retry is intentionally quiet at launch. The pending marker
            // and credential remain in Keychain for the next attempt.
            if let apiError = error as? WeeklyChallengeAPIError, apiError.isOffline {
                isOffline = true
            }
        }
    }

    func block(_ participant: WeeklyChallengeParticipant) {
        guard !participant.isViewer, participant.participantId != participantID else { return }
        blockedParticipantIDs.insert(participant.participantId)
        defaults.set(Array(blockedParticipantIDs).sorted(), forKey: Self.blockedParticipantIDsKey)
    }

    func unblock(participantID: String) {
        blockedParticipantIDs.remove(participantID)
        defaults.set(Array(blockedParticipantIDs).sorted(), forKey: Self.blockedParticipantIDsKey)
    }

    func isBlocked(participantID: String) -> Bool {
        blockedParticipantIDs.contains(participantID)
    }

    @discardableResult
    func report(
        participant: WeeklyChallengeParticipant,
        reason: WeeklyChallengeReportReason,
        details: String
    ) async -> Bool {
        guard !isSubmittingReport,
              isJoined,
              !participant.isViewer,
              participant.participantId != participantID,
              let token = bearerToken
        else { return false }

        let sanitizedDetails = WeeklyChallengeReportDetailsValidator.submissionValue(details)
        isSubmittingReport = true
        errorMessage = nil
        defer { isSubmittingReport = false }

        do {
            _ = try await api.report(
                WeeklyChallengeReportRequest(
                    reportedParticipantId: participant.participantId,
                    reason: reason,
                    details: sanitizedDetails
                ),
                token: token
            )
            isOffline = false
            return true
        } catch {
            if WeeklyChallengeSessionPolicy.shouldClearLocalIdentity(after: error) {
                clearLocalIdentity()
                isOffline = false
            }
            record(
                error,
                fallback: WeeklyChallengeL10n.text("The report could not be sent. Try again.")
            )
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private var bearerToken: String? {
        KeychainHelper.load(key: Self.tokenKey)
    }

    private func queueLatest(_ score: WeeklyChallengeScore) {
        guard isJoined else { return }
        pendingScore = score
        persist(score, key: Self.pendingScoreKey)
    }

    private func syncPendingScore() async {
        guard let token = bearerToken, let pendingScore else { return }
        do {
            _ = try await api.putWeeklyScore(pendingScore, token: token)
            if self.pendingScore == pendingScore {
                self.pendingScore = nil
                defaults.removeObject(forKey: Self.pendingScoreKey)
            }
            isOffline = false
        } catch is CancellationError {
            return
        } catch {
            if WeeklyChallengeSessionPolicy.shouldClearLocalIdentity(after: error) {
                clearLocalIdentity()
                isOffline = false
            } else {
                record(
                    error,
                    fallback: WeeklyChallengeL10n.text("Your latest weekly totals are saved on this device and will retry automatically.")
                )
            }
        }
    }

    private func markDeletionPending() {
        KeychainHelper.save(key: Self.pendingDeletionKey, value: "1")
        hasPendingDeletion = true
    }

    private func deleteRemoteProfile(token: String) async throws {
        do {
            let response = try await api.deleteProfile(token: token)
            guard response.deleted else { throw WeeklyChallengeAPIError.invalidResponse }
        } catch WeeklyChallengeAPIError.server(let statusCode, _, _)
            where WeeklyChallengeSessionPolicy.deletionIsComplete(statusCode: statusCode) {
            // DELETE retries are idempotent from the app's perspective. A
            // missing or no-longer-authenticatable profile means this credential
            // cannot reference remaining public challenge data.
        }
    }

    private func clearLocalIdentity(deleteCredential: Bool = true) {
        participantID = nil
        publicProfile = nil
        pendingScore = nil
        leaderboard = nil
        lastUpdated = nil
        leaderboardCache = WeeklyChallengeLeaderboardCache()
        defaults.removeObject(forKey: Self.participantIDKey)
        defaults.removeObject(forKey: Self.publicProfileKey)
        defaults.removeObject(forKey: Self.pendingScoreKey)
        defaults.removeObject(forKey: Self.cachedLeaderboardKey)
        if deleteCredential {
            KeychainHelper.delete(key: Self.tokenKey)
            KeychainHelper.delete(key: Self.pendingDeletionKey)
            hasPendingDeletion = false
        }
    }

    private func persistLeaderboard(_ response: WeeklyChallengeLeaderboardResponse) {
        leaderboardCache.insert(response, savedAt: .now)
        persist(leaderboardCache, key: Self.cachedLeaderboardKey)
    }

    private func persistPublicProfile(_ profile: WeeklyChallengePublicProfile) {
        persist(profile, key: Self.publicProfileKey)
    }

    private func persist<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func record(_ error: Error, fallback: String) {
        if let apiError = error as? WeeklyChallengeAPIError, apiError.isOffline {
            isOffline = true
            errorMessage = nil
        } else {
            errorMessage = fallback
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func serverDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
