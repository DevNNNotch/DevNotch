import SwiftUI

struct UsageDashboardView: View {
    @ObservedObject private var workspace = DeveloperWorkspaceModel.shared
    @State private var selectedRange = UsageRange.today

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            dashboard(at: context.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private func dashboard(at now: Date) -> some View {
        let samples = selectedRange.samples(from: workspace.usageSamples, at: now)
        let totals = UsageAggregator.totals(samples)
        let providers = UsageAggregator.providerTotals(samples)

        return VStack(spacing: 0) {
            header(at: now)
                .frame(height: 34)

            horizontalDivider

            HStack(spacing: 0) {
                overview(totals: totals, providers: providers)
                    .frame(width: 188)

                verticalDivider

                VStack(spacing: 0) {
                    summaryMetrics(samples: samples, at: now)
                        .frame(height: 38)

                    horizontalDivider

                    providerList(providers, samples: samples)
                }
                .padding(.leading, 14)
            }
            .padding(.horizontal, 16)

            horizontalDivider

            footer(totals: totals, samples: samples, at: now)
                .frame(height: 30)
        }
    }

    private func header(at now: Date) -> some View {
        HStack(spacing: 8) {
            Text("AI TOKEN USAGE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))

            Spacer(minLength: 12)

            Menu {
                ForEach(UsageRange.allCases) { range in
                    Button {
                        selectedRange = range
                    } label: {
                        if range == selectedRange {
                            Label(range.label, systemImage: "checkmark")
                        } else {
                            Text(range.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedRange.label)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Usage range")
            .accessibilityValue(selectedRange.label)

            status(at: now)
        }
        .padding(.horizontal, 16)
    }

    private func status(at now: Date) -> some View {
        let latest = workspace.usageSamples.map(\.timestamp).max()
        let isLive = latest.map { abs(now.timeIntervalSince($0)) <= 120 } ?? false
        let label = latest == nil ? "NO DATA" : (isLive ? "LIVE" : "SYNCED")

        return HStack(spacing: 4) {
            Circle()
                .fill(isLive ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage status: \(label)")
    }

    private func overview(
        totals: (input: Int, cached: Int, output: Int, total: Int),
        providers: [UsageAggregator.ProviderTotal]
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TOTAL / \(selectedRange.shortLabel)")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(compact(totals.total))
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("TOKENS · \(providers.count) \(providers.count == 1 ? "CLIENT" : "CLIENTS")")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer(minLength: 3)

            platformMix(providers)

            HStack {
                Text("CLIENT MIX")
                Spacer(minLength: 4)
                Text(mixPercentages(providers))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.system(size: 6.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 14)
    }

    private func platformMix(_ providers: [UsageAggregator.ProviderTotal]) -> some View {
        let grandTotal = providers.reduce(0) { $0 + $1.total }

        return GeometryReader { geometry in
            if grandTotal == 0 {
                Capsule().fill(Color.white.opacity(0.1))
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                        let width = geometry.size.width * CGFloat(provider.total) / CGFloat(grandTotal)
                        Rectangle()
                            .fill(mixColor(at: index))
                            .frame(width: max(2, width - 2))
                    }
                }
            }
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Client mix: \(mixAccessibilityLabel(providers))")
    }

    private func summaryMetrics(samples: [UsageSample], at now: Date) -> some View {
        let hourStart = now.addingTimeInterval(-3_600)
        let lastHour = UsageAggregator.totals(
            workspace.usageSamples.filter { $0.timestamp >= hourStart && $0.timestamp <= now }
        ).total
        let cacheRate = UsageAggregator.cacheHitRate(samples)

        return HStack(spacing: 0) {
            summaryMetric("LAST HOUR", compact(lastHour))
            metricDivider
            summaryMetric("CACHE HIT", cacheRate?.formatted(.percent.precision(.fractionLength(0))) ?? "—")
            metricDivider
            summaryMetric("EST. COST", estimatedCostText(for: samples))
                .help(costAvailabilityDescription(for: samples))
        }
    }

    private func summaryMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func providerList(
        _ providers: [UsageAggregator.ProviderTotal],
        samples: [UsageSample]
    ) -> some View {
        if providers.isEmpty {
            VStack(spacing: 4) {
                Label("NO USAGE EVENTS", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                Text("Run a client adapter or submit a local usage event.")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let largestTotal = max(1, providers.first?.total ?? 1)
            VStack(spacing: 3) {
                ForEach(providers) { provider in
                    providerRow(
                        provider,
                        largestTotal: largestTotal,
                        totalAcrossProviders: providers.reduce(0) { $0 + $1.total },
                        samples: samples.filter { $0.provider == provider.provider }
                    )
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func providerRow(
        _ provider: UsageAggregator.ProviderTotal,
        largestTotal: Int,
        totalAcrossProviders: Int,
        samples: [UsageSample]
    ) -> some View {
        let share = totalAcrossProviders > 0 ? Double(provider.total) / Double(totalAcrossProviders) : 0

        return HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: providerIcon(provider.provider))
                    .foregroundStyle(providerColor(provider.provider))
                    .frame(width: 11)
                Text(providerName(provider.provider))
                    .lineLimit(1)
            }
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .frame(width: 78, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: geometry.size.width * CGFloat(provider.total) / CGFloat(largestTotal))
                }
            }
            .frame(height: 6)

            Text(compact(provider.total))
                .frame(width: 38, alignment: .trailing)
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .foregroundStyle(.secondary)
                .frame(width: 27, alignment: .trailing)
            Text(estimatedCostText(for: samples))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
                .help(costAvailabilityDescription(for: samples))
        }
        .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(providerName(provider.provider)), \(provider.total) tokens, \(share.formatted(.percent.precision(.fractionLength(0)))) of selected usage"
        )
    }

    private func footer(
        totals: (input: Int, cached: Int, output: Int, total: Int),
        samples: [UsageSample],
        at now: Date
    ) -> some View {
        HStack(spacing: 22) {
            footerMetric("IN", totals.input)
            footerMetric("OUT", totals.output)
            footerMetric("CACHE", totals.cached)

            Spacer(minLength: 8)

            if let error = samples.compactMap(\.collectionError).first {
                Label("SOURCE ERROR", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(error)
                    .accessibilityHint(error)
            }

            Text("UPDATED \(updatedAge(at: now))")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
    }

    private func footerMetric(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(compact(value)).fontWeight(.semibold)
        }
    }

    private var horizontalDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 25)
            .padding(.horizontal, 10)
    }

    private func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    private func mixPercentages(_ providers: [UsageAggregator.ProviderTotal]) -> String {
        let total = providers.reduce(0) { $0 + $1.total }
        guard total > 0 else { return "—" }
        return providers.map { provider in
            (Double(provider.total) / Double(total)).formatted(.percent.precision(.fractionLength(0)))
        }.joined(separator: " / ")
    }

    private func mixAccessibilityLabel(_ providers: [UsageAggregator.ProviderTotal]) -> String {
        let total = providers.reduce(0) { $0 + $1.total }
        guard total > 0 else { return "no data" }
        return providers.map { provider in
            let percentage = Double(provider.total) / Double(total)
            return "\(providerName(provider.provider)) \(percentage.formatted(.percent.precision(.fractionLength(0))))"
        }.joined(separator: ", ")
    }

    private func estimatedCostText(for samples: [UsageSample]) -> String {
        let pricedSamples = samples.filter { $0.estimatedCost != nil }
        guard !pricedSamples.isEmpty else { return "—" }
        guard pricedSamples.allSatisfy({ $0.currency?.isEmpty == false }) else { return "ERR" }

        let currencies = Set(pricedSamples.compactMap(\.currency))
        guard currencies.count == 1, let currency = currencies.first else { return "MIXED" }

        let total = pricedSamples.compactMap(\.estimatedCost).reduce(Decimal.zero, +)
        return total.formatted(.currency(code: currency.uppercased()).precision(.fractionLength(2)))
    }

    private func costAvailabilityDescription(for samples: [UsageSample]) -> String {
        let pricedSamples = samples.filter { $0.estimatedCost != nil }
        guard !pricedSamples.isEmpty else { return "No selected usage source reports estimated cost." }
        guard pricedSamples.allSatisfy({ $0.currency?.isEmpty == false }) else {
            return "A usage source reported cost without a currency."
        }
        let currencies = Set(pricedSamples.compactMap(\.currency))
        return currencies.count == 1 ? "Estimated cost reported by usage sources." : "Costs use multiple currencies and cannot be combined."
    }

    private func updatedAge(at now: Date) -> String {
        guard let latest = workspace.usageSamples.map(\.timestamp).max() else { return "NEVER" }
        let interval = Int(now.timeIntervalSince(latest))
        guard interval >= 0 else { return "CLOCK ERROR" }
        if interval < 60 { return "\(interval)S AGO" }
        if interval < 3_600 { return "\(interval / 60)M AGO" }
        if interval < 86_400 { return "\(interval / 3_600)H AGO" }
        return "\(interval / 86_400)D AGO"
    }

    private func providerName(_ provider: UsageSample.Provider) -> String {
        switch provider {
        case .openAI: "OpenAI"
        case .codex: "Codex"
        case .claudeCode: "Claude"
        case .trae: "Trae"
        case .external: "External"
        }
    }

    private func providerIcon(_ provider: UsageSample.Provider) -> String {
        switch provider {
        case .openAI: "circle.hexagongrid.fill"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .claudeCode: "sun.max.fill"
        case .trae: "sparkles"
        case .external: "network"
        }
    }

    private func providerColor(_ provider: UsageSample.Provider) -> Color {
        switch provider {
        case .openAI: .cyan
        case .codex: .blue
        case .claudeCode: .orange
        case .trae: .purple
        case .external: .gray
        }
    }

    private func mixColor(at index: Int) -> Color {
        switch index {
        case 0: .white
        case 1: Color.white.opacity(0.72)
        case 2: Color.white.opacity(0.5)
        case 3: Color.white.opacity(0.32)
        default: Color.white.opacity(0.18)
        }
    }
}

private enum UsageRange: String, CaseIterable, Identifiable {
    case today
    case sevenDays
    case allTime

    var id: Self { self }

    var label: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "Last 7 Days"
        case .allTime: "All Time"
        }
    }

    var shortLabel: String {
        switch self {
        case .today: "TODAY"
        case .sevenDays: "7 DAYS"
        case .allTime: "ALL TIME"
        }
    }

    func samples(from samples: [UsageSample], at now: Date) -> [UsageSample] {
        samples.filter { sample in
            guard sample.timestamp <= now else { return false }
            switch self {
            case .today:
                return Calendar.current.isDate(sample.timestamp, inSameDayAs: now)
            case .sevenDays:
                return sample.timestamp >= now.addingTimeInterval(-604_800)
            case .allTime:
                return true
            }
        }
    }
}
