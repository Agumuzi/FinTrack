import AppKit
import SwiftUI
import Combine

/// One native status item + transient popover, chosen after the SwiftUI/window
/// prototype could not reliably dismiss/reopen with the field editor focused.
@MainActor
final class MacMenuBarHost: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var item: NSStatusItem?
    private var insertion: AnyCancellable?
    private var subscriptions: [AnyCancellable] = []
    private var labelQueued = false
    private unowned let runtime: MacApplicationRuntime

    init(runtime: MacApplicationRuntime) {
        self.runtime = runtime
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let panel: AnyView
        #if FINTRACK_MENU_PROTOTYPE
        panel = AnyView(MacMenuBarPrototypePanel(session: runtime.session, entries: runtime.entries))
        #else
        panel = AnyView(MacMenuBarPanel(runtime: runtime, session: runtime.session, entries: runtime.entries))
        #endif
        popover.contentViewController = NSHostingController(rootView: panel)
        runtime.entries.menuIsRegistered = { [weak self] in self?.item?.button != nil }
        insertion = runtime.entries.$isMenuInserted.sink { [weak self] value in self?.setInserted(value) }
        if !MacApplicationRuntime.isPrototype {
            subscriptions.append(runtime.entries.$configuration.sink { [weak self] _ in self?.queueLabel() })
            subscriptions.append(MacFXApplication.shared.monitor.objectWillChange.sink { [weak self] _ in self?.queueLabel() })
            subscriptions.append(NotificationCenter.default.publisher(for:UserDefaults.didChangeNotification).sink { [weak self] _ in self?.queueLabel() })
        }
    }

    private func setInserted(_ inserted: Bool) {
        if !inserted {
            close()
            if let item { NSStatusBar.system.removeStatusItem(item); self.item = nil }
            return
        }
        guard item == nil else { return }
        let value = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        value.button?.image = FinTrackMacApp.menuIcon
        value.button?.setAccessibilityLabel(MacApplicationRuntime.isPrototype ? "FinTrack 原型" : "FinTrack")
        value.button?.setAccessibilityIdentifier(MacApplicationRuntime.isPrototype ? "fintrackPrototypeStatus" : "fintrackMenuStatus")
        value.button?.target = self
        value.button?.action = #selector(toggle)
        item = value
        queueLabel()
    }
    private func queueLabel() {
        guard !labelQueued else { return }; labelQueued = true
        DispatchQueue.main.async { [weak self] in self?.labelQueued = false; self?.updateLabel() }
    }
    private func updateLabel() {
        guard !MacApplicationRuntime.isPrototype, let button = item?.button else { return }
        let config = runtime.entries.configuration, app = MacFXApplication.shared
        app.menuPair = config.displayPair
        button.image = config.information == .rate ? nil : MacMenuBarLabel.image(config.iconStyle)
        button.imagePosition = .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize:MacUI.fontSize(.caption,tier:MacUI.fontTier),weight:.medium)
        button.title = config.information == .icon ? "" : MacMenuBarLabel.text(configuration: config, monitor: app.monitor)
        guard MacPreferences.defaults.object(forKey: "v141_show_help") as? Bool != false else { button.toolTip = nil; return }
        if let pair = config.displayPair, let quote = app.monitor.quote(pair) {
            button.toolTip = "FinTrack · " + pair.key + "\n每1单位：" + String(quote.unitRate) + "\n" + app.monitor.sourceName(quote) + "\n" + MacFXDates.label(quote.quoteTime) + (app.monitor.isCached(pair) ? "\n缓存" : "")
        } else { button.toolTip = "FinTrack · 点击打开快速记账、汇率列表与换算" }
    }

    @objc private func toggle() {
        if popover.isShown { close(); return }
        guard let button = item?.button else { return }
        runtime.session.opened(configuration: runtime.entries.configuration)
        let available = button.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        let requested = ProcessInfo.processInfo.environment["FINTRACK_MENU_TEST_HEIGHT"].flatMap(Double.init) ?? 720
        popover.contentSize = NSSize(width: MacApplicationRuntime.isPrototype ? 480 : 408, height: min(CGFloat(requested), max(280, available - 32)))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        runtime.panelWindow = popover.contentViewController?.view.window
        NSApp.activate(ignoringOtherApps: true)
        runtime.panelWindow?.makeKey()
    }
    func close() { if popover.isShown { popover.performClose(nil) } }
}
