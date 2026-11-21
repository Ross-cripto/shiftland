import AppKit
import SwiftUI

enum AppBrand {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Shiftland"
    static let quitTitle = "Salir de \(name)"
}

@main
enum WorkspaceBarMain {
    @MainActor
    static func main() async {
        if CommandLine.arguments.contains("--diagnose") {
            do {
                let client = try OmniClient.installed()
                let snapshot = try await client.snapshot()
                let draft = try SettingsStore.installed.load()
                for monitor in snapshot.monitors {
                    let labels = monitor.orderedWorkspaces.map(\.label).joined(separator: ", ")
                    print("\(monitor.id) \(monitor.name): \(labels)")
                }
                print("Ajustes: \(draft.spaces.count) espacios y \(draft.shortcuts.count) atajos editables")
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(EXIT_FAILURE)
            }
            return
        }
        launch()
    }

    @MainActor
    private static func launch() {
        let application = NSApplication.shared
        let delegate = WorkspaceBarApplication(preview: CommandLine.arguments.contains("--preview"))
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class WorkspaceBarApplication: NSObject, NSApplicationDelegate {
    private static let retryDelay: Duration = .seconds(3)
    private let preview: Bool
    private let icons = ApplicationIcons()
    private var panels: [String: WorkspacePanel] = [:]
    private var statusItem: NSStatusItem?
    private var engineStatus: NSMenuItem?
    private var shortcutStatus: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var subscription: Task<Void, Never>?
    private var snapshot: WorkspaceSnapshot?
    private var zeroShortcuts: WorkspaceZeroShortcuts?

    init(preview: Bool) {
        self.preview = preview
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        if !preview { registerZeroShortcuts() }
        subscription = Task { await connect() }
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        subscription?.cancel()
        zeroShortcuts?.stop()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        displaySnapshot()
    }

    private func connect() async {
        while !Task.isCancelled {
            do {
                let client = try OmniClient.installed()
                for try await updated in client.snapshots() {
                    engineStatus?.title = "Conectado a OmniWM"
                    guard snapshot != updated else { continue }
                    snapshot = updated
                    displaySnapshot()
                }
            } catch {
                if Task.isCancelled { return }
                engineStatus?.title = error.localizedDescription
                snapshot = nil
                displaySnapshot()
                try? await Task.sleep(for: Self.retryDelay)
            }
        }
    }

    private func displaySnapshot() {
        var displayed = Set<String>()
        for screen in NSScreen.screens {
            guard let id = screen.omniDisplayId,
                  let monitor = snapshot?.monitors.first(where: { $0.id == id })
            else { continue }
            displayed.insert(id)
            let panel = panels[id] ?? WorkspacePanel()
            panels[id] = panel
            panel.display(
                monitor: monitor,
                screen: screen,
                interactionMonitorId: snapshot?.interactionMonitorId,
                icons: icons,
                preview: preview,
                focus: { [weak self] name in self?.run(["workspace", "focus-name", name]) },
                showSettings: { [weak self] in self?.showSettings() },
                quit: { NSApplication.shared.terminate(nil) }
            )
        }
        for id in Array(panels.keys) where !displayed.contains(id) {
            panels.removeValue(forKey: id)?.close()
        }
    }

    private func run(_ arguments: [String]) {
        Task {
            do {
                try await OmniClient.installed().command(arguments)
            } catch {
                engineStatus?.title = error.localizedDescription
            }
        }
    }

    private func installMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = ShiftlandStatusIcon.makeImage()
        statusItem.button?.toolTip = preview ? "\(AppBrand.name) · Vista previa" : AppBrand.name
        let menu = NSMenu()
        let connection = NSMenuItem(title: "Conectando a OmniWM…", action: nil, keyEquivalent: "")
        connection.isEnabled = false
        menu.addItem(connection)
        engineStatus = connection
        let shortcuts = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        shortcuts.isHidden = true
        menu.addItem(shortcuts)
        shortcutStatus = shortcuts
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Ajustes…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: "Acerca de \(AppBrand.name)", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: AppBrand.quitTitle, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc private func showAbout() {
        NSApplication.shared.activate()
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showSettings() {
        let window: NSWindow
        if let settingsWindow {
            window = settingsWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 570, height: 495),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = preview ? "\(AppBrand.name) · Vista previa" : AppBrand.name
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 530, height: 470)
            window.contentView = NSHostingView(rootView: WorkspaceSettingsView(store: .installed, preview: preview))
            window.center()
            settingsWindow = window
        }
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func registerZeroShortcuts() {
        let shortcuts = WorkspaceZeroShortcuts { [weak self] move in
            guard let self else { return }
            let spaces = snapshot?.monitors.flatMap(\.workspaces) ?? []
            guard let zero = spaces.first(where: { $0.number == 10 }) else { return }
            if move {
                run(["command", "move-to-workspace", String(zero.number)])
            } else {
                run(["workspace", "focus-name", zero.rawName])
            }
        }
        do {
            try shortcuts.start()
            zeroShortcuts = shortcuts
        } catch {
            shortcutStatus?.title = error.localizedDescription
            shortcutStatus?.isHidden = false
        }
    }
}
