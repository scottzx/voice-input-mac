import Foundation

/// Configuration for the LLM-backed text polisher. Persisted via `UserDefaults` from `AppState`.
public struct PolisherConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var systemPrompt: String

    public init(
        enabled: Bool = false,
        baseURL: String = "https://api.openai.com/v1",
        apiKey: String = "",
        model: String = "gpt-4o-mini",
        systemPrompt: String = TextPolisher.defaultSystemPrompt
    ) {
        self.enabled = enabled
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
    }

    public var isConfigured: Bool {
        enabled && !apiKey.isEmpty && !model.isEmpty && !baseURL.isEmpty
    }
}

public enum PolisherError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case httpStatus(Int)
    case badResponse
    case empty

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "整理功能未启用，请在设置里填入 API key。"
        case .invalidURL: return "整理请求的地址无效"
        case .httpStatus(let code): return "整理请求失败（HTTP \(code)）"
        case .badResponse: return "整理响应格式异常"
        case .empty: return "整理结果为空"
        }
    }
}

/// OpenAI-compatible `/chat/completions` client used by the polish hotkey.
public final class TextPolisher: @unchecked Sendable {
    public static let defaultSystemPrompt = """
    你是中文文本整理助手。把下面的中文（或中英混排）口语文本整理成通顺、书面、简洁的表达。\
    保留原意，去掉口水词、明显重复和口误；只调整措辞、标点、断句和分段。\
    不要添加任何新内容，不要给出解释、列表或前后缀，只输出整理后的最终文本。
    """

    public var config: PolisherConfig

    public init(config: PolisherConfig = PolisherConfig()) {
        self.config = config
    }

    public func polish(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard config.isConfigured else { throw PolisherError.notConfigured }
        guard let url = completionsURL() else { throw PolisherError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": config.systemPrompt],
                ["role": "user", "content": trimmed],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PolisherError.httpStatus(http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PolisherError.badResponse
        }
        let stripped = TextPolisher.stripReasoningBlocks(in: content)
        let result = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw PolisherError.empty }
        return result
    }

    /// Reasoning models (DeepSeek-R1, Qwen3-Reasoning, etc.) prepend a
    /// `<think>...</think>` block to the assistant `content`. Strip those
    /// (and any sibling variants) so we only paste the final answer.
    private static let reasoningTagNames = [
        "think", "thinking", "reason", "reasoning", "reflection", "analysis",
    ]
    private static let reasoningRegex: NSRegularExpression? = {
        let tags = reasoningTagNames.joined(separator: "|")
        let pattern = "<(?:\(tags))\\b[^>]*>(?:[\\s\\S]*?</(?:\(tags))>|[\\s\\S]*$)"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    static func stripReasoningBlocks(in text: String) -> String {
        guard let regex = reasoningRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private func completionsURL() -> URL? {
        guard let base = baseURL() else { return nil }
        return base.appendingPathComponent("chat/completions")
    }

    private func modelsURL() -> URL? {
        guard let base = baseURL() else { return nil }
        return base.appendingPathComponent("models")
    }

    private func baseURL() -> URL? {
        let trimmed = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return URL(string: normalized)
    }

    /// Hit OpenAI-compatible `GET /models` and return the `id` of each entry.
    /// Many local gateways (Ollama, vLLM, lm-studio) also expose this.
    public func listModels() async throws -> [String] {
        guard config.isConfigured else { throw PolisherError.notConfigured }
        guard let url = modelsURL() else { throw PolisherError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PolisherError.httpStatus(http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            throw PolisherError.badResponse
        }
        return list.compactMap { $0["id"] as? String }.sorted()
    }
}