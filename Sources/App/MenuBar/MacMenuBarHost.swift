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
    private var lastIconKey: String?
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
            subscriptions.append(runtime.session.objectWillChange.sink{[weak self] _ in self?.queueLabel()})
            subscriptions.append(MacFXApplication.shared.query.objectWillChange.sink{[weak self] _ in self?.queueLabel()})
            subscriptions.append(runtime.entries.$configuration.sink { [weak self] _ in self?.queueLabel() })
            subscriptions.append(MacFXApplication.shared.monitor.objectWillChange.sink { [weak self] _ in self?.queueLabel() })
            subscriptions.append(NotificationCenter.default.publisher(for:UserDefaults.didChangeNotification).sink { [weak self] _ in self?.queueLabel() })
        }
    }

    private func setInserted(_ inserted: Bool) {
        if !inserted {
            close()
            if let item { NSStatusBar.system.removeStatusItem(item); self.item = nil; lastIconKey = nil }
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
        let iconKey = config.information == .rate ? "none" : config.iconStyle.rawValue
        if lastIconKey != iconKey {
            button.image = config.information == .rate ? nil : MacMenuBarLabel.image(config.iconStyle)
            button.imagePosition = .imageLeft
            lastIconKey = iconKey
        }
        let fontSize = min(14,max(10,MacUI.fontSize(.caption,tier:MacUI.fontTier)))
        if button.font?.pointSize != fontSize { button.font = .monospacedDigitSystemFont(ofSize:fontSize,weight:.medium) }
        if popover.isShown { resizePanel() }
        let title = config.information == .icon ? "" : MacMenuBarLabel.text(configuration: config, monitor: app.monitor)
        if button.title != title { button.title = title }
        guard MacPreferences.defaults.object(forKey: "v141_show_help") as? Bool != false else { button.toolTip = nil; return }
        if let pair = config.displayPair, let quote = app.monitor.quote(pair) {
            button.toolTip = "FinTrack · " + pair.key + "\n每1单位：" + String(quote.unitRate) + "\n" + app.monitor.sourceName(quote) + "\n" + MacFXDates.label(quote.quoteTime) + (app.monitor.isCached(pair) ? "\n缓存" : "")
        } else { button.toolTip = "FinTrack · 点击打开快速记账、汇率列表与换算" }
    }

    @objc private func toggle() {
        if popover.isShown { close(); return }
        guard let button = item?.button else { return }
        runtime.session.opened(configuration: runtime.entries.configuration)
        resizePanel()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        runtime.panelWindow = popover.contentViewController?.view.window
        NSApp.activate(ignoringOtherApps: true)
        runtime.panelWindow?.makeKey()
    }
    private func resizePanel() {
        let available = item?.button?.window?.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size ?? CGSize(width:1280,height:800)
        let logical = MacMenuBarPanel.logicalSize(available: available), factor = MacInterfaceZoom.factor
        let size = MacApplicationRuntime.isPrototype ? NSSize(width:480,height:min(720,available.height-32)) : NSSize(width:logical.width*factor,height:logical.height*factor)
        if popover.contentSize != size {
            let window = popover.contentViewController?.view.window
            let wasKey = window?.isKeyWindow == true
            popover.contentSize = size
            if wasKey, popover.isShown { window?.makeKey() }
        }
    }
    func close() { if popover.isShown { popover.performClose(nil) } }
}
