import SwiftUI
import AppKit

struct MacSelectionSettingsCard: View {
    @ObservedObject private var service = MacSelectionConversion.shared
    @AppStorage("v141_selection_shortcut") private var shortcutEnabled = true
    @AppStorage("v141_selection_auto") private var automatic = false
    @AppStorage("v141_hotkey") private var hotkeyData = Data()
    @State private var recording = false
    @State private var monitor: Any?
    var body: some View {
        MacSettingsCard(title: "选区金额换算", icon: "text.cursor", subtitle: "在其他应用选中金额，换算为账本本位币。") {
            MacSettingsToggleRow(title: "启用全局快捷键", value: $shortcutEnabled)
            HStack {
                Text("换算快捷键"); Spacer()
                Button(recording ? "请按下新快捷键…" : MacConversionHotkey.current.label) { beginRecording() }
                    .accessibilityIdentifier("selectionShortcutRecorder")
                Button("默认") { stopRecording(); hotkeyData = (try? JSONEncoder().encode(MacConversionHotkey())) ?? Data() }
            }
            MacSettingsToggleRow(title: "划取金额后自动显示", subtitle: "松开鼠标后显示结果；不会自动复制或抢走焦点。", value: $automatic)
            Text(service.status).appFont(.caption).foregroundStyle(.secondary)
            Button("允许读取选中文本…") { service.requestAccessibility() }.accessibilityIdentifier("selectionAccessibility")
            Text("需要辅助功能权限。部分应用无法读取选区；快捷键可尝试复制读取并恢复剪贴板。自动模式只读取可用选区。").appFont(.caption).foregroundStyle(.secondary)
        }.onDisappear { stopRecording() }
    }
    private func beginRecording() {
        stopRecording(); recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil }
            if let key = MacConversionHotkey(event:event), let data = try? JSONEncoder().encode(key) {
                hotkeyData = data; stopRecording()
            }
            return nil
        }
    }
    private func stopRecording() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }; recording = false }
}
