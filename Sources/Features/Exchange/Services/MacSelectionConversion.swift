import SwiftUI
import AppKit
import ApplicationServices
import Carbon
import Combine

struct MacConversionHotkey: Codable, Equatable {
    var code: UInt32 = 8
    var modifiers: UInt32 = UInt32(controlKey | optionKey)
    var label = "⌃⌥C"
    static var current: Self { MacSettingsStore.load("v141_hotkey", fallback: Self()) }
    init() {}
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command,.control,.option,.shift])
        guard !flags.intersection([.command,.control,.option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.uppercased(), key.count == 1,
              event.keyCode != 53, !(flags == .command && ["Q","W","C","V","X","A","Z"].contains(key)) else { return nil }
        code = UInt32(event.keyCode); modifiers = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        label = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + key
    }
}

@MainActor
final class MacSelectionConversion: ObservableObject {
    static let shared = MacSelectionConversion()
    @Published private(set) var status = "选中金额后按快捷键换算"
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var mouseMonitor: Any?
    private var observer: AnyCancellable?
    private var selectionTask: Task<Void, Never>?
    private var window: MacSelectionFloatingPanel?
    private var session: MacSelectionSession?
    private var pointerMonitors: [Any] = []
    private var anchor = CGPoint.zero
    private var busy = false
    private var lastSelection = ""
    private var secureSelection = false
    private var signature = ""
    func start() {
        guard !MacPreferences.isTesting else { return }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard id.signature == 0x46544356 else { return OSStatus(eventNotHandledErr) }
                Task { @MainActor in await MacSelectionConversion.shared.convertSelection(automatic: false) }
                return noErr
            }, 1, &type, nil, &handler)
        }
        if observer == nil {
            observer = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).debounce(for: .milliseconds(200), scheduler: RunLoop.main).sink { [weak self] _ in Task { @MainActor in self?.configure() } }
        }
        configure()
    }
    func configure() {
        let d = MacPreferences.defaults, key = MacConversionHotkey.current
        let master = d.object(forKey: "selection_conversion_enabled") as? Bool ?? true
        let enabled = master && (d.object(forKey: "v141_selection_shortcut") as? Bool ?? true)
        let automatic = master && d.bool(forKey: "v141_selection_auto")
        if MacPreferences.isTesting { status = "隔离测试：不注册全局快捷键"; if !master { dismiss() }; return }
        let next = "\(master):\(enabled):\(automatic):\(key.code):\(key.modifiers)"
        guard next != signature else { return }; signature = next
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        if enabled {
            let result = RegisterEventHotKey(key.code, key.modifiers, EventHotKeyID(signature: 0x46544356, id: 1), GetApplicationEventTarget(), 0, &hotkey)
            status = result == noErr ? "选中金额后按 \(key.label) 换算" : "快捷键已被占用，请重新设置"
        } else { status = "快捷键换算已关闭" }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
        selectionTask?.cancel()
        if !master { dismiss() }
        if automatic {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                Task { @MainActor in
                    self?.selectionTask?.cancel()
                    self?.selectionTask = Task { [weak self] in
                        do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                        guard !Task.isCancelled else { return }
                        await self?.convertSelection(automatic: true)
                    }
                }
            }
        }
    }
    func dismiss(clearSelection: Bool = true) {
        session?.cancel(); session = nil
        for monitor in pointerMonitors { NSEvent.removeMonitor(monitor) }; pointerMonitors = []
        window?.close(); window = nil; if clearSelection { lastSelection = "" }
    }
    #if FINTRACK_LOCAL_VALIDATION
    func presentFixture(_ text: String) {
        guard MacPreferences.isTesting, let parsed = MacSelectedAmountParser.parse(text) else { return }
        present(parsed)
    }
    #endif
    func requestAccessibility() {
        guard !MacPreferences.isTesting else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { status = "请在系统设置 → 隐私与安全性 → 辅助功能中允许 FinTrack。" }
    }
    private func readSelection() -> String? {
        secureSelection = false
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var role: CFTypeRef?, subrole: CFTypeRef?, text: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if subrole as? String == kAXSecureTextFieldSubrole { secureSelection = true; return nil }
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &text) == .success else { return nil }
        return (text as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func copyFallback() async -> String? {
        let board = NSPasteboard.general
        let snapshot = board.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } } ?? []
        let before = board.changeCount
        guard let source = CGEventSource(stateID: .combinedSessionState), let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true), let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return nil }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(60))
            if board.changeCount != before {
                let count = board.changeCount, text = board.string(forType: .string)
                // Restore only the change we observed, never clobber a later copy.
                if board.changeCount == count {
                    board.clearContents()
                    let items = snapshot.map { values -> NSPasteboardItem in let item = NSPasteboardItem(); for (type,data) in values { item.setData(data, forType:type) }; return item }
                    board.writeObjects(items)
                }
                return text
            }
        }
        return nil
    }
    func convertSelection(automatic: Bool) async {
        guard !busy, MacPreferences.defaults.object(forKey: "selection_conversion_enabled") as? Bool != false else { return }
        guard AXIsProcessTrusted() else {
            if !automatic { status = "需要辅助功能权限才能读取选中金额。"; requestAccessibility() }
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        busy = true; defer { busy = false }
        var text = readSelection()
        guard !secureSelection else { return }
        if !automatic && (text?.isEmpty ?? true) { text = await copyFallback() }
        guard let text, !text.isEmpty, let parsed = MacSelectedAmountParser.parse(text) else {
            if automatic { dismiss() }
            if !automatic { showMessage("未识别到金额", "请选择一个金额，例如 1234 USD、€299 或 599.99 土耳其里拉。") }
            return
        }
        let signature = "\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0):\(text)"
        if automatic && signature == lastSelection { return }
        lastSelection = signature
        present(parsed)
    }
    private func showMessage(_ title: String, _ message: String) { status = title + "：" + message }
    private func present(_ parsed: MacSelectedAmountParser.Parsed) {
        dismiss(clearSelection: false)
        anchor = NSEvent.mouseLocation
        let board = MacPreferences.isTesting ? NSPasteboard(name: NSPasteboard.Name("dev.agumuzi.fintrack.tests.selection")) : NSPasteboard.general
        let clipboardVersion = board.changeCount
        let value = MacSelectionSession(parsed: parsed, target: MacPreferences.defaults.string(forKey: "base_currency") ?? "USD", monitor: MacFXApplication.shared.monitor) { text in
            guard board.changeCount == clipboardVersion else { return false }
            board.clearContents(); return board.setString(text, forType: .string)
        }
        session = value
        let panel = MacSelectionFloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "选区金额换算"; panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true; panel.acceptsMouseMovedEvents = true
        panel.onEscape = { [weak self] in self?.dismiss() }
        let background = MacSelectionPopoverBackground(); background.onExit = { [weak self] in self?.pointerEvent(.mouseMoved) }; background.material = .popover; background.state = .active; background.blendingMode = .behindWindow
        background.wantsLayer = true; background.layer?.cornerRadius = 16; background.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: MacSelectionPopoverView(session: value, dismiss: { [weak self] in self?.dismiss() }).defaultAppStorage(MacPreferences.defaults).interfaceZoom())
        hosting.translatesAutoresizingMaskIntoConstraints = false; background.addSubview(hosting)
        NSLayoutConstraint.activate([hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor), hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor), hosting.topAnchor.constraint(equalTo: background.topAnchor), hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor)])
        panel.contentView = background; window = panel
        value.phaseChanged = { [weak self, weak value] in guard let self, let value, self.session === value else { return }; self.anchor = NSEvent.mouseLocation; self.layout(value) }
        value.begin(); layout(value); panel.orderFrontRegardless()
        if panel.acceptsKeyboard { panel.makeKeyAndOrderFront(nil) }
        let types: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in Task { @MainActor in self?.pointerEvent(event.type) } } { pointerMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: types) { [weak self] event in if event.type == .keyDown && event.keyCode == 53 { self?.dismiss(); return nil }; self?.pointerEvent(event.type); return event } { pointerMonitors.append(monitor) }
    }
    private func layout(_ value: MacSelectionSession) {
        guard let panel = window else { return }
        let size: CGSize
        switch value.phase {
        case .choose: size = CGSize(width: 460, height: CGFloat(value.parsed.amounts.count > 1 ? 270 : 230) + min(86, CGFloat(max(0, (value.suggested.count + 5) / 6 - 1)) * 34)); panel.acceptsKeyboard = true
        case .result: size = CGSize(width: 390, height: 132); panel.acceptsKeyboard = false
        case .loading, .failure: size = CGSize(width: 360, height: 112); panel.acceptsKeyboard = false
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main else { return }
        let scaled = CGSize(width: size.width * MacInterfaceZoom.factor, height: size.height * MacInterfaceZoom.factor)
        panel.setFrame(MacSelectionPopoverGeometry.frame(size: scaled, pointer: anchor, visible: screen.visibleFrame), display: true)
    }
    private func pointerEvent(_ type: NSEvent.EventType) {
        guard let window else { return }
        if type == .keyDown { return }
        if !window.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) { dismiss() }
    }
}
