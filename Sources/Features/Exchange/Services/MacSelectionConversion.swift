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
    private var window: NSPanel?
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
        let enabled = d.object(forKey: "v141_selection_shortcut") as? Bool ?? true
        let automatic = d.bool(forKey: "v141_selection_auto")
        let next = "\(enabled):\(automatic):\(key.code):\(key.modifiers)"
        guard next != signature else { return }; signature = next
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        if enabled {
            let result = RegisterEventHotKey(key.code, key.modifiers, EventHotKeyID(signature: 0x46544356, id: 1), GetApplicationEventTarget(), 0, &hotkey)
            status = result == noErr ? "选中金额后按 \(key.label) 换算" : "快捷键已被占用，请重新设置"
        } else { status = "快捷键换算已关闭" }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
        selectionTask?.cancel()
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
    func dismiss() { window?.close() }
    #if FINTRACK_LOCAL_VALIDATION
    func presentFixture(_ text: String) {
        guard MacPreferences.isTesting, let parsed = MacSelectedAmountParser.parse(text) else { return }
        present(MacSelectionPrompt(parsed:parsed,automatic:false),activate:true)
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
        guard !busy else { return }
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
            if automatic { lastSelection = ""; window?.close() }
            if !automatic { showMessage("未识别到金额", "请选择一个金额，例如 1234 USD、€299 或 599.99 土耳其里拉。") }
            return
        }
        let signature = "\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0):\(text)"
        if automatic && signature == lastSelection { return }
        lastSelection = signature
        if automatic {
            present(MacSelectionPrompt(parsed: parsed, automatic: true), activate: false)
        } else { present(MacSelectionPrompt(parsed: parsed, automatic: false), activate: true) }
    }
    private func showMessage(_ title: String, _ message: String) {
        present(VStack(alignment: .leading, spacing: 14) { Text(title).font(.headline); Text(message); Button("关闭") { self.window?.close() } }.padding(24), activate: true)
    }
    private func present<V: View>(_ view: V, activate: Bool) {
        window?.close()
        let panel = NSPanel(contentRect: NSRect(x:0,y:0,width:440,height:320), styleMask: [.titled,.closable,.utilityWindow,.nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "选区金额换算"; panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace,.fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: view.defaultAppStorage(MacPreferences.defaults))
        panel.center(); panel.orderFrontRegardless(); window = panel
        if activate { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
}

private struct MacSelectionPrompt: View {
    let parsed: MacSelectedAmountParser.Parsed
    let automatic: Bool
    @State private var amountIndex = 0
    @State private var source = ""
    @State private var result = ""
    @State private var details = ""
    @State private var working = false
    init(parsed: MacSelectedAmountParser.Parsed, automatic: Bool) {
        self.parsed = parsed; self.automatic = automatic
        let choices = parsed.currencies.isEmpty ? Array(Set(MacFXCatalog.codes + ["USD","EUR","CNY","RUB","TRY","JPY","GBP"])).sorted() : parsed.currencies
        _source = State(initialValue: choices.first ?? "USD")
    }
    private var target: String { MacPreferences.defaults.string(forKey: "base_currency") ?? "USD" }
    private var options: [String] { parsed.currencies.isEmpty ? Array(Set(MacFXCatalog.codes + ["USD","EUR","CNY","RUB","TRY","JPY","GBP"])).sorted() : parsed.currencies }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("换算为 \(target)").font(.headline)
            if parsed.amounts.count > 1 { Picker("金额解释", selection: $amountIndex) { ForEach(parsed.amounts.indices, id:\.self) { Text(NSDecimalNumber(decimal: parsed.amounts[$0]).stringValue).tag($0) } }.disabled(working) }
            Picker(parsed.currencies.isEmpty ? "选择原币" : "原币", selection: $source) { ForEach(options,id:\.self) { Text($0).tag($0) } }.disabled(working)
            Text(NSDecimalNumber(decimal: parsed.amounts[amountIndex]).stringValue + " " + source).textSelection(.enabled)
            if !result.isEmpty { Text(result).font(.title2).textSelection(.enabled).accessibilityIdentifier("selectionConversionResult") }
            Text(details).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                Button("关闭") { MacSelectionConversion.shared.dismiss() }.keyboardShortcut(.cancelAction)
                Button(working ? "换算中…" : "换算") { Task { await convert() } }.disabled(working || source.isEmpty)
                Spacer()
                Button("复制结果") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result,forType:.string) }.disabled(result.isEmpty || working)
            }
        }.padding(24).frame(width:440)
        .task { if parsed.currencies.count == 1 && parsed.amounts.count == 1 { await convert() } }
        .onChange(of: source) { _, _ in result = ""; details = "" }
        .onChange(of: amountIndex) { _, _ in result = ""; details = "" }
    }
    private func convert() async {
        working = true; defer { working = false }
        guard let pair = try? MacFXPair(base:source,quote:target) else { return }
        let monitor = MacFXApplication.shared.monitor
        if source != target { await monitor.refresh(reason:.manual,extraPairs:[pair]) }
        guard let route = MacFXMath.resolve(from:source,to:target,quotes:monitor.quotes) else { details = "没有可用汇率，请稍后重试或检查数据源。"; result = ""; return }
        let value = NSDecimalNumber(decimal:parsed.amounts[amountIndex]).multiplying(by:NSDecimalNumber(value:route.unitRate))
        guard value != .notANumber, value.doubleValue.isFinite else { details = "金额超出范围"; return }
        result = MacFXMath.formatted(value.doubleValue,digits:2,grouping:true) + " " + target
        details = route.legs.isEmpty ? "同币种 · 1:1" : route.legs.map { MacFXApplication.shared.sourceLabel($0.sourceID) + " · " + MacFXDates.label($0.quoteTime) }.joined(separator:"\n")
    }
}
