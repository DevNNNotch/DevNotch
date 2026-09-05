import AppKit
import Defaults
import SwiftUI

struct DeveloperSettingsView: View {
    @ObservedObject private var workspace = DeveloperWorkspaceModel.shared
    @Default(.developerWorkspaceEnabled) private var workspaceEnabled
    @Default(.developerSystemMonitoringEnabled) private var systemMonitoringEnabled
    @Default(.developerClipboardMonitoringEnabled) private var clipboardMonitoringEnabled
    @Default(.developerLocalAPIEnabled) private var localAPIEnabled
    @Default(.developerCodexUsageEnabled) private var codexUsageEnabled
    @Default(.developerOllamaEnabled) private var ollamaEnabled
    @Default(.developerOllamaEndpoint) private var ollamaEndpoint
    @Default(.developerOllamaModel) private var ollamaModel
    @Default(.developerVLLMEnabled) private var vllmEnabled
    @Default(.developerVLLMEndpoint) private var vllmEndpoint
    @Default(.developerRefreshInterval) private var refreshInterval
    @Default(.developerAnimationSpeed) private var animationSpeed

    @State private var openAIAdminKey = ""
    @State private var credentialMessage: String?

    var body: some View {
        Form {
            Section("Developer workspace") {
                Defaults.Toggle(key: .developerWorkspaceEnabled) { Text("Enable developer workspace") }
                Defaults.Toggle(key: .developerSystemMonitoringEnabled) { Text("System monitoring") }
                Defaults.Toggle(key: .developerClipboardMonitoringEnabled) { Text("Clipboard context detection") }
                LabeledContent("Refresh interval") {
                    Slider(value: $refreshInterval, in: 1...10, step: 0.5)
                        .frame(width: 220)
                    Text("\(refreshInterval, specifier: "%.1f")s").monospacedDigit().frame(width: 38)
                }
                LabeledContent("Animation speed") {
                    Slider(value: $animationSpeed, in: 0.5...2, step: 0.1)
                        .frame(width: 220)
                    Text("\(animationSpeed, specifier: "%.1f")x").monospacedDigit().frame(width: 38)
                }
                Button("Apply monitoring settings") { workspace.applyConfiguration() }
            }

            Section("Token client connections") {
                connectionRow(
                    "Codex",
                    icon: "chevron.left.forwardslash.chevron.right",
                    source: "Local token_count metadata from a user-selected sessions folder",
                    status: workspace.codexStatus
                ) {
                    Button(codexUsageEnabled ? "Change folder" : "Choose folder") {
                        chooseCodexSessionsFolder()
                    }
                    Button { Task { await workspace.refreshCodexUsage() } } label: {
                        if workspace.isRefreshingCodexUsage {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Scanning Codex sessions")
                        } else {
                            Text("Scan now")
                        }
                    }
                    .disabled(!codexUsageEnabled || workspace.isRefreshingCodexUsage)
                    if codexUsageEnabled {
                        Button("Disconnect", role: .destructive) { workspace.disconnectCodexUsage() }
                    }
                }

                connectionRow(
                    "OpenAI API",
                    icon: "circle.hexagongrid.fill",
                    source: "Official organization Usage API",
                    status: workspace.openAIStatus
                ) {
                    Button("Refresh") { Task { await workspace.refreshOpenAIUsage() } }
                }

                connectionRow(
                    "Claude Code",
                    icon: "sun.max.fill",
                    source: "Official status-line adapter",
                    status: workspace.claudeCodeStatus
                ) {
                    Button("Setup guide") { openIntegrationGuide() }
                }

                connectionRow(
                    "Trae",
                    icon: "sparkles",
                    source: "Client-reported usage through the local API",
                    status: workspace.traeStatus
                ) {
                    Button("Setup guide") { openIntegrationGuide() }
                }

                connectionRow(
                    "Other clients",
                    icon: "network",
                    source: "Authenticated endpoint at 127.0.0.1:54731",
                    status: workspace.localAPIStatus
                ) {
                    Toggle("Connect", isOn: $localAPIEnabled)
                        .toggleStyle(.switch)
                    Button("Copy token") { copyLocalAPIToken() }
                        .disabled(!localAPIEnabled)
                }

                Text("DevNotch only reports usage from verified local metadata, official APIs, or authenticated client events. Unsupported account quotas remain unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local AI") {
                Defaults.Toggle(key: .developerOllamaEnabled) { Text("Enable Ollama") }
                TextField("Endpoint", text: $ollamaEndpoint)
                TextField("Model", text: $ollamaModel)
                HStack {
                    providerIndicator(workspace.ollamaStatus)
                    Spacer()
                    Button("Check connection") { Task { await workspace.refreshOllamaStatus() } }
                }
            }

            Section("OpenAI API organization usage") {
                SecureField("Organization Admin Key", text: $openAIAdminKey)
                HStack {
                    Button("Save to Keychain") { saveOpenAIKey() }
                    Button("Remove", role: .destructive) { removeOpenAIKey() }
                    Spacer()
                    Button("Refresh usage") { Task { await workspace.refreshOpenAIUsage() } }
                }
                providerIndicator(workspace.openAIStatus)
                Text("This reports OpenAI API organization usage. It is not Codex subscription quota.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("vLLM") {
                Defaults.Toggle(key: .developerVLLMEnabled) { Text("Monitor vLLM") }
                TextField("OpenAI-compatible endpoint", text: $vllmEndpoint)
                HStack {
                    providerIndicator(workspace.vllmStatus)
                    Spacer()
                    Button("Check connection") { Task { await workspace.refreshVLLMStatus() } }
                }
            }

            Section("Local event API security") {
                Text("Bearer authentication, a 1 MiB body limit, strict JSON fields, and rate limiting are enforced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let credentialMessage {
                Section("Credential status") {
                    Text(credentialMessage)
                        .foregroundStyle(credentialMessage.hasPrefix("Error") ? .red : .secondary)
                }
            }
        }
        .navigationTitle("Developer")
        .onChange(of: workspaceEnabled) { workspace.applyConfiguration() }
        .onChange(of: systemMonitoringEnabled) { workspace.applyConfiguration() }
        .onChange(of: clipboardMonitoringEnabled) { workspace.applyConfiguration() }
        .onChange(of: localAPIEnabled) { workspace.applyConfiguration() }
        .onChange(of: vllmEnabled) { Task { await workspace.refreshVLLMStatus() } }
    }

    private func providerIndicator(_ status: ProviderStatus) -> some View {
        Label(status.reason, systemImage: statusIcon(status.state))
            .font(.caption)
            .foregroundStyle(status.state == .failed ? .red : .secondary)
    }

    private func connectionRow<Actions: View>(
        _ name: String,
        icon: String,
        source: String,
        status: ProviderStatus,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(name, systemImage: icon)
                    .fontWeight(.semibold)
                Spacer()
                actions()
            }
            Text(source)
                .font(.caption)
                .foregroundStyle(.secondary)
            providerIndicator(status)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    private func statusIcon(_ state: ProviderStatus.State) -> String {
        switch state {
        case .ready: "checkmark.circle.fill"
        case .needsConfiguration: "gearshape.circle"
        case .unavailable: "minus.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func saveOpenAIKey() {
        do {
            try workspace.storeOpenAIAdminKey(openAIAdminKey)
            openAIAdminKey = ""
            credentialMessage = "OpenAI Admin Key saved to Keychain."
            Task { await workspace.refreshOpenAIUsage() }
        } catch {
            credentialMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func removeOpenAIKey() {
        do {
            try workspace.storeOpenAIAdminKey("")
            openAIAdminKey = ""
            credentialMessage = "OpenAI Admin Key removed from Keychain."
            Task { await workspace.refreshOpenAIUsage() }
        } catch {
            credentialMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func copyLocalAPIToken() {
        do {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(try workspace.localAPIToken(), forType: .string)
            credentialMessage = "Local API token copied to the clipboard."
        } catch {
            credentialMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func chooseCodexSessionsFolder() {
        let panel = NSOpenPanel()
        panel.title = "Connect Codex token usage"
        panel.message = "Choose .codex or its sessions folder. DevNotch reads token metadata only."
        panel.prompt = "Connect"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(
            fileURLWithPath: "/Users/\(NSUserName())/.codex",
            isDirectory: true
        )

        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            try workspace.bindCodexSessionsDirectory(directory)
            credentialMessage = "Codex sessions folder connected."
            Task { await workspace.refreshCodexUsage() }
        } catch {
            credentialMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func openIntegrationGuide() {
        guard let url = URL(string: "https://github.com/DevNNNotch/DevNotch#ai-usage-providers") else {
            credentialMessage = "Error: The integration guide URL is invalid."
            return
        }
        NSWorkspace.shared.open(url)
    }
}
