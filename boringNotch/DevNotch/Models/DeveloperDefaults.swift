import Defaults
import Foundation

extension Defaults.Keys {
    static let developerWorkspaceEnabled = Key<Bool>("developerWorkspaceEnabled", default: true)
    static let developerSystemMonitoringEnabled = Key<Bool>("developerSystemMonitoringEnabled", default: true)
    static let developerClipboardMonitoringEnabled = Key<Bool>("developerClipboardMonitoringEnabled", default: true)
    static let developerLocalAPIEnabled = Key<Bool>("developerLocalAPIEnabled", default: false)
    static let developerCodexUsageEnabled = Key<Bool>("developerCodexUsageEnabled", default: false)
    static let developerCodexSessionsBookmark = Key<Data?>("developerCodexSessionsBookmark", default: nil)
    static let developerOllamaEnabled = Key<Bool>("developerOllamaEnabled", default: true)
    static let developerOllamaEndpoint = Key<String>("developerOllamaEndpoint", default: "http://127.0.0.1:11434")
    static let developerOllamaModel = Key<String>("developerOllamaModel", default: "qwen2.5-coder:7b")
    static let developerVLLMEnabled = Key<Bool>("developerVLLMEnabled", default: false)
    static let developerVLLMEndpoint = Key<String>("developerVLLMEndpoint", default: "http://127.0.0.1:8000")
    static let developerRefreshInterval = Key<Double>("developerRefreshInterval", default: 2)
    static let developerAnimationSpeed = Key<Double>("developerAnimationSpeed", default: 1)
}
