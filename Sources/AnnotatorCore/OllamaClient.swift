import Foundation

public enum OllamaError: LocalizedError {
    case notRunning
    case modelMissing(String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Can't reach Ollama. Open the Ollama app (or run `ollama serve`) and try again."
        case .modelMissing(let m):
            return "The model \"\(m)\" isn't installed. Run `ollama pull \(m)` in Terminal."
        case .badResponse(let s):
            return "Ollama returned an unexpected response: \(s)"
        }
    }
}

public struct OllamaClient: Sendable {
    public var baseURL: URL

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.baseURL = baseURL
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }()

    public func listModels() async throws -> [String] {
        struct Tags: Decodable { struct Model: Decodable { var name: String }; var models: [Model] }
        var req = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 5
        let (data, _) = try await send(req)
        return try JSONDecoder().decode(Tags.self, from: data).models.map(\.name).sorted()
    }

    /// Sends one chat turn constrained to `schema` and decodes the model's JSON reply.
    /// Retries once if the reply doesn't decode.
    public func chat<T: Decodable>(model: String, system: String, user: String, images: [Data] = [],
                                   schema: [String: Any], numCtx: Int = 8192, as type: T.Type) async throws -> T {
        var lastError: Error?
        for _ in 0..<2 {
            let content = try await chatRaw(model: model, system: system, user: user, images: images,
                                             schema: schema, numCtx: numCtx)
            do {
                return try JSONDecoder().decode(T.self, from: Data(content.utf8))
            } catch {
                lastError = OllamaError.badResponse(String(content.prefix(200)))
            }
        }
        throw lastError ?? OllamaError.badResponse("empty")
    }

    public func chatRaw(model: String, system: String, user: String, images: [Data],
                        schema: [String: Any], numCtx: Int) async throws -> String {
        var userMessage: [String: Any] = ["role": "user", "content": user]
        if !images.isEmpty { userMessage["images"] = images.map { $0.base64EncodedString() } }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], userMessage],
            "stream": false,
            "format": schema,
            "keep_alive": "15m",
            "options": ["temperature": 0.2, "num_ctx": numCtx],
        ]
        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        struct Reply: Decodable { struct Message: Decodable { var content: String }; var message: Message }
        let (data, http) = try await send(req)
        if http.statusCode == 404 { throw OllamaError.modelMissing(model) }
        guard http.statusCode == 200 else {
            throw OllamaError.badResponse(String(decoding: data.prefix(300), as: UTF8.self))
        }
        return try JSONDecoder().decode(Reply.self, from: data).message.content
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, resp) = try await Self.session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw OllamaError.badResponse("no HTTP response") }
            return (data, http)
        } catch let e as URLError where [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost].contains(e.code) {
            throw OllamaError.notRunning
        }
    }
}

extension OllamaClient {
    /// Whether the model accepts images (Ollama reports a "vision" capability).
    public func supportsVision(model: String) async -> Bool {
        struct Show: Decodable { var capabilities: [String]? }
        var req = URLRequest(url: baseURL.appendingPathComponent("api/show"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model])
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let show = try? JSONDecoder().decode(Show.self, from: data) else { return false }
        return show.capabilities?.contains("vision") ?? false
    }
}
