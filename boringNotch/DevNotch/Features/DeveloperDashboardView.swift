import SwiftUI

struct DeveloperDashboardView: View {
    @ObservedObject private var workspace = DeveloperWorkspaceModel.shared
    @State private var showingAIResult = false
    @State private var showingUsageDetails = false

    var body: some View {
        HStack(spacing: 10) {
            systemPanel
            usagePanel
            activityPanel
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .onChange(of: workspace.isGenerating) { _, isGenerating in
            if isGenerating { showingAIResult = true }
        }
    }

    private var systemPanel: some View {
        DeveloperPanel(title: "SYSTEM", icon: "gauge.with.dots.needle.67percent", status: systemStatusColor) {
            Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    developerMetric("CPU", percentage(workspace.snapshot.cpu), detail: workspace.snapshot.cpu.unavailableReason)
                    developerMetric("MEM", percentage(workspace.snapshot.memory), detail: workspace.snapshot.memory.unavailableReason)
                }
                GridRow {
                    developerMetric("DOWN", networkRate(\.downloadBytesPerSecond), detail: workspace.snapshot.network.unavailableReason)
                    developerMetric("UP", networkRate(\.uploadBytesPerSecond), detail: workspace.snapshot.network.unavailableReason)
                }
            }
            Spacer(minLength: 0)
            Text("GPU \(percentage(workspace.snapshot.gpu))  HP \(percentage(workspace.snapshot.headphoneBattery))  \(workspace.snapshot.batterySummary)")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(systemAvailabilityDetail)
        }
    }

    private var usagePanel: some View {
        let totals = UsageAggregator.totals(workspace.usageSamples)
        return DeveloperPanel(title: "AI USAGE", icon: "number.square", status: usageStatusColor) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(totals.total.formatted(.number.notation(.compactName)))
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                Text("TOKENS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                tokenMetric("IN", totals.input, color: .cyan)
                tokenMetric("CACHE", totals.cached, color: .green)
                tokenMetric("OUT", totals.output, color: .orange)
            }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Button {
                    showingUsageDetails = true
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
                .buttonStyle(.plain)
                .help("Show usage by client")
                .popover(isPresented: $showingUsageDetails, arrowEdge: .bottom) {
                    UsageDetailsPopover(samples: workspace.usageSamples)
                }

                Button {
                    Task { await workspace.refreshOpenAIUsage() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(workspace.openAIStatus.reason)
            }
        }
    }

    private var activityPanel: some View {
        DeveloperPanel(title: "CONTEXT", icon: "terminal", status: contextStatusColor) {
            if let context = workspace.clipboardContext {
                Text(context.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(context.suggestedAction)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 12) {
                    ForEach(AIAction.available(for: context.kind)) { action in
                        Button {
                            workspace.runAIAction(action)
                            showingAIResult = true
                        } label: {
                            Image(systemName: icon(for: action))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(workspace.isGenerating)
                        .help(action.rawValue)
                    }
                    if workspace.isGenerating {
                        Button {
                            workspace.cancelAIRequest()
                        } label: {
                            Image(systemName: "stop.fill")
                                .foregroundStyle(.red)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("Stop generation")
                    }
                }
                .popover(isPresented: $showingAIResult, arrowEdge: .bottom) {
                    AIResultPopover(workspace: workspace)
                }
            } else if let event = workspace.events.first {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(event.detail ?? event.state.rawValue.capitalized)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let progress = event.progress {
                    ProgressView(value: progress)
                        .tint(event.state == .failed ? .red : .green)
                }
            } else {
                Text("Copy developer context")
                    .font(.system(size: 12, weight: .semibold))
                Text("Code, error logs, Git diffs, or text")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(workspace.localAPIStatus.reason)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func developerMetric(_ label: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(detail ?? "\(label): \(value)")
    }

    private func tokenMetric(_ label: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).foregroundStyle(color)
            Text(value.formatted(.number.notation(.compactName)))
        }
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
    }

    private var systemStatusColor: Color {
        let cpu = workspace.snapshot.cpu.value
        let memory = workspace.snapshot.memory.value
        guard cpu != nil || memory != nil else { return .gray }
        if cpu ?? 0 >= 0.9 || memory ?? 0 >= 0.95 { return .red }
        if cpu ?? 0 >= 0.7 || memory ?? 0 >= 0.8 { return .yellow }
        return .green
    }

    private var systemAvailabilityDetail: String {
        [
            workspace.snapshot.gpu.unavailableReason,
            workspace.snapshot.headphoneBattery.unavailableReason,
            workspace.snapshot.battery.unavailableReason
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func percentage(_ metric: MetricAvailability<Double>) -> String {
        metric.value?.formatted(.percent.precision(.fractionLength(0))) ?? "N/A"
    }

    private func networkRate(_ keyPath: KeyPath<NetworkRates, UInt64>) -> String {
        guard let rates = workspace.snapshot.network.value else { return "N/A" }
        return rates[keyPath: keyPath].formatted(.byteCount(style: .memory)) + "/s"
    }

    private var contextStatusColor: Color {
        if workspace.clipboardContext?.kind == .sensitive { return .red }
        if workspace.clipboardContext != nil || workspace.events.first?.state == .running { return .orange }
        return statusColor(workspace.ollamaStatus.state)
    }

    private var usageStatusColor: Color {
        workspace.usageSamples.isEmpty ? statusColor(workspace.openAIStatus.state) : .green
    }

    private func statusColor(_ state: ProviderStatus.State) -> Color {
        switch state {
        case .ready: .green
        case .needsConfiguration: .yellow
        case .unavailable: .gray
        case .failed: .red
        }
    }

    private func icon(for action: AIAction) -> String {
        switch action {
        case .explainCode: "text.book.closed"
        case .diagnoseError: "stethoscope"
        case .suggestFix: "wrench.and.screwdriver"
        case .polish: "wand.and.stars"
        case .translate: "character.book.closed"
        case .generateCommitMessage: "arrow.triangle.branch"
        }
    }
}

private struct UsageDetailsPopover: View {
    let samples: [UsageSample]

    private var providers: [UsageSample.Provider] {
        UsageSample.Provider.allCases.filter { provider in
            samples.contains { $0.provider == provider }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Usage by client", systemImage: "chart.bar.xaxis")
                .font(.headline)
            Divider()
            if providers.isEmpty {
                ContentUnavailableView(
                    "No usage data",
                    systemImage: "number.square",
                    description: Text("Configure a provider or submit a local usage event.")
                )
            } else {
                ForEach(providers, id: \.self) { provider in
                    let providerSamples = samples.filter { $0.provider == provider }
                    let totals = UsageAggregator.totals(providerSamples)
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName(provider))
                                .font(.system(size: 12, weight: .semibold))
                            Text(sourceSummary(providerSamples))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(totals.input.formatted()) in")
                        Text("\(totals.cached.formatted()) cache")
                        Text("\(totals.output.formatted()) out")
                        Text(totals.total.formatted())
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    if provider != providers.last { Divider() }
                }
            }
        }
        .padding(14)
        .frame(width: 560, height: 280, alignment: .topLeading)
    }

    private func displayName(_ provider: UsageSample.Provider) -> String {
        switch provider {
        case .openAI: "OpenAI API"
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .trae: "Trae"
        case .external: "External"
        }
    }

    private func sourceSummary(_ values: [UsageSample]) -> String {
        let sources = Set(values.map(\.sourceType.rawValue)).sorted()
        return sources.joined(separator: ", ")
    }
}

private struct DeveloperPanel<Content: View>: View {
    let title: String
    let icon: String
    let status: Color
    let content: Content

    init(title: String, icon: String, status: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.status = status
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle().fill(status).frame(width: 6, height: 6)
                Image(systemName: icon)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.065))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct AIResultPopover: View {
    @ObservedObject var workspace: DeveloperWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Local AI", systemImage: "cpu")
                    .font(.headline)
                Spacer()
                if workspace.isGenerating { ProgressView().controlSize(.small) }
            }
            Divider()
            ScrollView {
                Text(workspace.aiError ?? (workspace.aiOutput.isEmpty ? "Waiting for Ollama…" : workspace.aiOutput))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(workspace.aiError == nil ? Color.primary : Color.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 520, height: 330)
    }
}
