import Defaults
import Foundation

public enum NotchViews: String, CaseIterable, Codable, Hashable, Identifiable, Sendable, Defaults.Serializable {
    case home
    case developer
    case usage

    public var id: String { rawValue }
}

struct NotchTabPreference: Codable, Equatable, Identifiable, Sendable, Defaults.Serializable {
    let view: NotchViews
    var isVisible: Bool

    var id: NotchViews { view }

    static let defaultConfiguration = NotchViews.allCases.map {
        NotchTabPreference(view: $0, isVisible: true)
    }

    static func normalized(_ configuration: [NotchTabPreference]) -> [NotchTabPreference] {
        var seen = Set<NotchViews>()
        var result = configuration.filter { seen.insert($0.view).inserted }

        for item in defaultConfiguration where !seen.contains(item.view) {
            result.append(item)
        }

        return result
    }

    static func visibleViews(in configuration: [NotchTabPreference]) -> [NotchViews] {
        normalized(configuration).filter(\.isVisible).map(\.view)
    }

    static func settingVisibility(
        of view: NotchViews,
        to isVisible: Bool,
        in configuration: [NotchTabPreference]
    ) throws -> [NotchTabPreference] {
        var result = normalized(configuration)
        guard let index = result.firstIndex(where: { $0.view == view }) else {
            throw NotchNavigationError.missingView(view)
        }

        if !isVisible,
           result[index].isVisible,
           result.lazy.filter(\.isVisible).count == 1
        {
            throw NotchNavigationError.requiresVisibleView
        }

        result[index].isVisible = isVisible
        return result
    }

    static func moving(
        _ view: NotchViews,
        to destinationIndex: Int,
        in configuration: [NotchTabPreference]
    ) throws -> [NotchTabPreference] {
        var result = normalized(configuration)
        guard let sourceIndex = result.firstIndex(where: { $0.view == view }) else {
            throw NotchNavigationError.missingView(view)
        }
        guard result.indices.contains(destinationIndex) else {
            throw NotchNavigationError.invalidDestination(destinationIndex)
        }
        guard sourceIndex != destinationIndex else { return result }

        let item = result.remove(at: sourceIndex)
        result.insert(item, at: destinationIndex)
        return result
    }
}

enum NotchNavigationError: LocalizedError, Equatable {
    case missingView(NotchViews)
    case invalidDestination(Int)
    case requiresVisibleView

    var errorDescription: String? {
        switch self {
        case .missingView(let view):
            return "Navigation page '\(view.rawValue)' is missing from the configuration."
        case .invalidDestination(let index):
            return "Navigation destination index \(index) is outside the configured page list."
        case .requiresVisibleView:
            return String(localized: "At least one page must remain visible.")
        }
    }
}
