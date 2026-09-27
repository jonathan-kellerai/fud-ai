//
//  NeonBridgeService.swift
//  calorietracker
//
//  JL Physical — Neon training bridge HTTP client
//

import Foundation

enum NeonBridgeError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case httpError(statusCode: Int, message: String?)
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid bridge URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode)\(message.map { ": \($0)" } ?? "")"
        case .noData:
            return "No data received"
        }
    }

    var isNotFound: Bool {
        if case .httpError(let statusCode, _) = self, statusCode == 404 {
            return true
        }
        return false
    }

    var isAlreadyCompleted: Bool {
        if case .httpError(let statusCode, let message) = self, statusCode == 409 {
            return message == "already_completed"
        }
        return false
    }

    /// The bridge did not answer with a usable program payload.
    var isConnectivityFailure: Bool {
        switch self {
        case .invalidURL, .networkError, .decodingError, .noData:
            return true
        case .httpError(let statusCode, _) where statusCode >= 500:
            return true
        default:
            return false
        }
    }
}

@Observable
final class NeonBridgeService {
    static let shared = NeonBridgeService()
    
    var settings = NeonBridgeSettings.load()
    var lastSyncDate: Date?
    var lastSyncError: String?
    
    private init() {}
    
    // MARK: - Health Check
    
    func checkHealth() async throws -> BridgeHealth {
        let url = try makeURL(path: "/api/bridge/health")
        let request = makeRequest(url: url, method: "GET")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try JSONDecoder().decode(BridgeHealth.self, from: data)
    }
    
    // MARK: - Workouts
    
    func postWorkout(_ payload: WorkoutPayload) async throws -> WorkoutResponse {
        let url = try makeURL(path: "/api/workouts")
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try JSONDecoder().decode(WorkoutResponse.self, from: data)
    }
    
    func listWorkouts(limit: Int = 50) async throws -> [RemoteWorkout] {
        let url = try makeURL(path: "/api/workouts", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)")
        ])
        let request = makeRequest(url: url, method: "GET")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        let listResponse = try JSONDecoder().decode(ListWorkoutsResponse.self, from: data)
        return listResponse.workouts
    }
    
    func getWorkout(id: String) async throws -> WorkoutDetailResponse {
        let url = try makeURL(path: "/api/workouts/\(id)")
        let request = makeRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        return try JSONDecoder().decode(WorkoutDetailResponse.self, from: data)
    }

    func updateWorkout(id: String, payload: WorkoutPayload) async throws -> WorkoutResponse {
        let url = try makeURL(path: "/api/workouts/\(id)")
        var request = makeRequest(url: url, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        if data.isEmpty {
            return WorkoutResponse(id: id, ok: true, message: nil, deduped: nil, action: "updated", contentHash: nil)
        }
        return try JSONDecoder().decode(WorkoutResponse.self, from: data)
    }

    func deleteWorkout(id: String) async throws {
        let url = try makeURL(path: "/api/workouts/\(id)")
        let request = makeRequest(url: url, method: "DELETE")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    // MARK: - Programs

    func listPrograms(status: String? = nil, lineageID: String? = nil) async throws -> [TrainingProgramRecord] {
        var items: [URLQueryItem] = []
        if let status, !status.isEmpty {
            items.append(URLQueryItem(name: "status", value: status))
        }
        if let lineageID, !lineageID.isEmpty {
            items.append(URLQueryItem(name: "lineage_id", value: lineageID))
        }
        let url = try makeURL(path: "/api/programs", queryItems: items.isEmpty ? nil : items)
        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(TrainingProgramListResponse.self, from: data).programs
    }

    func activeProgram() async throws -> TrainingProgramRecord {
        let url = try makeURL(path: "/api/programs/active")
        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decodeProgram(data)
    }

    func program(id: String) async throws -> TrainingProgramRecord {
        let url = try makeURL(path: "/api/programs/\(pathComponent(id))")
        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decodeProgram(data)
    }

    func createProgram(
        name: String,
        body: TrainingProgramBody,
        parentID: String? = nil,
        changeReason: String? = nil
    ) async throws -> TrainingProgramRecord {
        let url = try makeURL(path: "/api/programs")
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ProgramCreateRequest(
            name: name,
            body: body.normalizedForSave(),
            parentId: parentID,
            changeReason: changeReason,
            createdBy: "app"
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decodeProgram(data)
    }

    func updateDraft(
        id: String,
        name: String,
        body: TrainingProgramBody,
        changeReason: String? = nil
    ) async throws -> TrainingProgramRecord {
        let url = try makeURL(path: "/api/programs/\(pathComponent(id))")
        var request = makeRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ProgramPatchRequest(name: name, body: body.normalizedForSave(), changeReason: changeReason)
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        if let record = try? decodeProgram(data) {
            return record
        }
        return try await program(id: id)
    }

    func reviseProgram(
        id: String,
        name: String,
        body: TrainingProgramBody,
        changeReason: String,
        activate: Bool
    ) async throws -> TrainingProgramRecord {
        let url = try makeURL(path: "/api/programs/\(pathComponent(id))/revise")
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ProgramReviseRequest(
            body: body.normalizedForSave(),
            name: name,
            changeReason: changeReason,
            activate: activate,
            createdBy: "app"
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decodeProgram(data)
    }

    func activateProgram(id: String) async throws {
        let url = try makeURL(path: "/api/programs/\(pathComponent(id))/activate")
        let request = makeRequest(url: url, method: "POST")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    func peptidesToday(date: String? = nil) async throws -> PeptideTodayResponse {
        var items: [URLQueryItem] = []
        if let date, !date.isEmpty {
            items.append(URLQueryItem(name: "date", value: date))
        }
        let url = try makeURL(path: "/api/peptides/today", queryItems: items.isEmpty ? nil : items)
        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(PeptideTodayResponse.self, from: data)
    }

    func peptideInventory() async throws -> [PeptideInventoryItem] {
        let url = try makeURL(path: "/api/peptides/inventory")
        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(PeptideInventoryList.self, from: data).inventory
    }

    func peptideInventory(id: String) async throws -> PeptideInventoryItem {
        let url = try makeURL(path: "/api/peptides/inventory/\(pathComponent(id))")
        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(PeptideInventoryItem.self, from: data)
    }

    func peptideSchedules(activeOnly: Bool = false) async throws -> [PeptideSchedule] {
        let items = activeOnly ? [URLQueryItem(name: "active", value: "1")] : nil
        let url = try makeURL(path: "/api/peptides/schedules", queryItems: items)
        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(PeptideScheduleList.self, from: data).schedules
    }

    func peptideSchedule(id: String) async throws -> PeptideSchedule {
        let url = try makeURL(path: "/api/peptides/schedules/\(pathComponent(id))")
        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(PeptideSchedule.self, from: data)
    }

    func peptideAdministration(id: String) async throws -> PeptideAdministration {
        let url = try makeURL(path: "/api/peptides/administrations/\(pathComponent(id))")
        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decodePeptideAdministration(data)
    }

    func createCompletedAdministration(
        clientRequestID: String,
        plannedID: String?,
        datetime: String,
        dose: Double?,
        units: String?,
        compound: String?,
        route: String?,
        notes: String?,
        sourceVial: String?
    ) async throws -> PeptideAdministration {
        let url = try makeURL(path: "/api/peptides/administrations")
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "client_request_id": clientRequestID,
            "datetime": datetime,
        ]
        if let plannedID, !plannedID.isEmpty { body["planned_id"] = plannedID }
        if let dose { body["dose"] = dose }
        if let units, !units.isEmpty { body["units"] = units }
        if let compound, !compound.isEmpty { body["compound"] = compound }
        if let route, !route.isEmpty { body["route"] = route }
        if let notes, !notes.isEmpty { body["notes"] = notes }
        if let sourceVial, !sourceVial.isEmpty { body["source_vial"] = sourceVial }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           http.statusCode == 409,
           BridgeErrorFormatting.errorCode(from: data) == "already_completed" {
            throw NeonBridgeError.httpError(statusCode: 409, message: "already_completed")
        }
        try validateResponse(response, data: data)
        return try decodePeptideAdministration(data)
    }

    func correctAdministration(
        id: String,
        reason: String,
        changes: [String: Any]
    ) async throws -> PeptideAdministration {
        try await patchAdministration(id: id, body: [
            "action": "correct",
            "reason": reason,
            "changes": changes,
        ])
    }

    func voidAdministration(id: String, reason: String) async throws -> PeptideAdministration {
        try await patchAdministration(id: id, body: [
            "action": "void",
            "reason": reason,
        ])
    }

    private func patchAdministration(id: String, body: [String: Any]) async throws -> PeptideAdministration {
        let url = try makeURL(path: "/api/peptides/administrations/\(pathComponent(id))")
        var request = makeRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decodePeptideAdministration(data)
    }

    private func decodePeptideAdministration(_ data: Data) throws -> PeptideAdministration {
        let decoder = JSONDecoder()
        if let row = try? decoder.decode(PeptideAdministration.self, from: data), !row.id.isEmpty {
            return row
        }
        struct Envelope: Decodable { let administration: PeptideAdministration? }
        if let envelope = try? decoder.decode(Envelope.self, from: data), let row = envelope.administration, !row.id.isEmpty {
            return row
        }
        throw NeonBridgeError.decodingError(
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Peptide response was not an administration row"))
        )
    }

    func deleteDraft(id: String) async throws {
        let url = try makeURL(path: "/api/programs/\(pathComponent(id))")
        let request = makeRequest(url: url, method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }
    
    // MARK: - Steps
    
    func postSteps(_ payload: StepsPayload) async throws -> StepsResponse {
        let url = try makeURL(path: "/api/steps")
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try JSONDecoder().decode(StepsResponse.self, from: data)
    }
    
    func getSteps(days: Int = 7) async throws -> StepsListResponse {
        let url = try makeURL(path: "/api/steps", queryItems: [
            URLQueryItem(name: "days", value: "\(days)")
        ])
        let request = makeRequest(url: url, method: "GET")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        
        return try JSONDecoder().decode(StepsListResponse.self, from: data)
    }
    
    // MARK: - Helper Methods
    
    private func makeURL(path: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        var components = URLComponents(string: settings.baseURL + path)
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            throw NeonBridgeError.invalidURL
        }
        
        return url
    }
    
    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let apiKey = settings.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        return request
    }
    
    private func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func decodeProgram(_ data: Data) throws -> TrainingProgramRecord {
        let decoder = JSONDecoder()
        if let record = try? decoder.decode(TrainingProgramRecord.self, from: data), !record.id.isEmpty {
            return record
        }
        if let envelope = try? decoder.decode(TrainingProgramEnvelope.self, from: data), let program = envelope.program {
            return program
        }
        throw NeonBridgeError.decodingError(
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Program response was not a program row"))
        )
    }

    private func validateResponse(_ response: URLResponse, data: Data = Data()) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NeonBridgeError.httpError(
                statusCode: httpResponse.statusCode,
                message: BridgeErrorFormatting.userMessage(from: data)
                    ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
    }
}

enum BridgeErrorFormatting {
    static func userMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        if let issues = object["issues"] as? [Any] {
            let lines = issues.compactMap { issue -> String? in
                if let text = issue as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                if let fields = issue as? [String: Any] {
                    if let message = fields["message"] as? String, !message.isEmpty { return message }
                    if let path = fields["path"] as? String, !path.isEmpty { return path }
                }
                return nil
            }
            if !lines.isEmpty {
                return lines.joined(separator: "\n")
            }
        }
        if let error = object["error"] as? String, !error.isEmpty {
            return error
        }
        return nil
    }

    static func errorCode(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? String,
              !error.isEmpty else {
            return nil
        }
        return error
    }
}
