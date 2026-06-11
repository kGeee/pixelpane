//
//  ResultPanelContainers.swift
//  PixelPane
//
//  Overlay/notch containers, visual-effect blur, and compact notch notification views.
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Glass Overlay Container

struct GlassOverlayContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.045),
                    Color.clear,
                    Color.black.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)

            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: OverlayPanelMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OverlayPanelMetrics.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}

struct NotchResultContainer<Content: View>: View {
    let isExpanded: Bool
    let roundsTopCorners: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            if isExpanded {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                    .opacity(0.42)
                Color.black.opacity(0.86)
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.98), location: 0.0),
                        .init(color: Color.black.opacity(0.96), location: 0.18),
                        .init(color: Color.black.opacity(0.88), location: 0.38),
                        .init(color: Color.black.opacity(0.80), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            } else {
                Color.clear
            }

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(shape)
        .padding(.horizontal, isExpanded ? 2 : 0)
        .padding(.bottom, isExpanded ? 2 : 0)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isExpanded && roundsTopCorners ? 30 : 0,
            bottomLeadingRadius: isExpanded ? 30 : 0,
            bottomTrailingRadius: isExpanded ? 30 : 8,
            topTrailingRadius: isExpanded && roundsTopCorners ? 30 : 0,
            style: .continuous
        )
    }
}

enum CompactNotchNotificationState {
    case processing

    var color: Color {
        Color(red: 1.0, green: 0.78, blue: 0.18)
    }
}

struct CompactNotchNotificationView: View {
    let state: CompactNotchNotificationState
    private let shape = UnevenRoundedRectangle(
        topLeadingRadius: 0,
        bottomLeadingRadius: 8,
        bottomTrailingRadius: 8,
        topTrailingRadius: 0,
        style: .continuous
    )

    var body: some View {
        shape
            .fill(Color(nsColor: .black))
            .overlay(CompactThinkingMoon(color: state.color))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

struct CompactThinkingMoon: View {
    let color: Color

    var body: some View {
        MoonPhaseIndicator(diameter: 9, color: color)
            .shadow(color: color.opacity(0.4), radius: 2)
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

