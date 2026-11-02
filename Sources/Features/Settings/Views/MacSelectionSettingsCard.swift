import SwiftUI
import AppKit

struct MacSelectionSettingsCard: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @ObservedObject private var service = MacSelectionConversion.shared
    @ObservedObject private var permissions = MacPermissionCoordinator.shared
    @AppStorage("selection_conversion_enabled") private var enabled = true
    @AppStorage("v141_selection_shortcut") private var shortcutEnabled = true
    @AppStorage("v141_selection_auto") private var automatic = false
    @AppStorage("v141_hotkey") private var hotkeyData = Data()
    @State private var recording = false
    @State private var monitor: Any?
    var body: some View {
        MacSettingsCard(title: L10n.text("mac.selectionSettingsCard.body.03a46977ef"), icon: "text.cursor", subtitle: L10n.text("mac.selectionSettingsCard.body.33f2775e45")) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("mac.selectionSettingsCard.body.936753ccf1")).appFont(.body, weight: .medium)
                    HStack(spacing: 5) {
                        Circle().fill(permissions.selectionActive ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(permissions.selectionActive ? L10n.text("mac.selectionSettingsCard.body.5e99759bf7") : enabled ? L10n.text("mac.selectionSettingsCard.body.47a7e4edb4") : L10n.text("mac.selectionSettingsCard.body.6744b4c6a9")).appFont(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("selectionPermissionStatus")
                }
                Spacer()
                Toggle(L10n.text("mac.selectionSettingsCard.body.936753ccf1"), isOn: Binding(get: { permissions.selectionActive }, set: { permissions.setSelectionEnabled($0) })).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("selectionPermissionToggle")
            }
            Divider()
            HStack(spacing: 8) {
                Text(L10n.text("mac.selectionSettingsCard.body.0299dc0191")).appFont(.body)
                Spacer()
                Button(recording ? L10n.text("mac.selectionSettingsCard.body.2a86ea793b") : MacConversionHotkey.current.label) { beginRecording() }.accessibilityIdentifier("selectionShortcutRecorder").disabled(!enabled || !shortcutEnabled)
                Button { stopRecording(); hotkeyData = (try? JSONEncoder().encode(MacConversionHotkey())) ?? Data() } label: { Image(systemName: "arrow.counterclockwise") }.accessibilityLabel(L10n.text("mac.selectionSettingsCard.body.dcc045b9ae")).disabled(!enabled || !shortcutEnabled)
                Toggle(L10n.text("mac.selectionSettingsCard.body.c6a591a792"), isOn: $shortcutEnabled).labelsHidden().toggleStyle(.switch).disabled(!enabled)
            }
            MacSettingsToggleRow(title: L10n.text("mac.selectionSettingsCard.body.c22c4b6b22"), subtitle: L10n.text("mac.selectionSettingsCard.body.6eb7ffd104"), value: $automatic).disabled(!enabled)
            Text(enabled ? service.status : L10n.text("mac.selectionSettingsCard.body.7df05b5b4e")).appFont(.caption).foregroundStyle(.secondary)
            Text(L10n.text("mac.selectionSettingsCard.body.55b5a4f3d7")).appFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
