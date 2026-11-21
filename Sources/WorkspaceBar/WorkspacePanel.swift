import AppKit
import SwiftUI

private enum BarStyle {
    static let slotWidth: CGFloat = 48
    static let groupHeight: CGFloat = 24
    static let slotHeight: CGFloat = 20
    static let iconSize: CGFloat = 16
    static let groupInset: CGFloat = 2
    static let notchGap: CGFloat = 6
    static let notchMenuHeight: CGFloat = 38
    static let menuHeight: CGFloat = 25
    static let previewOffset: CGFloat = 42
    static let surface = Color(red: 32 / 255, green: 38 / 255, blue: 49 / 255)
    static let border = Color(red: 59 / 255, green: 70 / 255, blue: 87 / 255)
    static let blue = Color(red: 139 / 255, green: 183 / 255, blue: 232 / 255)
    static let selectedText = Color(red: 16 / 255, green: 23 / 255, blue: 34 / 255)
    static let occupiedText = Color(red: 216 / 255, green: 226 / 255, blue: 239 / 255)
    static let emptyText = Color(red: 157 / 255, green: 174 / 255, blue: 196 / 255)
}

private enum FocusStyle {
    case active
    case visible
    case inactive
}

@MainActor
final class ApplicationIcons {
    private var images: [String: NSImage?] = [:]

    func firstTwo(for names: [String]) -> [NSImage] {
        names.prefix(2).compactMap { icon(for: $0) }
    }

    private func icon(for name: String) -> NSImage? {
        if let cached = images[name] { return cached }
        let workspace = NSWorkspace.shared
        var url = workspace.urlForApplication(withBundleIdentifier: name)
        if url == nil {
            let matchingApplication = workspace.runningApplications.first {
                $0.localizedName == name.trimmingCharacters(in: .controlCharacters)
            }
            url = matchingApplication?.bundleURL
        }
        let image = url.map { workspace.icon(forFile: $0.path) }
        images.updateValue(image, forKey: name)
        return image
    }
}

private struct WorkspaceButton: View {
    let slot: WorkspaceSlot
    let names: [String]
    let icons: [NSImage]
    let focus: FocusStyle
    let action: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(slot.label)
                    .font(.custom("HelveticaNeue-Medium", size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !icons.isEmpty { applicationIcon }
            }
            .padding(.horizontal, 2)
            .frame(width: BarStyle.slotWidth - 4, height: BarStyle.slotHeight)
            .foregroundStyle(foreground)
            .background(focus == .active ? BarStyle.blue : .clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                if focus == .visible {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(BarStyle.blue, lineWidth: 1)
                }
            }
            .frame(width: BarStyle.slotWidth, height: BarStyle.groupHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Espacio \(slot.label)")
        .accessibilityValue(names.isEmpty ? "Sin ventanas" : names.joined(separator: ", "))
        .accessibilityAddTraits(focus == .active ? .isSelected : [])
        .onHover(perform: hover)
    }

    private var foreground: Color {
        if focus == .active { return BarStyle.selectedText }
        if focus == .visible || !names.isEmpty { return BarStyle.occupiedText }
        return BarStyle.emptyText
    }

    @ViewBuilder
    private var applicationIcon: some View {
        if icons.count == 2 {
            HStack(spacing: 0) {
                image(icons[0])
                    .frame(width: BarStyle.iconSize / 2, alignment: .leading)
                    .clipped()
                image(icons[1])
                    .frame(width: BarStyle.iconSize / 2, alignment: .trailing)
                    .clipped()
            }
            .overlay {
                Rectangle().fill(BarStyle.surface.opacity(0.7))
                    .frame(width: 0.5, height: BarStyle.iconSize)
            }
        } else if let icon = icons.first {
            image(icon)
        }
    }

    private func image(_ icon: NSImage) -> some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: BarStyle.iconSize, height: BarStyle.iconSize)
            .accessibilityHidden(true)
    }
}

@MainActor
final class WorkspacePanel {
    let window: NSPanel
    private let tooltip: NSPanel
    private var hoveredIndex: Int?
    private var content: NSHostingView<AnyView>?

    init() {
        window = Self.makePanel(name: AppBrand.name)
        tooltip = Self.makePanel(name: "\(AppBrand.name) · Información del espacio")
        tooltip.ignoresMouseEvents = true
    }

    func close() {
        tooltip.orderOut(nil)
        window.orderOut(nil)
    }

    func display(
        monitor: WorkspaceMonitor,
        screen: NSScreen,
        interactionMonitorId: String?,
        icons: ApplicationIcons,
        preview: Bool,
        focus: @escaping (String) -> Void,
        showSettings: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        let slots = monitor.orderedWorkspaces
        guard !slots.isEmpty else { close(); return }
        let slotNames = slots.map(\.applicationNames)
        let slotIcons = slotNames.map { icons.firstTwo(for: $0) }
        let frame = placement(screen: screen, slots: slots.count, preview: preview)
        if window.frame != frame {
            tooltip.orderOut(nil)
            hoveredIndex = nil
        }
        let view = HStack(spacing: 0) {
            ForEach(slots.indices, id: \.self) { index in
                let slot = slots[index]
                WorkspaceButton(
                    slot: slot,
                    names: slotNames[index],
                    icons: slotIcons[index],
                    focus: Self.focusStyle(slot, monitorId: monitor.id, interactionMonitorId: interactionMonitorId),
                    action: { focus(slot.rawName) },
                    hover: { [weak self] hover in self?.hover(hover, index: index, names: slotNames[index]) }
                )
            }
        }
        .padding(.horizontal, BarStyle.groupInset)
        .background(BarStyle.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(BarStyle.border, lineWidth: 1) }
        .contextMenu {
            Button("Ajustes…", action: showSettings)
            Divider()
            Button(AppBrand.quitTitle, action: quit)
        }
        let rootView = AnyView(view)
        if let content {
            content.rootView = rootView
        } else {
            let content = NSHostingView(rootView: rootView)
            window.contentView = content
            self.content = content
        }
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    private func placement(screen: NSScreen, slots: Int, preview: Bool) -> CGRect {
        let screenFrame = screen.frame
        let width = CGFloat(slots) * BarStyle.slotWidth + 2 * BarStyle.groupInset
        let notchArea = screen.auxiliaryTopLeftArea
        let menuHeight = notchArea == nil ? BarStyle.menuHeight : BarStyle.notchMenuHeight
        var left = screenFrame.midX - width / 2
        if let notchArea {
            left = max(screenFrame.minX, notchArea.maxX - width - BarStyle.notchGap)
        }
        let offset = preview ? BarStyle.previewOffset : 0
        let top = screenFrame.maxY - (menuHeight + BarStyle.groupHeight) / 2 - offset
        return CGRect(x: left.rounded(), y: top.rounded(), width: width, height: BarStyle.groupHeight)
    }

    private func hover(_ entered: Bool, index: Int, names: [String]) {
        if !entered {
            if hoveredIndex == index {
                hoveredIndex = nil
                tooltip.orderOut(nil)
            }
            return
        }
        hoveredIndex = index
        let text = names.isEmpty ? "Sin ventanas" : names.joined(separator: " · ")
        let view = Text(text)
            .font(.custom("HelveticaNeue-Medium", size: 12))
            .lineLimit(1)
            .foregroundStyle(BarStyle.occupiedText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(BarStyle.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(BarStyle.border, lineWidth: 1) }
        let content = NSHostingView(rootView: view)
        let size = content.fittingSize
        let center = window.frame.minX + BarStyle.groupInset + (CGFloat(index) + 0.5) * BarStyle.slotWidth
        let bounds = window.screen?.frame ?? window.frame
        let left = min(max(bounds.minX, center - size.width / 2), max(bounds.minX, bounds.maxX - size.width))
        tooltip.contentView = content
        tooltip.setFrame(CGRect(x: left, y: window.frame.minY - size.height - 4,
                                width: min(size.width, bounds.width), height: size.height), display: true)
        tooltip.orderFrontRegardless()
    }

    private static func focusStyle(_ slot: WorkspaceSlot, monitorId: String, interactionMonitorId: String?) -> FocusStyle {
        guard slot.isFocused else { return .inactive }
        return monitorId == interactionMonitorId ? .active : .visible
    }

    private static func makePanel(name: String) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.title = name
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }
}

extension NSScreen {
    var omniDisplayId: String? {
        guard let identifier = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return "display:\(identifier.uint32Value)"
    }
}
