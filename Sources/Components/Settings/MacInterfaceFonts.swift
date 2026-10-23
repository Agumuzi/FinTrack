import SwiftUI
import AppKit
import CoreText

enum MacInterfaceFonts {
    static let preferenceKey = "v13_interface_font"
    static var selectedName: String { MacPreferences.defaults.string(forKey: preferenceKey) ?? "" }
    static var displayName: String { selectedName.isEmpty ? "系统字体" : NSFont(name: selectedName, size: 16)?.displayName ?? selectedName }
    static var unavailable: Bool { !selectedName.isEmpty && NSFont(name: selectedName, size: 16) == nil }
    static func controlHeight(_ minimum: CGFloat = 40) -> CGFloat {
        let face = font(size: MacUI.fontTier.bodySize)
        return max(minimum, ceil(face.ascender - face.descender + face.leading) + 16)
    }
    static func font(size: CGFloat, weight: NSFont.Weight = .regular, monospacedDigits: Bool = false) -> NSFont {
        guard !selectedName.isEmpty, let chosen = NSFont(name: selectedName, size: size) else {
            return monospacedDigits ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        }
        var descriptor = chosen.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]])
        if monospacedDigits {
            descriptor = descriptor.addingAttributes([.featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType, NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
        }
        return NSFont(descriptor: descriptor, size: size) ?? chosen
    }
}

@MainActor
final class MacInterfaceFontPanel: NSObject, NSFontChanging {
    static let shared = MacInterfaceFontPanel()
    func open() {
        let manager = NSFontManager.shared
        manager.target = self; manager.action = #selector(changeFont(_:))
        manager.setSelectedFont(MacInterfaceFonts.font(size: MacUI.fontTier.bodySize), isMultiple: false)
        guard let panel = manager.fontPanel(true) else { return }
        panel.worksWhenModal = true
        panel.title = "显示字体"
        if !panel.isVisible { panel.center() }
        manager.orderFrontFontPanel(nil)
        panel.makeKeyAndOrderFront(nil)
    }
    @objc func changeFont(_ sender: NSFontManager?) {
        guard let sender else { return }
        let selected = sender.convert(MacInterfaceFonts.font(size: MacUI.fontTier.bodySize))
        MacPreferences.defaults.set(selected.fontName, forKey: MacInterfaceFonts.preferenceKey)
    }
    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask { [.face, .collection] }
}

struct MacInterfaceFontSettings: View {
    @AppStorage(MacInterfaceFonts.preferenceKey, store: MacPreferences.defaults) private var selectedName = ""
    @State private var error: String?
    var body: some View {
        MacSettingsCard(title: "显示字体", icon: "textformat", subtitle: "从 macOS 字体库选择，字号由下方三档设置统一控制。", headerColor: .blue) {
            HStack(spacing: 12) {
                Text(MacInterfaceFonts.displayName).appFont(.body, weight: .medium).lineLimit(1).truncationMode(.middle).accessibilityIdentifier("interfaceFontName")
                Spacer(minLength: 12)
                Button("选择字体…") { MacInterfaceFontPanel.shared.open() }.accessibilityIdentifier("chooseInterfaceFont")
            }
            Text("中文预览 · FinTrack · 1,234,567.89").appFont(.section).monospacedDigit().accessibilityIdentifier("interfaceFontPreview")
            if MacInterfaceFonts.unavailable { Text("当前字体未安装，暂时使用系统字体。").appFont(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("打开字体册") {
                    if !NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Font Book.app")) { error = "无法打开字体册，请从应用程序中打开。" }
                }.accessibilityIdentifier("openFontBook")
                Spacer()
                Button("恢复系统字体") { selectedName = ""; NSFontManager.shared.setSelectedFont(.systemFont(ofSize: MacUI.fontTier.bodySize), isMultiple: false) }.disabled(selectedName.isEmpty).accessibilityIdentifier("resetInterfaceFont")
            }
            if let error { Text(error).appFont(.caption).foregroundStyle(.secondary) }
        }
    }
}
