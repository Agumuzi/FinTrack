import SwiftUI
import SwiftData
import AppKit

/// Native macOS entry point using the original eight SwiftData models.
@main
struct FinTrackMacApp: App {
    @NSApplicationDelegateAdaptor(MacApplicationDelegate.self) private var applicationDelegate
    @StateObject private var entries = MacApplicationRuntime.shared.entries
    init() { MacSettingsStore.migrateFontPreference() }

    @MainActor static let workspace = MacWorkspaceSession()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        let _ = configureRouter()
        #if FINTRACK_MENU_PROTOTYPE
        Window("FinTrack 原型", id: "menu-prototype-main") {
            MacMenuPrototypeMainView(runtime: MacApplicationRuntime.shared, entries: entries)
        }.defaultSize(width: 760, height: 800)
            .defaultLaunchBehavior(entries.configuration.showMainOnLaunch ? .presented : .suppressed)
        #else
        Window("FinTrack", id: "main") { Self.content() }
            .defaultSize(width: 1480, height: 900)
            .defaultLaunchBehavior(entries.configuration.showMainOnLaunch ? .presented : .suppressed)
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("设置…") { MacApplicationRuntime.shared.showMain(settings: true) }.keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(after: .windowArrangement) {
                    Button("打开主窗口") { MacApplicationRuntime.shared.showMain() }.keyboardShortcut("0", modifiers: .command)
                }
            }
        #endif
    }
    private func configureRouter() {
        #if FINTRACK_MENU_PROTOTYPE
        MacApplicationRuntime.shared.openMain = { openWindow(id: "menu-prototype-main") }
        #else
        MacApplicationRuntime.shared.openMain = { openWindow(id: "main") }
        #endif
    }

    static var menuIcon: NSImage {
        let icon = NSApp.applicationIconImage.copy() as! NSImage
        icon.size = NSSize(width: 20, height: 20)
        return icon
    }

    static func content() -> AnyView { AnyView(MacLedgerWorkspaceGate()) }
}
