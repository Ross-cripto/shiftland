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
            let device = MacSetupDevice.current
            let installation = OmniInstallation.installed(for: device)
            print("Mac: macOS \(device.macOS.label) · \(device.architecture.label)")
            if let engine = installation.installation {
                print("OmniWM: \(engine.version ?? "versión sin identificar")")
            }
            do {
                let client = try installation.client()
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
    private static let completedSetupKey = "didConnectToOmniWM"
    private static let workspaceZeroNumber = 10
    private let preview: Bool
    private let icons = ApplicationIcons()
    private let setup = WorkspaceSetupModel(device: .current)
    private var panels: [String: WorkspacePanel] = [:]
    private var statusItem: NSStatusItem?
    private var engineStatus: NSMenuItem?
    private var shortcutStatus: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var subscription: Task<Void, Never>?
    private var connectedClient: OmniClient?
    private var snapshot: WorkspaceSnapshot?
    private var zeroShortcuts: WorkspaceZeroShortcuts?
    private var hasShownSetup = false

    init(preview: Bool) {
        self.preview = preview
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        subscription = Task { await connect() }
        if CommandLine.arguments.contains("--settings") { showSettings() }
        if CommandLine.arguments.contains("--setup") { showSetup() }
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
            let installation = OmniInstallation.installed(for: setup.device)
            do {
                let client = try installation.client()
                let initial = try await client.snapshot()
                try Task.checkCancellation()
                connectedClient = client
                accept(initial, from: installation.installation)
                for try await updated in client.snapshots() {
                    try Task.checkCancellation()
                    accept(updated, from: installation.installation)
                }
                try Task.checkCancellation()
                throw OmniError.disconnected
            } catch {
                if Task.isCancelled { return }
                engineStatus?.title = error.localizedDescription
                connectedClient = nil
                snapshot = nil
                displaySnapshot()
                updateSetup(.failed(error, installation: OmniInstallation.installed(for: setup.device)))
                try? await Task.sleep(for: Self.retryDelay)
            }
        }
    }

    private func accept(_ updated: WorkspaceSnapshot, from installation: OmniInstallation?) {
        let hasWorkspaces = updated.monitors.contains { !$0.workspaces.isEmpty }
        engineStatus?.title = hasWorkspaces ? "Conectado a OmniWM" : "OmniWM aún no muestra espacios"
        updateSetup(SetupAssessment(hasWorkspaces ? .connected : .noWorkspaces, installation: installation))
        guard snapshot != updated else { return }
        snapshot = updated
        displaySnapshot()
    }

    private func updateSetup(_ assessment: SetupAssessment) {
        guard setup.assessment != assessment else { return }
        setup.assessment = assessment
        guard !preview else { return }

        if assessment.step == .connected {
            setup.openError = nil
            UserDefaults.standard.set(true, forKey: Self.completedSetupKey)
            if zeroShortcuts == nil { registerZeroShortcuts() }
        } else if !hasShownSetup,
                  !UserDefaults.standard.bool(forKey: Self.completedSetupKey),
                  settingsWindow == nil {
            showSetup()
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
        guard let client = connectedClient else { return }
        Task {
            do {
                try await client.command(arguments)
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
        let setup = NSMenuItem(title: "Configurar conexión…", action: #selector(showSetup), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
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

    @objc private func showSetup() {
        hasShownSetup = true
        let window: NSWindow
        if let setupWindow {
            window = setupWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 490, height: 290),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Configurar \(AppBrand.name)"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WorkspaceSetupView(
                model: setup,
                recheck: { [weak self] in self?.recheckSetup() },
                openEngine: { [weak self] in self?.openEngine() },
                openSettings: { [weak self] in self?.showSettings() }
            ))
            window.center()
            setupWindow = window
        }
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func recheckSetup() {
        setup.openError = nil
        setup.assessment = SetupAssessment(.checking, installation: setup.assessment.installation)
        subscription?.cancel()
        subscription = Task { await connect() }
    }

    private func openEngine() {
        guard let installation = setup.assessment.installation else { return }
        setup.openError = nil
        guard NSWorkspace.shared.open(installation.bundleURL) else {
            setup.openError = "No se pudo abrir OmniWM. Prueba a abrirlo desde Finder."
            return
        }
        if setup.assessment.step != .connected { recheckSetup() }
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
            guard let zero = spaces.first(where: { $0.number == Self.workspaceZeroNumber }) else { return }
            if move {
                run(["command", "move-to-workspace", String(Self.workspaceZeroNumber)])
            } else {
                run(["workspace", "focus-name", zero.rawName])
            }
        }
        do {
            try shortcuts.start()
            zeroShortcuts = shortcuts
            shortcutStatus?.isHidden = true
        } catch {
            shortcutStatus?.title = error.localizedDescription
            shortcutStatus?.isHidden = false
        }
    }
}
