import AppKit
import Foundation

@MainActor
final class ClipboardService: ObservableObject {
    @Published private(set) var context: ClipboardContext?

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.inspectPasteboard()
            }
        }
        timer?.tolerance = 0.2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func inspectPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let content = pasteboard.string(forType: .string) else {
            context = nil
            return
        }
        context = ClipboardClassifier.classify(content)
    }
}
