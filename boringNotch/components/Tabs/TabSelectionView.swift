//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(coordinator.visibleViews) { view in
                    TabButton(label: view.tabLabel, icon: view.tabIcon, selected: coordinator.currentView == view) {
                        withAnimation(.smooth) {
                            coordinator.selectView(view)
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(view == coordinator.currentView ? .white : .gray)
                    .background {
                        if view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
        .animation(.smooth(duration: 0.25), value: coordinator.visibleViews)
    }
}

extension NotchViews {
    var tabLabel: String {
        switch self {
        case .home:
            return String(localized: "Music")
        case .developer:
            return String(localized: "Developer")
        case .usage:
            return String(localized: "AI token usage")
        }
    }

    var tabIcon: TabIcon {
        switch self {
        case .home:
            return .asset("MusicTabIcon")
        case .developer:
            return .system("terminal.fill")
        case .usage:
            return .system("chart.bar.xaxis")
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
