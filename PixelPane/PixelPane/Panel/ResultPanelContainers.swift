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
    @State private var isPulsing = false
    private let shape = UnevenRoundedRectangle(
        topLeadingRadius: 0,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 4,
        topTrailingRadius: 0,
        style: .continuous
    )

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                shape
                    .fill(Color(nsColor: .black))
                    .frame(
                        width: ResultPanelPresentationStyle.notchCompactSize.width,
                        height: ResultPanelPresentationStyle.notchCompactSize.height
                    )

                Circle()
                    .fill(state.color.opacity(0.22))
                    .frame(width: 14, height: 8)
                    .blur(radius: 6)
                    .scaleEffect(isPulsing ? 1.18 : 0.88)
                    .opacity(isPulsing ? 0.64 : 0.26)

                CompactThinkingDots(color: state.color)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

struct CompactThinkingDots: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color.opacity(animate ? 1.0 : 0.5))
                    .frame(width: 2.8, height: 2.8)
                    .scaleEffect(animate ? 1.18 : 0.72)
                    .offset(y: animate ? -1.2 : 1.0)
                    .shadow(color: color.opacity(0.55), radius: animate ? 3 : 1.5)
                    .animation(
                        .easeInOut(duration: 0.62)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.16),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
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

