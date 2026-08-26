//
//  HoverButton.swift
//  boringNotch
//
//  Created by Kraigo on 04.09.2024.
//

import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = Color(white: 0.9)
    var scale: Image.Scale = .medium
    /// When true, use the compact NotchNook-style sizing (24pt/28pt hit areas
    /// with small, weighted icon fonts) instead of the legacy 30pt/40pt
    /// sizing. Legacy call sites keep their original look by leaving this
    /// false.
    var compact: Bool = false
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect;

    @State private var isHovering = false

    private var size: CGFloat {
        if compact {
            return scale == .large ? 26 : 22
        }
        return scale == .large ? 40 : 30
    }

    private var iconFont: Font {
        if compact {
            return scale == .large ? .system(size: 14, weight: .bold) : .system(size: 11, weight: .bold)
        }
        return scale == .large ? .largeTitle : .body
    }

    var body: some View {
        Button(action: action) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(isHovering ? (compact ? Color.white.opacity(0.08) : Color.gray.opacity(0.2)) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(systemName: icon)
                                .foregroundColor(iconColor)
                                .contentTransition(contentTransition)
                                .font(iconFont)
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}
