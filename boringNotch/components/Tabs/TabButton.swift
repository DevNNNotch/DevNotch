//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

enum TabIcon {
    case system(String)
    case asset(String)
}

struct TabButton: View {
    let label: String
    let icon: TabIcon
    let selected: Bool
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            iconView
                .frame(width: 18, height: 18)
                .padding(.horizontal, 15)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(selected ? "Selected" : "")
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        }
    }
}

#Preview {
    TabButton(label: "Home", icon: .system("tray.fill"), selected: true) {
        print("Tapped")
    }
}
