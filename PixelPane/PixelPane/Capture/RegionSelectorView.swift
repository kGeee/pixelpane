import AppKit
import SwiftUI

struct RegionSelectorView: View {
    let screen: NSScreen
    let showFirstUseTip: Bool
    let onComplete: (CaptureSelection) -> Void
    let onCancel: () -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                OverlayDimmer(selectionRect: selectionRect)

                if let selectionRect {
                    SelectionFrame(rect: selectionRect)
                }

                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                    Text(selectionHint)
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.escape, modifiers: [])
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .padding(18)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(selectionGesture(in: geometry.size))
            .onExitCommand(perform: onCancel)
        }
        .ignoresSafeArea()
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragStart.x - dragCurrent.x),
            height: abs(dragStart.y - dragCurrent.y)
        )
    }

    private var selectionHint: String {
        guard let selectionRect else {
            return showFirstUseTip ? "Drag over text to ask Pixel Pane" : "Drag to capture text"
        }

        return "\(Int(selectionRect.width)) x \(Int(selectionRect.height))"
    }

    private func selectionGesture(in viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                }
                dragCurrent = value.location
            }
            .onEnded { _ in
                guard let selectionRect, selectionRect.width >= 20, selectionRect.height >= 20 else {
                    dragStart = nil
                    dragCurrent = nil
                    return
                }

                let screenRect = convertToScreenRect(selectionRect, viewHeight: viewSize.height)
                let captureRect = convertToCaptureRect(selectionRect)
                onComplete(CaptureSelection(screen: screen, screenRect: screenRect, captureRect: captureRect))
            }
    }

    private func convertToScreenRect(_ rect: CGRect, viewHeight: CGFloat) -> CGRect {
        CGRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + (viewHeight - rect.maxY),
            width: rect.width,
            height: rect.height
        )
    }

    private func convertToCaptureRect(_ rect: CGRect) -> CGRect {
        guard let displayID = screen.displayID else {
            return convertToScreenRect(rect, viewHeight: screen.frame.height)
        }

        let displayBounds = CGDisplayBounds(displayID)
        return CGRect(
            x: displayBounds.minX + rect.minX,
            y: displayBounds.minY + rect.minY,
            width: rect.width,
            height: rect.height
        ).integral
    }
}

private struct OverlayDimmer: View {
    let selectionRect: CGRect?

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geometry.size))
                if let selectionRect {
                    path.addRoundedRect(in: selectionRect, cornerSize: CGSize(width: 8, height: 8))
                }
            }
            .fill(Color.black.opacity(0.52), style: FillStyle(eoFill: true))
            .ignoresSafeArea()
        }
    }
}

private struct SelectionFrame: View {
    let rect: CGRect

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.92), lineWidth: 1)
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
                .shadow(color: Color.accentColor.opacity(0.5), radius: 8)
            cornerMarks
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private var cornerMarks: some View {
        ZStack {
            CornerMark()
                .frame(width: 18, height: 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            CornerMark()
                .rotationEffect(.degrees(90))
                .frame(width: 18, height: 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            CornerMark()
                .rotationEffect(.degrees(-90))
                .frame(width: 18, height: 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            CornerMark()
                .rotationEffect(.degrees(180))
                .frame(width: 18, height: 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .padding(5)
    }
}

private struct CornerMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
