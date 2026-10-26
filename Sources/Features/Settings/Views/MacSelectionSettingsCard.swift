import SwiftUI
import AppKit

struct MacSelectionSettingsCard: View {
    @ObservedObject private var service = MacSelectionConversion.shared
    @ObservedObject private var permissions = MacPermissionCoordinator.shared
    @AppStorage("selection_conversion_enabled") private var enabled = true
    @AppStorage("v141_selection_shortcut") private var shortcutEnabled = true
    @AppStorage("v141_selection_auto") private var automatic = false
    @AppStorage("v141_hotkey") private var hotkeyData = Data()
    @State private var recording = false
    @State private var monitor: Any?
    var body: some View {
        MacSettingsCard(title: "选区金额换算", icon: "text.cursor", subtitle: "在其他应用选中金额，换算为账本本位币。") {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("启用选区换算").appFont(.body, weight: .medium)
                    HStack(spacing: 5) {
                        Circle().fill(permissions.selectionActive ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(permissions.selectionActive ? "辅助功能已授权" : enabled ? "需要辅助功能授权" : "已关闭").appFont(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("selectionPermissionStatus")
                }
                Spacer()
                Toggle("启用选区换算", isOn: Binding(get: { permissions.selectionActive }, set: { permissions.setSelectionEnabled($0) })).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("selectionPermissionToggle")
            }
            Divider()
            HStack(spacing: 8) {
                Text("全局快捷键").appFont(.body)
                Spacer()
                Button(recording ? "请按快捷键…" : MacConversionHotkey.current.label) { beginRecording() }.accessibilityIdentifier("selectionShortcutRecorder").disabled(!enabled || !shortcutEnabled)
                Button { stopRecording(); hotkeyData = (try? JSONEncoder().encode(MacConversionHotkey())) ?? Data() } label: { Image(systemName: "arrow.counterclockwise") }.accessibilityLabel("恢复默认快捷键").disabled(!enabled || !shortcutEnabled)
                Toggle("启用全局快捷键", isOn: $shortcutEnabled).labelsHidden().toggleStyle(.switch).disabled(!enabled)
            }
            MacSettingsToggleRow(title: "划取金额后自动显示", subtitle: "换算成功自动复制；鼠标移出浮层后关闭。", value: $automatic).disabled(!enabled)
            Text(enabled ? service.status : "选区金额换算已关闭").appFont(.caption).foregroundStyle(.secondary)
            Text("开启时前往辅助功能授权。关闭仅停用本应用读取，保留系统授权；快捷键读取失败时可尝试复制读取，再自动复制换算结果。").appFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.onDisappear { stopRecording() }.task { await permissions.refresh() }
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
