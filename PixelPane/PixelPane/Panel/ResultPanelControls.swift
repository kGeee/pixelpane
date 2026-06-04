//
//  ResultPanelControls.swift
//  PixelPane
//
//  Badges, buttons, action bar/tabs, chips, menus, and the overlay text field.
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Header bits

struct ActionGradientBadge: View {
    let systemImage: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.95),
                            Color.accentColor.opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                        .blendMode(.plusLighter)
                }
                .shadow(color: Color.accentColor.opacity(0.45), radius: 10, y: 3)

            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
        }
        .frame(width: 36, height: 36)
    }
}

struct NotchHeaderStatusDot: View {
    var body: some View {
        Circle()
            .fill(.white.opacity(0.72))
            .frame(width: 5, height: 5)
            .shadow(color: .white.opacity(0.36), radius: 5)
            .frame(width: 10, height: 18)
    }
}

struct OverlayCloseButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(hovered ? 0.14 : 0.07))
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 1)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovered ? .primary : .secondary)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Close (Esc)")
        .keyboardShortcut(.cancelAction)
    }
}

// MARK: - Action tab bar

struct SegmentedActionBar: View {
    let actions: [PanelActionState]
    let onSelect: (PanelActionState) -> Void
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(actions) { action in
                ActionTab(
                    action: action,
                    namespace: indicator,
                    onSelect: onSelect
                )
            }
        }
        .padding(4)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }
}

struct ActionTab: View {
    let action: PanelActionState
    let namespace: Namespace.ID
    let onSelect: (PanelActionState) -> Void
    @State private var hovered = false

    var body: some View {
        Button {
            onSelect(action)
        } label: {
            HStack(spacing: 6) {
                if action.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(action.isSelected ? Color.accentColor : .secondary)
                } else {
                    Image(systemName: action.kind.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(action.kind.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    if action.isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.16),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.white.opacity(0.16), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                            .matchedGeometryEffect(id: "indicator", in: namespace)
                    } else if hovered, action.isEnabled {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.05))
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .help(action.disabledReason ?? action.kind.title)
        .onHover { hovered = $0 }
    }

    private var foreground: Color {
        if !action.isEnabled {
            return .secondary.opacity(0.45)
        }
        return action.isSelected ? .primary : .primary.opacity(0.62)
    }
}

// MARK: - Buttons

struct EmptyAssistantStatusChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.white.opacity(0.055), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

struct OverlayPillButton: View {
    enum Style {
        case primary, secondary, accent
    }

    enum DisplayStyle {
        case iconAndTitle, prominentIconAndTitle, iconOnly
    }

    let title: String
    let systemImage: String
    let style: Style
    var displayStyle: DisplayStyle = .iconAndTitle
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: displayStyle == .iconOnly ? 0 : 6) {
                Image(systemName: systemImage)
                    .font(.system(size: displayStyle == .prominentIconAndTitle ? 12 : 11.5, weight: .semibold))

                if displayStyle != .iconOnly {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(foreground)
            .frame(width: buttonWidth)
            .padding(.horizontal, displayStyle == .iconOnly ? 0 : 12)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
            .shadow(color: shadow, radius: 4, y: 1)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .frame(width: buttonWidth, height: 36)
        .fixedSize()
        .onHover { hovered = $0 && isEnabled }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .help(title)
    }

    private var buttonWidth: CGFloat? {
        switch displayStyle {
        case .iconOnly:
            return 36
        case .prominentIconAndTitle:
            return 88
        case .iconAndTitle:
            return nil
        }
    }

    private var foreground: Color {
        switch style {
        case .accent:
            return .black
        case .primary, .secondary:
            return .primary
        }
    }

    private var fill: AnyShapeStyle {
        switch style {
        case .accent:
            return AnyShapeStyle(Color.white.opacity(hovered ? 1.0 : 0.92))
        case .primary:
            return AnyShapeStyle(.white.opacity(hovered ? 0.14 : 0.09))
        case .secondary:
            return AnyShapeStyle(.white.opacity(hovered ? 0.09 : 0.04))
        }
    }

    private var stroke: Color {
        switch style {
        case .accent:
            return .white.opacity(0.0)
        case .primary:
            return .white.opacity(0.10)
        case .secondary:
            return .white.opacity(0.06)
        }
    }

    private var shadow: Color {
        switch style {
        case .accent:
            return .black.opacity(0.18)
        case .primary, .secondary:
            return .black.opacity(0.10)
        }
    }
}

struct FileSourceMenuButton: View {
    let grants: [LocalFileGrant]
    let isDisabled: Bool
    let onGrantFolder: () -> Void
    let onGrantFile: () -> Void
    let onRemove: (LocalFileGrant) -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            Button {
                onGrantFolder()
            } label: {
                Label("Choose Folder", systemImage: "folder.badge.plus")
            }

            Button {
                onGrantFile()
            } label: {
                Label("Choose File", systemImage: "doc.badge.plus")
            }

            if grants.isEmpty {
                Divider()
                Text("No file sources")
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                ForEach(grants) { grant in
                    Menu {
                        Button(role: .destructive) {
                            onRemove(grant)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(grant.displayName)
                                Text("\(grant.kindLabel): \(grant.path)")
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: grant.isDirectory ? "folder" : "doc.text")
                        }
                    }
                }

                Divider()
                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("Clear File Sources", systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: grants.isEmpty ? "folder" : "folder.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .frame(width: 40)
            .frame(height: 40)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(isDisabled)
        .help(grants.isEmpty ? "Choose files Pixel Pane can read" : "Change file sources")
    }

}

struct AssistantImageMenuButton: View {
    let context: AssistantImageContext?
    let isPreparing: Bool
    let isDisabled: Bool
    let onChoose: () -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            Button {
                onChoose()
            } label: {
                Label(context == nil ? "Choose Image" : "Replace Image", systemImage: "photo.badge.plus")
            }

            if let context {
                Divider()
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.label)
                        Text(context.isOCRComplete ? "Text fallback ready" : "Preparing text fallback")
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "photo")
                }

                Divider()
                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("Clear Image", systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: context == nil ? "photo" : "photo.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(context == nil ? .secondary : .primary)
            .frame(width: 40)
            .frame(height: 40)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(context == nil ? 0.08 : 0.16), lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(isDisabled || isPreparing)
        .help(context == nil ? "Attach an image" : "Change attached image")
    }
}

struct OverlayTextField: View {
    let placeholder: String
    @Binding var text: String
    let height: CGFloat
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(.primary)
            .lineLimit(1...5)
            .frame(maxWidth: .infinity, minHeight: 20, maxHeight: max(20, height - 16), alignment: .topLeading)
            .focused(isFocused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
    }
}

// MARK: - Metadata chip

struct OverlayMetadataChip: View {
    let badge: MetadataBadge

    var body: some View {
        Label(badge.text, systemImage: badge.systemImage)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.05), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.06), lineWidth: 1)
            }
            .help(badge.help)
    }
}

