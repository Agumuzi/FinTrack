import SwiftUI

struct MacIconLibraryChooser: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @Binding var icon: String
    var color: String
    var title: String
    var identifierPrefix: String
    @Environment(\.dismiss) private var dismiss
    @State private var group = "全部"
    @State private var search = ""
    @State private var draft = "target"
    private var choices: [(String, String)] {
        let values = group == "全部" ? MacPresentationOptions.icons : MacPresentationOptions.groups.first { $0.0 == group }?.1 ?? []
        return values.filter { search.isEmpty || $0.1.localizedCaseInsensitiveContains(search) || L10n.builtIn($0.1).localizedCaseInsensitiveContains(search) || $0.0.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        MacFormShell(width: 650) {
            Text(L10n.text("mac.presentationPickerDialogs.MacFormShell.c11330b852") + title + L10n.text("mac.presentationPickerDialogs.MacFormShell.0d720eeea2")).appFont(.dialogTitle, weight: .semibold)
        } fields: {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(["全部"] + MacPresentationOptions.groups.map { $0.0 }, id: \.self) { name in
                            Button { group = name } label: {
                                Text(L10n.builtIn(name)).appFont(.body, weight: .medium).padding(.horizontal, 14).frame(minHeight: 40)
                                    .foregroundStyle(group == name ? MacUI.accent : .primary)
                                    .background(group == name ? MacUI.accent.opacity(0.12) : .gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                            }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier(identifierPrefix + "Group-" + name).accessibilityValue(group == name ? L10n.text("mac.presentationPickerDialogs.ForEach.3f4ebc4aad") : L10n.text("mac.presentationPickerDialogs.ForEach.1182c5454f"))
                        }
                    }
                }
                TextField(L10n.text("mac.presentationPickerDialogs.MacFormShell.ebb240a193"), text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier(identifierPrefix + "Search")
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 62, maximum: 78), spacing: 10)], spacing: 12) {
                        ForEach(choices, id: \.0) { symbol, name in
                            Button { draft = symbol } label: {
                                VStack(spacing: 5) {
                                    MacSettingsIcon(symbol: symbol, color: MacAccent.color(color), size: 42)
                                    Text(L10n.builtIn(name)).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth: .infinity).padding(5)
                                    .background(draft == symbol ? MacUI.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(draft == symbol ? MacUI.accent : .clear, lineWidth: 1.5)).contentShape(Rectangle())
                            }.buttonStyle(MacInteractiveButtonStyle()).appHelp(L10n.builtIn(name)).accessibilityLabel(title + L10n.text("mac.presentationPickerDialogs.ForEach.a8dd300dd9") + name)
                                .accessibilityIdentifier(identifierPrefix + "-" + symbol).accessibilityValue(draft == symbol ? L10n.text("mac.presentationPickerDialogs.ForEach.3f4ebc4aad") : L10n.text("mac.presentationPickerDialogs.ForEach.1182c5454f"))
                        }
                    }.padding(2)
                }.frame(height: 260)
                if choices.isEmpty { Text(L10n.text("mac.presentationPickerDialogs.MacFormShell.90f8bfdf63")).foregroundStyle(.secondary) }
            }
        } footer: {
            HStack { Button(L10n.text("mac.presentationPickerDialogs.MacFormShell.2cd0f3be87")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(L10n.text("mac.presentationPickerDialogs.MacFormShell.feb3ae0738")) { icon = draft; dismiss() }.keyboardShortcut(.defaultAction).accessibilityIdentifier(identifierPrefix + "Confirm") }
        }.onAppear { draft = icon }
    }
}

struct MacColorLibraryChooser: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @Binding var selection: String
    var identifierPrefix: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft = "blue"
    @State private var custom = ""
    var body: some View {
        MacFormShell(width: 500) {
            Text(L10n.text("mac.presentationPickerDialogs.MacFormShell.369b82fa07")).appFont(.dialogTitle, weight: .semibold)
        } fields: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Circle().fill(MacAccent.color(draft)).frame(width: 42, height: 42)
                    Text(draft.hasPrefix("#") ? draft.uppercased() : MacAccent.hex(MacAccent.color(draft))).appFont(.body, weight: .semibold)
                    Spacer()
                }
                MacColorSwatches(selection: $draft, identifierPrefix: identifierPrefix)
                Divider()
                Text(L10n.text("mac.presentationPickerDialogs.MacFormShell.781b07fdcb")).appFont(.body, weight: .medium)
                HStack {
                    TextField("#RRGGBB", text: $custom).textFieldStyle(.roundedBorder).accessibilityIdentifier(identifierPrefix + "Hex")
                    Button(L10n.text("mac.presentationPickerDialogs.MacFormShell.63c73c4730")) { if MacPresentationOptions.validColor(custom) { draft = custom.uppercased() } }.disabled(custom.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) == nil)
                }
            }
        } footer: {
            HStack { Button(L10n.text("mac.presentationPickerDialogs.MacFormShell.2cd0f3be87")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(L10n.text("mac.presentationPickerDialogs.MacFormShell.cc425641d1")) { selection = draft; dismiss() }.keyboardShortcut(.defaultAction).accessibilityIdentifier(identifierPrefix + "Confirm") }
        }.onAppear { draft = selection; custom = selection.hasPrefix("#") ? selection : MacAccent.hex(MacAccent.color(selection)) }
    }
}
