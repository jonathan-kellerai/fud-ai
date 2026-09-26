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
        try validateResponse(response)
        
        return try JSONDecoder().decode(BridgeHealth.self, from: data)
    }
    
    // MARK: - Workouts
    
    func postWorkout(_ payload: WorkoutPayload) async throws -> WorkoutResponse {
        let url = try makeURL(path: "/api/workouts")
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        
        return try JSONDecoder().decode(WorkoutResponse.self, from: data)
    }
    
    func listWorkouts(limit: Int = 50) async throws -> [RemoteWorkout] {
        let url = try makeURL(path: "/api/workouts", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)")
        ])
        let request = makeRequest(url: url, method: "GET")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        
        let listResponse = try JSONDecoder().decode(ListWorkoutsResponse.self, from: data)
        return listResponse.workouts
    }
    
    func getWorkout(id: String) async throws -> WorkoutDetailResponse {
        let url = try makeURL(path: "/api/workouts/\(id)")
        let request = makeRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode(WorkoutDetailResponse.self, from: data)
    }

    func updateWorkout(id: String, payload: WorkoutPayload) async throws -> WorkoutResponse {
        let url = try makeURL(path: "/api/workouts/\(id)")
        var request = makeRequest(url: url, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        if data.isEmpty {
            return WorkoutResponse(id: id, ok: true, message: nil, deduped: nil, action: "updated", contentHash: nil)
        }
        return try JSONDecoder().decode(WorkoutResponse.self, from: data)
    }

    func deleteWorkout(id: String) async throws {
        let url = try makeURL(path: "/api/workouts/\(id)")
        let request = makeRequest(url: url, method: "DELETE")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
    }
    
    // MARK: - Steps
    
    func postSteps(_ payload: StepsPayload) async throws -> StepsResponse {
        let url = try makeURL(path: "/api/steps")
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        
        return try JSONDecoder().decode(StepsResponse.self, from: data)
    }
    
    func getSteps(days: Int = 7) async throws -> StepsListResponse {
        let url = try makeURL(path: "/api/steps", queryItems: [
            URLQueryItem(name: "days", value: "\(days)")
        ])
        let request = makeRequest(url: url, method: "GET")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        
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
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NeonBridgeError.httpError(
                statusCode: httpResponse.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
    }
}
