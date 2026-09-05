import SwiftUI

struct CodexActivityGlow: View {
    let shape: NotchShape

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                activityStroke(angle: .degrees(35), dashPhase: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    activityStroke(
                        angle: .degrees(elapsed.truncatingRemainder(dividingBy: 3) * 120),
                        dashPhase: -elapsed * 28
                    )
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex is working")
    }

    private func activityStroke(angle: Angle, dashPhase: Double) -> some View {
        shape
            .stroke(
                AngularGradient(
                    colors: [
                        .clear,
                        Color.cyan.opacity(0.75),
                        .white,
                        Color.mint,
                        .clear,
                        Color.cyan.opacity(0.55),
                        .clear,
                    ],
                    center: .center,
                    angle: angle
                ),
                style: StrokeStyle(
                    lineWidth: 1.6,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: [28, 10],
                    dashPhase: dashPhase
                )
            )
            .shadow(color: .cyan.opacity(0.9), radius: 4)
            .shadow(color: .white.opacity(0.35), radius: 9)
    }
}

struct CodexCompletionView: View {
    let completion: CodexTaskCompletion
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.09))
                Image("ProviderCodex")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .padding(13)
            }
            .frame(width: 54, height: 54)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)
                    .background(Circle().fill(.black).padding(2))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("CODEX")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Text("Task completed")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(completion.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(completion.title)

                Text(completion.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss Codex completion")
            .accessibilityLabel("Dismiss Codex completion")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
    }
}
