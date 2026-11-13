import SwiftUI

struct AISettingsView: View {
    @AppStorage(AISettings.providerKey) private var providerRaw = AIProvider.gemini.rawValue
    @AppStorage(AISettings.modelKey) private var model = ""
    @AppStorage(AISettings.baseURLKey) private var baseURL = ""
    @AppStorage(AISettings.autoAskKey) private var autoAsk = false
    @State private var key = ""
    @State private var testResult: String?
    @State private var testing = false

    private var provider: AIProvider { AIProvider(rawValue: providerRaw) ?? .gemini }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(AIProvider.allCases) { Text($0.name).tag($0.rawValue) }
                }
                SecureField("API key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { AISettings.setAPIKey(key, provider) }
                TextField(provider == .gemini ? "Model (leave empty = automatic)" : (provider.defaultModel.isEmpty ? "Model (required)" : "Model (default \(provider.defaultModel))"), text: $model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if provider == .openai {
                    TextField("Base URL (default https://api.openai.com/v1)", text: $baseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
            } footer: {
                Text(provider.keyHelp + " Your key is stored in the iPhone Keychain and only sent to the provider you choose.")
            }

            Section {
                Button("Save") { AISettings.setAPIKey(key, provider) }
                Button(testing ? "Testing…" : "Test connection") { Task { await test() } }
                    .disabled(testing || key.isEmpty)
                if let testResult { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
                if AISettings.apiKey(provider) != nil {
                    Button("Remove key", role: .destructive) { AISettings.setAPIKey(nil, provider); key = "" }
                }
            }

            Section {
                Toggle("Ask right away on Learn", isOn: $autoAsk)
            } footer: {
                Text("When you open Learn for a song or album, Ask AI starts on \"What is this about?\" in the background, so the answer is ready when you switch to it.")
            }
        }
        .navigationTitle("AI Assistant")
        .onAppear { key = AISettings.apiKey(provider) ?? "" }
        .onChange(of: providerRaw) { key = AISettings.apiKey(provider) ?? ""; model = ""; testResult = nil }
        .onChange(of: model) {
            UserDefaults.standard.removeObject(forKey: "aiGeminiResolvedModel")
            UserDefaults.standard.removeObject(forKey: "aiGeminiSearchOff")
            UserDefaults.standard.removeObject(forKey: "aiGeminiModelListDate")
        }
        .onDisappear { AISettings.setAPIKey(key, provider) }
    }

    private func test() async {
        AISettings.setAPIKey(key, provider)
        testing = true; defer { testing = false }
        do {
            let r = try await AIClient.reply(system: "Reply with one short sentence.",
                                             history: [ChatMessage(role: .user, text: "Say hi and name the model you are.")])
            testResult = "Connected" + (r.model.map { " using \($0)" } ?? "") + ": " + r.text.prefix(120)
        } catch {
            testResult = error.localizedDescription
        }
    }
}
