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
    // A minimized main window needs a Dock application tile even in menu-only
    // mode. This is transient presentation, never a persisted entry preference.
    private(set) var mainWindowIsMiniaturized = false

    func mainWindowMiniaturizationChanged(_ value: Bool) {
        mainWindowIsMiniaturized = value
        reconcileActivationPolicy()
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        configuration = MacAppEntryConfiguration.load(from: defaults)
    }

    func start() async { await apply(configuration) }

    /// SwiftUI/Launch Services may promote a windowed accessory app. Reassert
    /// the saved policy at lifecycle boundaries without changing the preference.
    /// Accessory windows can be key and activated; opening one needs no Dock.
    func reconcileActivationPolicy() {
        guard !isTransitioning else { return }
        guard configuration.showDock || menuIsRegistered() else { return }
        let visible = configuration.showDock || mainWindowIsMiniaturized
        if setDockVisible(visible) {
            policyDescription = visible ? "regular" : "accessory"
        } else {
            fail(configuration, inserted: isMenuInserted)
        }
    }

    /// Enable and verify the replacement before removing a working entry.
    /// Persistence follows the OS operation, never precedes it.
    func apply(_ requested: MacAppEntryConfiguration, rejectAllHidden: Bool = false) async {
        guard !isTransitioning else { return }
        if rejectAllHidden && !requested.showMenuBar && !requested.showDock {
            message = L10n.text("mac.appEntryController.apply.1b06fd90b2"); return
        }
        let next = requested.normalized(), old = configuration, oldInserted = isMenuInserted
        isTransitioning = true; message = nil
        defer { isTransitioning = false }
        if next.showMenuBar { isMenuInserted = true }
        let effectiveDock = next.showDock || mainWindowIsMiniaturized
        if effectiveDock {
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
        policyDescription = effectiveDock ? "regular" : "accessory"
        configuration = next
        persist()
    }

    private func fail(_ old: MacAppEntryConfiguration, inserted: Bool) {
        isMenuInserted = inserted || old.showMenuBar
        var restored = old
        // Failure is observable. Never persist an unverified hidden state.
        if setDockVisible(old.showDock || mainWindowIsMiniaturized) {
            policyDescription = old.showDock || mainWindowIsMiniaturized ? "regular" : "accessory"
        } else if setDockVisible(true) {
            restored.showDock = true; policyDescription = "regular"
        } else {
            // Keep the state item as the remaining entry and report the failure.
            isMenuInserted = true; restored.showMenuBar = true
        }
        configuration = restored.normalized()
        message = L10n.text("mac.appEntryController.fail.3ba1e06e94")
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
        catch { message = L10n.text("mac.appEntryController.persist.d87ab19280") }
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
    private var mainWindowObservers: [NSObjectProtocol] = []
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
    func attachMainWindow(_ window: NSWindow?) {
        guard let window, !window.isSheet, mainWindow !== window else { return }
        for observer in mainWindowObservers { NotificationCenter.default.removeObserver(observer) }
        mainWindowObservers.removeAll()
        mainWindow = window
        entries.mainWindowMiniaturizationChanged(window.isMiniaturized)
        mainWindowObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.willMiniaturizeNotification, object: window, queue: .main) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, self.mainWindow === window else { return }
                // Set regular before AppKit creates the minimized Dock tile.
                self.entries.mainWindowMiniaturizationChanged(true)
            }
        })
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification, NSWindow.didDeminiaturizeNotification] {
            mainWindowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                if name == NSWindow.willCloseNotification {
                    MainActor.assumeIsolated { self?.entries.mainWindowMiniaturizationChanged(false) }
                }
                // Run after SwiftUI handles the event. Rapid reopen and configuration
                // changes use the latest preference, never a captured old policy.
                DispatchQueue.main.async {
                    guard let self, self.mainWindow === window else { return }
                    self.entries.mainWindowMiniaturizationChanged(window?.isMiniaturized == true)
                }
            })
        }
        entries.reconcileActivationPolicy()
    }
    func showMain(settings: Bool = false) {
        entries.reconcileActivationPolicy()
        showsSettings = settings
        if settings { settingsRequest = UUID() }
        closePanel()
        if settings && !Self.isPrototype { FinTrackMacApp.workspace.section = .settings }
        if let mainWindow, mainWindow.isVisible || mainWindow.isMiniaturized {
            if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
            mainWindow.makeKeyAndOrderFront(nil)
        } else { openMain?() }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { self.entries.reconcileActivationPolicy() }
    }
}

final class MacApplicationDelegate: NSObject, NSApplicationDelegate {
    private var typographyMonitor: Any?
    func applicationWillFinishLaunching(_ notification: Notification) { MacNotificationDelegate.shared.install() }
    func applicationDidBecomeActive(_ notification: Notification) {
        MacApplicationRuntime.shared.entries.reconcileActivationPolicy()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        MacNativeMenuLocalization.shared.install()
        typographyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command,.shift,.option,.control])
            if flags.contains(.command), flags.intersection([.option,.control]).isEmpty,
               ["=","+","-","0"].contains(event.charactersIgnoringModifiers ?? "") {
                let key = event.charactersIgnoringModifiers ?? ""
                if key == "0" {
                    if !flags.contains(.shift) { DispatchQueue.main.async { MacInterfaceZoom.reset() }; return nil }
                } else {
                    DispatchQueue.main.async { MacTypographyCommands.adjust(key == "-" ? -1 : 1) }
                    return nil
                }
            }
            return event
        }

        MacApplicationRuntime.shared.installHost()
        if !MacApplicationRuntime.isPrototype { MacFXApplication.shared.start() }
        Task { @MainActor in
            await MacApplicationRuntime.shared.entries.start()
            MacAppServices.shared.start()
            MacSelectionConversion.shared.start()
            let updateLaunch = await Task.detached(priority: .utility) { MacUpdateInstallation.launchReceipt() != nil }.value
            if updateLaunch {
                // An explicit update restart should restore the app even when
                // normal login launches are configured to stay in the menu bar.
                MacApplicationRuntime.shared.showMain()
                for _ in 0..<100 {
                    if MacApplicationRuntime.shared.mainWindow?.isVisible == true { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard MacApplicationRuntime.shared.mainWindow?.isVisible == true else { return }
            }
            // A visible failure gate is not a healthy replacement. Keep the
            // previous app until recovery and ledger initialization complete.
            for _ in 0..<1000 {
                if MacLedgerAccess.shared.canConfirmUpdateLaunch { break }
                if case .failed = MacLedgerAccess.shared.state { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard MacLedgerAccess.shared.canConfirmUpdateLaunch else { return }
            Task.detached(priority: .utility) { MacUpdateInstallation.confirmLaunch() }
            #if FINTRACK_LOCAL_VALIDATION
            MacUpdateService.shared.loadInstallationFixture()
            if let text = ProcessInfo.processInfo.environment["FINTRACK_SELECTION_FIXTURE"] {
                MacSelectionConversion.shared.presentFixture(text)
            }
            #endif
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let entries = MacAppEntryConfiguration.load(from: MacPreferences.defaults)
        if entries.showDock && !entries.showMenuBar { return false }
        return !(MacPreferences.defaults.object(forKey: "v141_background") as? Bool ?? true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MacApplicationRuntime.shared.showMain(); return false
    }
}
