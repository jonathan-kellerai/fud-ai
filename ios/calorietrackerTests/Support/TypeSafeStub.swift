import Foundation

/// Shared URLProtocol stub for TypeSafe tests. Never touches the Keychain.
nonisolated final class TypeSafeStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest, Data?) throws -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var requests: [(URLRequest, Data?)] = []
    nonisolated(unsafe) static var delay: TimeInterval = 0
    nonisolated(unsafe) private static var generation = 0

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
        let delay = Self.delay
        let generation = Self.generation
        let currentRequest = request
        let currentBody = body
        let deliver = {
            guard generation == Self.generation else { return }
            Self.requests.append((currentRequest, currentBody))
            do {
                let (status, headers, data) = try Self.handler!(currentRequest, currentBody)
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: deliver)
        } else {
            deliver()
        }
    }

    nonisolated override func stopLoading() {}

    nonisolated static func reset() {
        generation += 1
        handler = nil
        requests = []
        delay = 0
    }
}
