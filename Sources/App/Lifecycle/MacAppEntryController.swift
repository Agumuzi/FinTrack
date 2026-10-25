import SwiftUI
import AppKit

@MainActor
final class MacAppEntryController: ObservableObject {
    @Published private(set) var configuration: MacAppEntryConfiguration
    @Published private(set) var isMenuInserted = true
    @Published private(set) var isTransitioning = false
    @Published private(set) var message: String?
    @Published private(set) var policyDescription = "regular"
    var menuIsRegistered: () -> Bool = { false }
    var setDockVisible: (Bool) -> Bool = { visible in
        let expected: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        if NSApp.activationPolicy() == expected { return true }
        return NSApp.setActivationPolicy(expected) && NSApp.activationPolicy() == expected
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        configuration = MacAppEntryConfiguration.load(from: defaults)
    }

    func start() async { await apply(configuration) }

    /// Enable and verify the replacement before removing a working entry.
    /// Persistence follows the OS operation, never precedes it.
    func apply(_ requested: MacAppEntryConfiguration, rejectAllHidden: Bool = false) async {
        guard !isTransitioning else { return }
        if rejectAllHidden && !requested.showMenuBar && !requested.showDock {
            message = "菜单栏和 Dock 至少保留一个入口。"; return
        }
        let next = requested.normalized(), old = configuration, oldInserted = isMenuInserted
        isTransitioning = true; message = nil
        defer { isTransitioning = false }
        if next.showMenuBar { isMenuInserted = true }
        if next.showDock {
            guard setDockVisible(true) else { fail(old, inserted: oldInserted); return }
        } else {
            // Wait only for our own SwiftUI label installation acknowledgement.
            // Actual operability is verified in B UI tests, never screen-monitored.
            var registered = menuIsRegistered()
            for _ in 0..<20 where !registered {
                try? await Task.sleep(for: .milliseconds(50))
                registered = menuIsRegistered()
            }
            guard registered, setDockVisible(false) else { fail(old, inserted: oldInserted); return }
        }
        isMenuInserted = next.showMenuBar
        policyDescription = next.showDock ? "regular" : "accessory"
        configuration = next
        persist()
    }

    private func fail(_ old: MacAppEntryConfiguration, inserted: Bool) {
        isMenuInserted = inserted || old.showMenuBar
        var restored = old
        // Failure is observable. Never persist an unverified hidden state.
        if setDockVisible(old.showDock) {
            policyDescription = old.showDock ? "regular" : "accessory"
        } else if setDockVisible(true) {
            restored.showDock = true; policyDescription = "regular"
        } else {
            // Keep the state item as the remaining entry and report the failure.
            isMenuInserted = true; restored.showMenuBar = true
        }
        configuration = restored.normalized()
        message = "入口切换未完成，已保留原入口。请检查菜单栏或 Dock。"
        persist()
    }

    /// Reflect SwiftUI's binding without monitoring OS visibility or changing
    /// the user's Dock preference. Reopening the app is the recovery path.
    func systemChangedInsertion(_ inserted: Bool) {
        guard inserted != isMenuInserted else { return }
        Task { @MainActor in
            guard inserted != self.isMenuInserted else { return }
            self.isMenuInserted = inserted
        }
    }

    func remember(_ page: MacMenuBarPage) {
        guard configuration.pageMemory == .restart else { return }
        configuration.lastPage = page; persist()
    }

    private func persist() {
        do { defaults.set(try JSONEncoder().encode(configuration.normalized()), forKey: MacAppEntryConfiguration.storageKey) }
        catch { message = "入口设置未能保存。" }
    }
}

/// A narrow AppKit observation bridge, not a second status item or panel host.
struct MacMenuBarWindowProbe: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> Probe { let view = Probe(); view.onWindow = onWindow; return view }
    func updateNSView(_ view: Probe, context: Context) { view.onWindow = onWindow }
    final class Probe: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let captured = window
            DispatchQueue.main.async { [weak self] in self?.onWindow?(captured) }
        }
    }
}

@MainActor
final class MacApplicationRuntime: ObservableObject {
    #if FINTRACK_MENU_PROTOTYPE
    static let isPrototype = true
    #else
    static let isPrototype = false
    #endif
    static let shared = MacApplicationRuntime()
    let entries: MacAppEntryController
    let session: MacMenuBarSession
    weak var panelWindow: NSWindow?
    weak var mainWindow: NSWindow?
    private var host: MacMenuBarHost?
    private var restoreObserver: NSObjectProtocol?
    var openMain: (() -> Void)?
    @Published var showsSettings = false
    @Published private(set) var settingsRequest = UUID()

    private init() {
        entries = MacAppEntryController(defaults: MacPreferences.defaults)
        session = MacMenuBarSession(configuration: entries.configuration)
        session.onPageSelected = { [weak entries] page in entries?.remember(page) }
        restoreObserver = NotificationCenter.default.addObserver(forName: MacSettingsStore.restoreCompleted, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let restored = MacAppEntryConfiguration.load(from: MacPreferences.defaults)
                await self.entries.apply(restored)
                MacFXApplication.shared.reload()
            }
        }

    }
    func installHost() { if host == nil { host = MacMenuBarHost(runtime: self) } }
    func closePanel() { host?.close() }
    func showMain(settings: Bool = false) {
        showsSettings = settings
        if settings { settingsRequest = UUID() }
        closePanel()
        if settings && !Self.isPrototype { FinTrackMacApp.workspace.section = .settings }
        if let mainWindow, mainWindow.isVisible || mainWindow.isMiniaturized {
            if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
            mainWindow.makeKeyAndOrderFront(nil)
        } else { openMain?() }
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class MacApplicationDelegate: NSObject, NSApplicationDelegate {
    private var typographyMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        typographyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command,.shift,.option,.control])
            if flags.contains(.command), flags.intersection([.option,.control]).isEmpty,
               ["=","+"].contains(event.charactersIgnoringModifiers ?? "") {
                MacTypographyCommands.adjust(1); return nil
            }
            return event
        }

        MacApplicationRuntime.shared.installHost()
        if !MacApplicationRuntime.isPrototype { MacFXApplication.shared.start() }
        Task { @MainActor in
            await MacApplicationRuntime.shared.entries.start()
            MacAppServices.shared.start()
            MacSelectionConversion.shared.start()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(MacPreferences.defaults.object(forKey: "v141_background") as? Bool ?? true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MacApplicationRuntime.shared.showMain(); return false
    }
}
