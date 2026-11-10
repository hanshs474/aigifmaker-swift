import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Official Swift SDK for AI GIF Maker (https://aigifmaker.ai): turn text into animated GIFs.
///
/// Create an API key at https://aigifmaker.ai/settings/apikeys and pass it in, or set
/// `AIGIFMAKER_API_KEY`. Each GIF costs 1 credit on your AI GIF Maker account, the same
/// as on the website.
///
///     let gif = AIGifMaker()
///     let url = try await gif.generate("a corgi in sunglasses dancing on a beach")
public struct AIGifMaker {
    public static let baseURL = URL(string: "https://aigifmaker.ai")!
    public static let keysURL = "https://aigifmaker.ai/settings/apikeys"
    public static let pricingURL = "https://aigifmaker.ai/pricing"
    public static let version = "0.1.0"

    public enum AIGifMakerError: Error, LocalizedError, Equatable {
        /// No API key, or the key is invalid or deleted.
        case auth(String)
        /// The account is out of credits.
        case quota(String)
        /// The content filter refused the prompt, or a cooldown is active. Reword it.
        case rejected(String)
        /// The GIF was accepted but the run failed; the message says why.
        case failed(String)
        /// The wait ran out; the GIF may still finish in your AI GIF Maker history.
        case timeout(String)
        /// Any other refusal, with the server's message.
        case api(String)

        public var errorDescription: String? {
            switch self {
            case .auth(let m): return "aigifmaker: API key missing or invalid: \(m)"
            case .quota(let m): return "aigifmaker: out of credits: \(m); top up at \(AIGifMaker.pricingURL)"
            case .rejected(let m): return "aigifmaker: the prompt was refused: \(m)"
            case .failed(let m): return "aigifmaker: generation failed: \(m)"
            case .timeout(let id): return "aigifmaker: still running; task \(id) may finish later in your history"
            case .api(let m): return "aigifmaker: \(m)"
            }
        }
    }

    /// One task as `/api/ai/query` reports it.
    public struct Status {
        public let id: String
        /// "pending", "processing", "success" or "failed".
        public let status: String
        /// The finished GIF when `status` is "success".
        public let url: URL?
        /// True while a run from an account without purchased credits waits in the queue.
        public let queued: Bool
        public let errorMessage: String?
        public let failureKind: String?
    }

    /// Sends one POST with a JSON body and returns the decoded JSON answer. Replaceable in tests.
    public typealias Transport = (_ url: URL, _ body: [String: Any], _ apiKey: String) async throws -> [String: Any]

    public let apiKey: String
    public let base: URL
    public var pollInterval: TimeInterval = 3
    public var timeout: TimeInterval = 900
    private let transport: Transport

    public init(apiKey: String? = nil, baseURL: URL = AIGifMaker.baseURL, session: URLSession = .shared) {
        self.init(apiKey: apiKey, baseURL: baseURL, transport: AIGifMaker.urlSessionTransport(session))
    }

    public init(apiKey: String? = nil, baseURL: URL = AIGifMaker.baseURL, transport: @escaping Transport) {
        self.apiKey = (apiKey ?? ProcessInfo.processInfo.environment["AIGIFMAKER_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.base = baseURL
        self.transport = transport
    }

    /// Generate one animated GIF and return its URL: submits, waits, and returns when the GIF is ready.
    public func generate(_ prompt: String) async throws -> URL {
        try await wait(try await submit(prompt))
    }

    /// Start one GIF and return its task id without waiting.
    public func submit(_ prompt: String) async throws -> String {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIGifMakerError.api("prompt is required")
        }
        let data = try await call("api/ai/generate", [
            "provider": "openlux",
            "mediaType": "image",
            "model": "gif-maker-v1",
            "scene": "text-to-image",
            "prompt": prompt,
            "options": ["output_format": "gif"],
        ])
        guard let id = AIGifMaker.string(data["id"]), !id.isEmpty else {
            throw AIGifMakerError.api("the service returned no task id")
        }
        return id
    }

    /// Look up a task.
    public func status(_ id: String) async throws -> Status {
        AIGifMaker.parseStatus(try await call("api/ai/query", ["taskId": id]))
    }

    /// Credits left on the account. Free to call.
    public func credits() async throws -> Int {
        let data = try await call("api/user/get-user-credits", [:])
        return (data["remainingCredits"] as? NSNumber)?.intValue ?? 0
    }

    /// Poll a task every `pollInterval` seconds until it finishes and return the GIF URL.
    public func wait(_ id: String) async throws -> URL {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            var polled: Status?
            do { polled = try await status(id) }
            catch let e as AIGifMakerError { if case .api = e {} else { throw e } } // a refusal is final
            catch {} // a dropped poll is not a failed GIF
            if let st = polled {
                if st.status == "success", let url = st.url { return url }
                if st.status == "failed" || st.status == "canceled" {
                    let msg = st.errorMessage ?? "the GIF \(st.status)"
                    throw st.failureKind == "moderation" ? AIGifMakerError.rejected(msg) : AIGifMakerError.failed(msg)
                }
            }
            if Date().addingTimeInterval(pollInterval) >= deadline { throw AIGifMakerError.timeout(id) }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    private func call(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        try AIGifMaker.unwrap(try await transport(base.appendingPathComponent(path), body, apiKey))
    }

    // MARK: - Response handling (public so it can be tested without the network)

    /// Every answer is HTTP 200; the JSON `code` tells success from refusal.
    public static func unwrap(_ env: [String: Any]) throws -> [String: Any] {
        let code = (env["code"] as? NSNumber)?.intValue
        let data = env["data"] as? [String: Any] ?? [:]
        if code == 0 {
            if (data["wall"] as? Bool) == true {
                throw AIGifMakerError.auth("an API key is required; create one at \(keysURL) and set AIGIFMAKER_API_KEY")
            }
            return data
        }
        throw classify(code, string(env["message"]) ?? "unexpected answer")
    }

    public static func classify(_ code: Int?, _ message: String) -> AIGifMakerError {
        let low = message.lowercased()
        if low.contains("invalid api key") || low.contains("no auth") { return .auth(message) }
        if low.contains("insufficient credits") { return .quota(message) }
        if let c = code, c != 0, c != -1 { return .rejected(message) }
        return .api(message)
    }

    public static func parseStatus(_ d: [String: Any]) -> Status {
        let images = d["images"] as? [Any] ?? []
        return Status(id: string(d["id"]) ?? "", status: string(d["status"]) ?? "",
                      url: images.first.flatMap { string($0) }.flatMap(URL.init(string:)),
                      queued: (d["queued"] as? Bool) ?? false,
                      errorMessage: string(d["errorMessage"]), failureKind: string(d["failureKind"]))
    }

    static func string(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func urlSessionTransport(_ session: URLSession) -> Transport {
        return { url, body, key in
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.setValue("aigifmaker-swift/\(AIGifMaker.version)", forHTTPHeaderField: "user-agent")
            // Without a key the request still goes out: the service answers with a wall, which becomes .auth.
            if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "authorization") }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let data: Data = try await withCheckedThrowingContinuation { cont in
                session.dataTask(with: req) { d, _, err in
                    if let err = err { cont.resume(throwing: err) } else { cont.resume(returning: d ?? Data()) }
                }.resume()
            }
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
    }
}
