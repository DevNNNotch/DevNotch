import AppKit
import Defaults
import SwiftUI

struct DeveloperSettingsView: View {
    @ObservedObject private var workspace = DeveloperWorkspaceModel.shared
    @Default(.developerWorkspaceEnabled) private var workspaceEnabled
    @Default(.developerSystemMonitoringEnabled) private var systemMonitoringEnabled
    @Default(.developerClipboardMonitoringEnabled) private var clipboardMonitoringEnabled
    @Default(.developerLocalAPIEnabled) private var localAPIEnabled
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

            Section("Local event API") {
                Defaults.Toggle(key: .developerLocalAPIEnabled) { Text("Listen on 127.0.0.1:54731") }
                HStack {
                    providerIndicator(workspace.localAPIStatus)
                    Spacer()
                    Button("Copy access token") { copyLocalAPIToken() }
                }
                Text("Bearer authentication, a 1 MiB body limit, strict JSON fields, and rate limiting are enforced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Client support") {
                providerRow("Codex", workspace.codexStatus)
                providerRow("Claude Code", workspace.claudeCodeStatus)
                providerRow("Trae", workspace.traeStatus)
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

    private func providerRow(_ name: String, _ status: ProviderStatus) -> some View {
        LabeledContent(name) { providerIndicator(status) }
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
}
