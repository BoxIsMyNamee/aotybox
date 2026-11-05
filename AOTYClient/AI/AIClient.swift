import Foundation
import Security

// MARK: - Keychain (API keys never go in UserDefaults)

enum Keychain {
    private static let service = "com.harper.aotyclient.ai"

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Providers

enum AIProvider: String, CaseIterable, Identifiable {
    case gemini, anthropic, openai
    var id: String { rawValue }
    var name: String {
        switch self {
        case .gemini: "Google Gemini"
        case .anthropic: "Anthropic Claude"
        case .openai: "OpenAI-compatible"
        }
    }
    var defaultModel: String {
        switch self {
        case .gemini: "gemini-flash-latest"
        case .anthropic: "claude-haiku-5-5"
        case .openai: ""
        }
    }
    var keyHelp: String {
        switch self {
        case .gemini: "Free key at aistudio.google.com → Get API key. Answers can use Google Search."
        case .anthropic: "Key from console.anthropic.com. Answers can use web search."
        case .openai: "Works with OpenAI, OpenRouter, Groq, or a local server. Set the base URL and model."
        }
    }
    var searchesWeb: Bool { self != .openai }
}

enum AISettings {
    static let providerKey = "aiProvider"
    static let modelKey = "aiModel"
    static let baseURLKey = "aiBaseURL"

    static var provider: AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .gemini
    }
    static var model: String {
        let m = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return m.isEmpty ? provider.defaultModel : m
    }
    static var baseURL: String {
        let b = UserDefaults.standard.string(forKey: baseURLKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return b.isEmpty ? "https://api.openai.com/v1" : b
    }
    static func apiKey(_ p: AIProvider = provider) -> String? { Keychain.get("key." + p.rawValue) }
    static func setAPIKey(_ k: String?, _ p: AIProvider) { Keychain.set(k, for: "key." + p.rawValue) }
    static var isConfigured: Bool {
        guard let k = apiKey(), !k.isEmpty else { return false }
        return provider != .openai || !model.isEmpty
    }
}

struct ChatMessage: Identifiable, Hashable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var sources: [Source] = []
    var model: String? = nil

    struct Source: Hashable { let title: String; let url: URL }
}

enum AIError: LocalizedError {
    case notConfigured, http(Int, String), empty
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Add an AI provider and API key in Settings → AI Assistant."
        case let .http(code, msg): "The AI service returned \(code). \(msg)"
        case .empty: "The AI didn't return an answer."
        }
    }
}

// MARK: - Client

enum AIClient {
    static func reply(system: String, history: [ChatMessage]) async throws -> ChatMessage {
        guard let key = AISettings.apiKey(), !key.isEmpty else { throw AIError.notConfigured }
        switch AISettings.provider {
        case .gemini: return try await gemini(key: key, system: system, history: history)
        case .anthropic: return try await anthropic(key: key, system: system, history: history)
        case .openai: return try await openai(key: key, system: system, history: history)
        }
    }

    private static func post(_ url: URL, headers: [String: String], body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: url, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(code) else {
            let msg = ((obj["error"] as? [String: Any])?["message"] as? String) ?? String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw AIError.http(code, msg)
        }
        return obj
    }

    /// Free-tier-friendly fallbacks, tried when the chosen model returns 429 (no free quota).
    private static let geminiFallbacks = ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite"]
    private static let resolvedModelKey = "aiGeminiResolvedModel"
    private static let searchOffKey = "aiGeminiSearchOff"

    private static func gemini(key: String, system: String, history: [ChatMessage]) async throws -> ChatMessage {
        let chosen = AISettings.model
        let userPicked = !(UserDefaults.standard.string(forKey: AISettings.modelKey) ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        var models = [chosen]
        if !userPicked {
            if let r = UserDefaults.standard.string(forKey: resolvedModelKey), r != chosen { models.insert(r, at: 0) }
            models += geminiFallbacks.filter { !models.contains($0) }
        }
        var lastError: Error = AIError.empty
        for model in models {
            // With Google Search first (better answers), then without (search has its own quota).
            let searchOrder = UserDefaults.standard.bool(forKey: searchOffKey) ? [false] : [true, false]
            for search in searchOrder {
                do {
                    let reply = try await geminiOnce(key: key, model: model, search: search, system: system, history: history)
                    if !userPicked { UserDefaults.standard.set(model, forKey: resolvedModelKey) }
                    UserDefaults.standard.set(!search, forKey: searchOffKey)
                    return reply
                } catch let AIError.http(code, msg) where code == 429 || (code == 404 && !userPicked) || (code == 400 && msg.lowercased().contains("search")) {
                    lastError = AIError.http(code, msg)
                    continue
                }
            }
        }
        if case let AIError.http(429, _) = lastError {
            throw AIError.http(429, "No free quota on any Gemini model for this key yet. Check limits at ai.dev/rate-limit, or try again later.")
        }
        throw lastError
    }

    private static func geminiOnce(key: String, model: String, search: Bool, system: String, history: [ChatMessage]) async throws -> ChatMessage {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { throw AIError.empty }
        let contents = history.map { ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.text]]] }
        var body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": contents,
        ]
        if search { body["tools"] = [["google_search": [String: Any]()]] }
        let obj = try await post(url, headers: ["x-goog-api-key": key], body: body)
        let cand = (obj["candidates"] as? [[String: Any]])?.first
        let parts = ((cand?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIError.empty }
        let chunks = ((cand?["groundingMetadata"] as? [String: Any])?["groundingChunks"] as? [[String: Any]]) ?? []
        var seen = Set<URL>()
        let sources: [ChatMessage.Source] = chunks.compactMap { c in
            guard let web = c["web"] as? [String: Any], let u = (web["uri"] as? String).flatMap(URL.init(string:)), seen.insert(u).inserted else { return nil }
            return .init(title: (web["title"] as? String) ?? u.host ?? "Source", url: u)
        }
        var msg = ChatMessage(role: .assistant, text: text, sources: sources)
        msg.model = model + (search ? " + Google Search" : "")
        return msg
    }

    private static func anthropic(key: String, system: String, history: [ChatMessage]) async throws -> ChatMessage {
        let messages = history.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.text] }
        let body: [String: Any] = [
            "model": AISettings.model,
            "max_tokens": 1500,
            "system": system,
            "messages": messages,
            "tools": [["type": "web_search_20250305", "name": "web_search", "max_uses": 3]],
        ]
        let obj = try await post(URL(string: "https://api.anthropic.com/v1/messages")!,
                                 headers: ["x-api-key": key, "anthropic-version": "2023-06-01"], body: body)
        let blocks = (obj["content"] as? [[String: Any]]) ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIError.empty }
        var seen = Set<URL>()
        var sources: [ChatMessage.Source] = []
        for b in blocks where b["type"] as? String == "text" {
            for c in (b["citations"] as? [[String: Any]]) ?? [] {
                if let u = (c["url"] as? String).flatMap(URL.init(string:)), seen.insert(u).inserted {
                    sources.append(.init(title: (c["title"] as? String) ?? u.host ?? "Source", url: u))
                }
            }
        }
        return ChatMessage(role: .assistant, text: text, sources: sources)
    }

    private static func openai(key: String, system: String, history: [ChatMessage]) async throws -> ChatMessage {
        guard !AISettings.model.isEmpty else { throw AIError.notConfigured }
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        messages += history.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.text] }
        let base = AISettings.baseURL.hasSuffix("/") ? String(AISettings.baseURL.dropLast()) : AISettings.baseURL
        guard let url = URL(string: base + "/chat/completions") else { throw AIError.notConfigured }
        let obj = try await post(url, headers: ["Authorization": "Bearer \(key)"],
                                 body: ["model": AISettings.model, "messages": messages])
        let text = (((obj["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
        guard !text.isEmpty else { throw AIError.empty }
        return ChatMessage(role: .assistant, text: text)
    }
}
