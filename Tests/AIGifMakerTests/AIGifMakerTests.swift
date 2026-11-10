import XCTest
@testable import AIGifMaker

/// Replays the service's real response shapes in order and records the requests.
final class Script: @unchecked Sendable {
    var answers: [[String: Any]]
    var requests: [(URL, [String: Any], String)] = []
    init(_ a: [[String: Any]]) { answers = a }
    func transport() -> AIGifMaker.Transport {
        return { url, body, key in
            self.requests.append((url, body, key))
            return self.answers.removeFirst()
        }
    }
}

let submitted: [String: Any] = ["code": 0, "message": "ok", "data": ["id": "task_1", "status": "pending", "taskId": "up_9", "provider": "openlux"]]

final class AIGifMakerTests: XCTestCase {
    func client(_ s: Script) -> AIGifMaker {
        var g = AIGifMaker(apiKey: "sk-test", transport: s.transport())
        g.pollInterval = 0.001
        return g
    }

    func testGenerateWaitsThroughQueue() async throws {
        let s = Script([
            submitted,
            ["code": 0, "message": "ok", "data": ["id": "task_1", "status": "processing", "images": [], "queued": true, "queueEta": 40]],
            ["code": 0, "message": "ok", "data": ["id": "task_1", "status": "success", "images": ["https://cdn.aigifmaker.ai/g/task_1.gif"], "watermarked": [true]]],
        ])
        let url = try await client(s).generate("a corgi dancing")
        XCTAssertEqual(url.absoluteString, "https://cdn.aigifmaker.ai/g/task_1.gif")
        let (u0, b0, k0) = s.requests[0]
        XCTAssertEqual(u0.path, "/api/ai/generate")
        XCTAssertEqual(k0, "sk-test")
        XCTAssertEqual(b0["provider"] as? String, "openlux")
        XCTAssertEqual(b0["mediaType"] as? String, "image")
        XCTAssertEqual(b0["model"] as? String, "gif-maker-v1")
        XCTAssertEqual(b0["scene"] as? String, "text-to-image")
        XCTAssertEqual(b0["prompt"] as? String, "a corgi dancing")
        XCTAssertEqual((b0["options"] as? [String: Any])?["output_format"] as? String, "gif")
        XCTAssertEqual(s.requests[1].0.path, "/api/ai/query")
        XCTAssertEqual(s.requests[1].1["taskId"] as? String, "task_1")
    }

    func testCredits() async throws {
        let s = Script([["code": 0, "message": "ok", "data": ["remainingCredits": 42, "made": 3]]])
        let n = try await client(s).credits()
        XCTAssertEqual(n, 42)
    }

    func testFailedAndModeration() async {
        for (data, want) in [
            (["id": "t", "status": "failed", "errorMessage": "upstream error", "refundNote": "credit returned"], AIGifMaker.AIGifMakerError.failed("upstream error")),
            (["id": "t", "status": "failed", "errorMessage": "blocked", "failureKind": "moderation"], .rejected("blocked")),
        ] as [([String: Any], AIGifMaker.AIGifMakerError)] {
            let s = Script([submitted, ["code": 0, "message": "ok", "data": data]])
            do { _ = try await client(s).generate("x"); XCTFail("expected \(want)") }
            catch let e as AIGifMaker.AIGifMakerError { XCTAssertEqual(e, want) }
            catch { XCTFail("\(error)") }
        }
    }

    func testErrorMapping() {
        func map(_ env: [String: Any]) -> AIGifMaker.AIGifMakerError? {
            do { _ = try AIGifMaker.unwrap(env); return nil } catch { return error as? AIGifMaker.AIGifMakerError }
        }
        let invalid = "invalid API key — create one at https://aigifmaker.ai/settings/apikeys"
        XCTAssertEqual(map(["code": -1, "message": invalid]), .auth(invalid))
        XCTAssertEqual(map(["code": -1, "message": "no auth, please sign in"]), .auth("no auth, please sign in"))
        if case .auth = map(["code": 0, "message": "ok", "data": ["wall": true, "reason": "anon_credits"]]) {} else { XCTFail("wall") }
        XCTAssertEqual(map(["code": -1, "message": "insufficient credits"]), .quota("insufficient credits"))
        XCTAssertEqual(map(["code": -2, "message": "content cooldown"]), .rejected("content cooldown"))
        XCTAssertEqual(map(["code": -1, "message": "upstream busy"]), .api("upstream busy"))
    }

    /// Two free live checks (no generation); run with AIGIFMAKER_SMOKE=1.
    func testLiveSmoke() async throws {
        guard ProcessInfo.processInfo.environment["AIGIFMAKER_SMOKE"] != nil else { throw XCTSkip("set AIGIFMAKER_SMOKE=1") }
        do { _ = try await AIGifMaker(apiKey: "sk-invalidtest000").credits(); XCTFail("expected auth") }
        catch let e as AIGifMaker.AIGifMakerError { if case .auth = e {} else { XCTFail("\(e)") } }
        do { _ = try await AIGifMaker(apiKey: " ").submit("a cat waving"); XCTFail("expected wall") }
        catch let e as AIGifMaker.AIGifMakerError { if case .auth = e {} else { XCTFail("\(e)") } }
    }
}
