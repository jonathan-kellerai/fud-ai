//
//  CCLadderClient.swift
//  calorietracker
//
//  JL Physical — Convict Conditioning ladders over the Neon bridge.
//  GET /api/cc/ladders, POST /api/cc/events. Uses the bridge settings and
//  bearer key the same way NeonBridgeService does.
//

import Foundation

enum CCLadderClient {
    static func fetchLadders(settings: NeonBridgeSettings) async throws -> CCLaddersResponse {
        let request = try makeRequest(path: "/api/cc/ladders", method: "GET", settings: settings)
        let data = try await send(request)
        do {
            return try JSONDecoder().decode(CCLaddersResponse.self, from: data)
        } catch {
            throw NeonBridgeError.decodingError(error)
        }
    }

    static func postEvent(
        _ event: CCLadderEventRequest,
        settings: NeonBridgeSettings
    ) async throws {
        var request = try makeRequest(path: "/api/cc/events", method: "POST", settings: settings)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(event)
        _ = try await send(request)
    }

    /// Text shown on screen for a failed load or save.
    static func userMessage(for error: Error) -> String {
        if let bridgeError = error as? NeonBridgeError {
            switch bridgeError {
            case .invalidURL:
                return "The bridge URL is not valid. Check Train › Bridge."
            case .networkError:
                return "Couldn’t reach the bridge. Check your connection and try again."
            case .decodingError:
                return "Ladder data from the bridge couldn’t be read."
            case .noData:
                return "The bridge sent no data."
            case .httpError(let statusCode, let message):
                if statusCode == 401 || statusCode == 403 {
                    return "The bridge rejected the request. Check the bridge key in Train › Bridge."
                }
                if let message, !message.isEmpty {
                    return message
                }
                return "The bridge returned HTTP \(statusCode)."
            }
        }
        if error is URLError {
            return "Couldn’t reach the bridge. Check your connection and try again."
        }
        return error.localizedDescription
    }

    // MARK: - Helpers

    private static func makeRequest(path: String, method: String, settings: NeonBridgeSettings) throws -> URLRequest {
        guard let url = URL(string: settings.baseURL + path), url.scheme != nil, url.host != nil else {
            throw NeonBridgeError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = settings.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw NeonBridgeError.networkError(error)
        }
        let data = result.0
        let response = result.1
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // 409 bodies carry {"error": code, "message": ...}; prefer the message.
            let message = BridgeErrorFormatting.userMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NeonBridgeError.httpError(statusCode: http.statusCode, message: message)
        }
        return data
    }
}
