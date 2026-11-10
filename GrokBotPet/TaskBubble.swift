import AppKit
import SwiftUI

@MainActor
final class TaskBubble {
    private let panel: NSPanel
    private var host: NSHostingView<BubbleView>?

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Lumo Task Status"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    func show(_ activity: TaskActivity, beside pet: NSWindow) {
        guard let screen = pet.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 6, dy: 6)
        let below = visible.maxY - pet.frame.maxY < 50
        let view = BubbleView(activity: activity, below: below)
        if let host {
            if host.rootView != view { host.rootView = view }
        } else {
            let host = NSHostingView(rootView: view)
            panel.contentView = host
            self.host = host
        }

        guard let host else { return }
        let size = host.fittingSize
        let x = max(visible.minX, min(pet.frame.midX - size.width / 2, visible.maxX - size.width))
        let preferredY = below ? pet.frame.minY + 18 - size.height : pet.frame.maxY - 16
        let y = max(visible.minY, min(preferredY, visible.maxY - size.height))
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct BubbleView: View, Equatable {
    let activity: TaskActivity
    let below: Bool

    private var tint: Color {
        switch activity.step {
        case .approval, .input: .orange
        case .done: .green
        case .stopped: .secondary
        default: .teal
        }
    }

    private var icon: String {
        switch activity.step {
        case .approval: "exclamationmark.circle.fill"
        case .input: "questionmark.circle.fill"
        case .done: "checkmark.circle.fill"
        case .stopped: "pause.circle.fill"
        default: "circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            if below {
                dot(4)
                dot(7)
            }
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: activity.step.isFinished || activity.step.needsUserAction ? 13 : 7))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.step.title).font(.system(size: 13, weight: .semibold))
                    if activity.otherActiveTasks > 0 {
                        Text("+\(activity.otherActiveTasks) more")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(.primary.opacity(0.12)) }
            if !below {
                dot(7)
                dot(4)
            }
        }
        .fixedSize()
        .padding(2)
        .accessibilityElement(children: .combine)
    }

    private func dot(_ size: CGFloat) -> some View {
        Circle()
            .fill(.regularMaterial)
            .overlay { Circle().strokeBorder(.primary.opacity(0.12)) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
