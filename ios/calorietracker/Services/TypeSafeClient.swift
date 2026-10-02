import Foundation
import os

indirect enum TypeSafeJSON: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([TypeSafeJSON])
    case object([String: TypeSafeJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([TypeSafeJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: TypeSafeJSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

enum TypeSafeQuestion: Encodable, Equatable, Sendable {
    case noul(instructions: TypeSafeJSON, criteria: (true: String, false: String)?)
    case choice(instructions: TypeSafeJSON, criteria: [(key: String, description: String?)])
    /// Choice whose option values are JSON objects, still encoded as type "choice".
    case choiceJSON(instructions: TypeSafeJSON, criteria: [(key: String, value: TypeSafeJSON)])
    case score(instructions: TypeSafeJSON, levels: [String])

    private enum CodingKeys: String, CodingKey {
        case type, instructions, criteria
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noul(let instructions, let criteria):
            try container.encode("noul", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            if let criteria {
                try container.encode(["true": criteria.true, "false": criteria.false], forKey: .criteria)
            }
        case .choice(let instructions, let criteria):
            try container.encode("choice", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            var object: [String: String?] = [:]
            for pair in criteria {
                object[pair.key] = pair.description
            }
            try container.encode(object, forKey: .criteria)
        case .choiceJSON(let instructions, let criteria):
            try container.encode("choice", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            var object: [String: TypeSafeJSON] = [:]
            for pair in criteria {
                object[pair.key] = pair.value
            }
            try container.encode(object, forKey: .criteria)
        case .score(let instructions, let levels):
            try container.encode("score", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(levels, forKey: .criteria)
        }
    }

    static func == (lhs: TypeSafeQuestion, rhs: TypeSafeQuestion) -> Bool {
        switch (lhs, rhs) {
        case let (.noul(leftInstructions, leftCriteria), .noul(rightInstructions, rightCriteria)):
            return leftInstructions == rightInstructions
                && leftCriteria?.true == rightCriteria?.true
                && leftCriteria?.false == rightCriteria?.false
        case let (.choice(leftInstructions, leftCriteria), .choice(rightInstructions, rightCriteria)):
            return leftInstructions == rightInstructions && leftCriteria.elementsEqual(rightCriteria, by: { $0 == $1 })
        case let (.choiceJSON(leftInstructions, leftCriteria), .choiceJSON(rightInstructions, rightCriteria)):
            return leftInstructions == rightInstructions && leftCriteria.elementsEqual(rightCriteria, by: { $0 == $1 })
        case let (.score(leftInstructions, leftLevels), .score(rightInstructions, rightLevels)):
            return leftInstructions == rightInstructions && leftLevels == rightLevels
        default:
            return false
        }
    }
}

struct TypeSafeRequest: Encodable, Equatable, Sendable {
    var state: TypeSafeJSON
    var model: String
    var questions: [String: TypeSafeQuestion]
}

enum TypeSafeAnswer: Decodable, Equatable, Sendable {
    case noul(Double)
    case choice(choice: String, confidence: Double, probabilities: [String: Double])
    case score(score: Double, confidence: Double, probabilities: [String: Double])
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type, noul, choice, confidence, probabilities, score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "noul":
            self = .noul(try container.decode(Double.self, forKey: .noul))
        case "choice":
            self = .choice(
                choice: try container.decode(String.self, forKey: .choice),
                confidence: try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0,
                probabilities: try container.decodeIfPresent([String: Double].self, forKey: .probabilities) ?? [:]
            )
        case "score":
            self = .score(
                score: try container.decode(Double.self, forKey: .score),
                confidence: try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0,
                probabilities: try container.decodeIfPresent([String: Double].self, forKey: .probabilities) ?? [:]
            )
        default:
            self = .unknown(type)
        }
    }
}

struct TypeSafeResponse: Decodable, Equatable, Sendable {
    var model: String
    var answers: [String: TypeSafeAnswer]
    var usage: Usage?

    struct Usage: Decodable, Equatable, Sendable {
        var inputTokens: Int?
        var outputTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

enum TypeSafeError: Error, Equatable, Sendable {
    case missingKey
    case keyRejected
    case invalidRequest
    case rateLimited
    case overloaded
    case server(Int)
    case network
    case timeout
    case invalidResponse
}

struct TypeSafeClient: Sendable {
    var baseURL: String
    var apiKey: String
    var session: URLSession = .shared
    var timeout: TimeInterval = 10
    var retryDelaysNs: [UInt64] = [500_000_000]

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "calorietracker", category: "TypeSafe")
    private static let retryAfterCapNs: UInt64 = 2_000_000_000

    func systemOne(_ request: TypeSafeRequest) async throws -> TypeSafeResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(request)
        let data = try await send(path: "/v1/systemone", method: "POST", body: body)
        do {
            return try JSONDecoder().decode(TypeSafeResponse.self, from: data)
        } catch {
            throw TypeSafeError.invalidResponse
        }
    }

    func listModels() async throws -> [CatalogModel] {
        let data = try await send(path: "/v1/models", method: "GET", body: nil)
        do {
            return try ModelCatalogParser.parseTypeSafe(data).models
        } catch {
            throw TypeSafeError.invalidResponse
        }
    }

    private func send(path: String, method: String, body: Data?) async throws -> Data {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TypeSafeError.missingKey }

        var attempt = 0
        while true {
            let urlRequest = try makeURLRequest(path: path, method: method, body: body, key: key)
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch let error as CancellationError {
                throw error
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as URLError where error.code == .timedOut {
                throw TypeSafeError.timeout
            } catch {
                throw TypeSafeError.network
            }

            guard let http = response as? HTTPURLResponse else {
                throw TypeSafeError.invalidResponse
            }
            if (200...299).contains(http.statusCode) {
                return data
            }

            let failure = mapStatus(http.statusCode, body: data)
            if shouldRetry(status: http.statusCode), attempt < retryDelaysNs.count {
                let wait = retryWaitNanoseconds(attempt: attempt, response: http)
                attempt += 1
                try await Task.sleep(nanoseconds: wait)
                continue
            }
            throw failure
        }
    }

    private func makeURLRequest(path: String, method: String, body: Data?, key: String) throws -> URLRequest {
        let root = Self.normalizedBaseURL(baseURL)
        guard let url = URL(string: root + path) else { throw TypeSafeError.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private func mapStatus(_ status: Int, body: Data) -> TypeSafeError {
        switch status {
        case 401, 403:
            return .keyRejected
        case 422:
            logValidation(body)
            return .invalidRequest
        case 429:
            return .rateLimited
        case 503, 529:
            return .overloaded
        default:
            return .server(status)
        }
    }

    private func shouldRetry(status: Int) -> Bool {
        status == 429 || (500...599).contains(status)
    }

    private func retryWaitNanoseconds(attempt: Int, response: HTTPURLResponse) -> UInt64 {
        let scheduled = attempt < retryDelaysNs.count ? retryDelaysNs[attempt] : 0
        return max(scheduled, retryAfterNanoseconds(response))
    }

    private func retryAfterNanoseconds(_ response: HTTPURLResponse) -> UInt64 {
        if let raw = response.value(forHTTPHeaderField: "retry-after-ms"), let milliseconds = Double(raw) {
            return min(UInt64(max(milliseconds, 0) * 1_000_000), Self.retryAfterCapNs)
        }
        if let raw = response.value(forHTTPHeaderField: "Retry-After"), let seconds = Double(raw) {
            return min(UInt64(max(seconds, 0) * 1_000_000_000), Self.retryAfterCapNs)
        }
        return 0
    }

    private func logValidation(_ body: Data) {
        guard
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let detail = json["detail"] as? [[String: Any]]
        else { return }
        let summary = detail.map { item -> String in
            let loc = (item["loc"] as? [Any])?.map { String(describing: $0) }.joined(separator: ".") ?? ""
            let message = item["msg"] as? String ?? ""
            return "\(loc): \(message)"
        }.joined(separator: "; ")
        Self.log.error("TypeSafe rejected the request: \(summary, privacy: .public)")
    }

    static func normalizedBaseURL(_ baseURL: String) -> String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
