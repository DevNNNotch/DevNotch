import Combine
import Defaults
import Foundation
import Security

@MainActor
final class DeveloperWorkspaceModel: ObservableObject {
    static let shared = DeveloperWorkspaceModel()

    @Published private(set) var snapshot = SystemSnapshot.empty
    @Published private(set) var clipboardContext: ClipboardContext?
    @Published private(set) var usageSamples: [UsageSample] = []
    @Published private(set) var events: [DeveloperEvent] = []
    @Published private(set) var aiOutput = ""
    @Published private(set) var aiError: String?
    @Published private(set) var isGenerating = false
    @Published private(set) var openAIStatus = ProviderStatus(
        state: .needsConfiguration,
        reason: "An OpenAI organization Admin Key is required."
    )
    @Published private(set) var ollamaStatus = ProviderStatus(state: .needsConfiguration, reason: "Not checked")
    @Published private(set) var vllmStatus = ProviderStatus(state: .unavailable, reason: "vLLM is disabled")
    @Published private(set) var localAPIStatus = ProviderStatus(state: .unavailable, reason: "Local API is disabled")

    var codexStatus: ProviderStatus {
        usageSamples.contains { $0.provider == .codex }
            ? ProviderStatus(state: .ready, reason: "Receiving local Codex session totals. This is not subscription quota.")
            : ProviderStatus(state: .needsConfiguration, reason: "Run Examples/codex_usage_sync.py for local session totals.")
    }

    var claudeCodeStatus: ProviderStatus {
        usageSamples.contains { $0.provider == .claudeCode }
            ? ProviderStatus(state: .ready, reason: "Receiving Claude Code status-line snapshots.")
            : ProviderStatus(state: .needsConfiguration, reason: "Configure Examples/claude_statusline.py as the Claude Code status line.")
    }

    var traeStatus: ProviderStatus {
        usageSamples.contains { $0.provider == .trae }
            ? ProviderStatus(state: .ready, reason: "Receiving client-reported Trae usage events.")
            : ProviderStatus(state: .unavailable, reason: "No verified Trae usage interface is configured. Use the local usage event endpoint.")
    }

    private let monitor = SystemMonitor()
    private let clipboard = ClipboardService()
    private let usageStore = UsageStore()
    private let eventStore = EventStore()
    private let keychain = KeychainStore()
    private var server: LocalAPIServer?
    private var cancellables: Set<AnyCancellable> = []
    private var aiTask: Task<Void, Never>?
    private var observationTasks: [Task<Void, Never>] = []
    private var hasStarted = false

    private init() {
        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.snapshot = value }
            .store(in: &cancellables)

        clipboard.$context
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.clipboardContext = value }
            .store(in: &cancellables)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observationTasks = [
            Task { [weak self] in await self?.observeUsage() },
            Task { [weak self] in await self?.observeEvents() }
        ]
        applyConfiguration()
        Task { [weak self] in
            await self?.refreshOllamaStatus()
            await self?.refreshVLLMStatus()
            await self?.refreshOpenAIUsage()
        }
    }

    func stop() {
        monitor.stop()
        clipboard.stop()
        server?.stop()
        server = nil
        aiTask?.cancel()
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
        hasStarted = false
    }

    func applyConfiguration() {
        if Defaults[.developerWorkspaceEnabled] && Defaults[.developerSystemMonitoringEnabled] {
            monitor.start(interval: Defaults[.developerRefreshInterval])
        } else {
            monitor.stop()
        }

        if Defaults[.developerWorkspaceEnabled] && Defaults[.developerClipboardMonitoringEnabled] {
            clipboard.start()
        } else {
            clipboard.stop()
            clipboardContext = nil
        }
        configureLocalAPI()
    }

    func storeOpenAIAdminKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.remove("openai-admin-key")
        } else {
            try keychain.set(trimmed, for: "openai-admin-key")
        }
    }

    func localAPIToken() throws -> String {
        if let token = try keychain.string(for: "local-api-token"), !token.isEmpty {
            return token
        }
        let token = try Self.generateToken()
        try keychain.set(token, for: "local-api-token")
        return token
    }

    func refreshOpenAIUsage() async {
        let provider = OpenAIUsageProvider(keychain: keychain)
        openAIStatus = await provider.status()
        guard openAIStatus.state == .ready else { return }
        do {
            let samples = try await provider.fetchUsage(
                from: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date().addingTimeInterval(-604_800),
                to: Date()
            )
            await usageStore.replace(samples, for: .openAI)
            openAIStatus = ProviderStatus(state: .ready, reason: "Loaded \(samples.count) OpenAI API usage bucket(s).")
        } catch {
            openAIStatus = ProviderStatus(state: .failed, reason: error.localizedDescription)
        }
    }

    func refreshOllamaStatus() async {
        guard Defaults[.developerOllamaEnabled] else {
            ollamaStatus = ProviderStatus(state: .unavailable, reason: "Ollama is disabled")
            return
        }
        do {
            let service = try OllamaService(endpoint: Defaults[.developerOllamaEndpoint])
            let models = try await service.models()
            ollamaStatus = ProviderStatus(
                state: .ready,
                reason: models.isEmpty ? "Ollama is running with no installed models" : "Ollama is running with \(models.count) model(s)"
            )
        } catch {
            ollamaStatus = ProviderStatus(state: .failed, reason: error.localizedDescription)
        }
    }

    func refreshVLLMStatus() async {
        guard Defaults[.developerVLLMEnabled] else {
            vllmStatus = ProviderStatus(state: .unavailable, reason: "vLLM is disabled")
            return
        }
        do {
            let models = try await VLLMService(endpoint: Defaults[.developerVLLMEndpoint]).models()
            vllmStatus = ProviderStatus(
                state: .ready,
                reason: models.isEmpty ? "vLLM is running with no advertised models" : "vLLM is serving \(models.count) model(s)"
            )
        } catch {
            vllmStatus = ProviderStatus(state: .failed, reason: error.localizedDescription)
        }
    }

    func runAIAction(_ action: AIAction) {
        guard let context = clipboardContext else {
            aiError = "Copy code, an error log, a Git diff, or text first."
            return
        }
        guard context.kind != .sensitive else {
            aiError = "AI actions are blocked because the clipboard appears to contain a credential or private key."
            return
        }

        aiTask?.cancel()
        aiOutput = ""
        aiError = nil
        isGenerating = true
        let endpoint = Defaults[.developerOllamaEndpoint]
        let model = Defaults[.developerOllamaModel]
        let prompt = action.prompt(for: context.content)

        aiTask = Task { [weak self] in
            guard let self else { return }
            do {
                let service = try OllamaService(endpoint: endpoint)
                for try await chunk in service.streamChat(model: model, prompt: prompt) {
                    try Task.checkCancellation()
                    self.aiOutput += chunk
                }
                self.isGenerating = false
            } catch is CancellationError {
                self.isGenerating = false
            } catch {
                self.isGenerating = false
                self.aiError = error.localizedDescription
            }
        }
    }

    func cancelAIRequest() {
        aiTask?.cancel()
        aiTask = nil
        isGenerating = false
    }

    private func configureLocalAPI() {
        server?.stop()
        server = nil
        guard Defaults[.developerWorkspaceEnabled], Defaults[.developerLocalAPIEnabled] else {
            localAPIStatus = ProviderStatus(state: .unavailable, reason: "Local API is disabled")
            return
        }

        do {
            let router = LocalAPIRouter(
                accessToken: try localAPIToken(),
                usageStore: usageStore,
                eventStore: eventStore
            )
            let server = LocalAPIServer(router: router) { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .starting:
                        self.localAPIStatus = ProviderStatus(state: .needsConfiguration, reason: "Starting local API")
                    case .ready(let port):
                        self.localAPIStatus = ProviderStatus(state: .ready, reason: "Listening on 127.0.0.1:\(port)")
                    case .waiting(let reason):
                        self.localAPIStatus = ProviderStatus(state: .failed, reason: "Local API is waiting: \(reason)")
                    case .failed(let reason):
                        self.localAPIStatus = ProviderStatus(state: .failed, reason: "Local API failed: \(reason)")
                    case .stopped:
                        if Defaults[.developerLocalAPIEnabled] {
                            self.localAPIStatus = ProviderStatus(state: .failed, reason: "Local API stopped unexpectedly")
                        }
                    }
                }
            }
            try server.start()
            self.server = server
            localAPIStatus = ProviderStatus(state: .needsConfiguration, reason: "Starting local API")
        } catch {
            localAPIStatus = ProviderStatus(state: .failed, reason: error.localizedDescription)
        }
    }

    private func observeUsage() async {
        for await values in await usageStore.updates() {
            guard !Task.isCancelled else { return }
            usageSamples = values
        }
    }

    private func observeEvents() async {
        for await values in await eventStore.updates() {
            guard !Task.isCancelled else { return }
            events = values
        }
    }

    private static func generateToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainStore.KeychainError.unexpectedStatus(status)
        }
        return Data(bytes).base64EncodedString()
    }
}
