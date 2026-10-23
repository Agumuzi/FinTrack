import SwiftUI

struct MacIconLibraryChooser: View {
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
        return values.filter { search.isEmpty || $0.1.localizedCaseInsensitiveContains(search) || $0.0.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        MacFormShell(width: 650) {
            Text("选择" + title + "图标").appFont(.dialogTitle, weight: .semibold)
        } fields: {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(["全部"] + MacPresentationOptions.groups.map { $0.0 }, id: \.self) { name in
                            Button { group = name } label: {
                                Text(name).appFont(.body, weight: .medium).padding(.horizontal, 14).frame(minHeight: 40)
                                    .foregroundStyle(group == name ? MacUI.accent : .primary)
                                    .background(group == name ? MacUI.accent.opacity(0.12) : .gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier(identifierPrefix + "Group-" + name).accessibilityValue(group == name ? "已选择" : "未选择")
                        }
                    }
                }
                TextField("搜索图标", text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier(identifierPrefix + "Search")
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 62, maximum: 78), spacing: 10)], spacing: 12) {
                        ForEach(choices, id: \.0) { symbol, name in
                            Button { draft = symbol } label: {
                                VStack(spacing: 5) {
                                    MacSettingsIcon(symbol: symbol, color: MacAccent.color(color), size: 42)
                                    Text(name).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth: .infinity).padding(5)
                                    .background(draft == symbol ? MacUI.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(draft == symbol ? MacUI.accent : .clear, lineWidth: 1.5)).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(name).accessibilityLabel(title + "图标：" + name)
                                .accessibilityIdentifier(identifierPrefix + "-" + symbol).accessibilityValue(draft == symbol ? "已选择" : "未选择")
                        }
                    }.padding(2)
                }.frame(height: 260)
                if choices.isEmpty { Text("没有匹配的图标").foregroundStyle(.secondary) }
            }
        } footer: {
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("使用图标") { icon = draft; dismiss() }.keyboardShortcut(.defaultAction).accessibilityIdentifier(identifierPrefix + "Confirm") }
        }.onAppear { draft = icon }
    }
}

struct MacColorLibraryChooser: View {
    @Binding var selection: String
    var identifierPrefix: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft = "blue"
    @State private var custom = ""
    var body: some View {
        MacFormShell(width: 500) {
            Text("选择颜色").appFont(.dialogTitle, weight: .semibold)
        } fields: {
            VStack(alignment: .leading, spacing: 18) {
                Capsule().fill(MacAccent.color(draft)).frame(height: 32)
                MacColorSwatches(selection: $draft, identifierPrefix: identifierPrefix)
                Divider()
                Text("自定义颜色").appFont(.body, weight: .medium)
                HStack {
                    TextField("#RRGGBB", text: $custom).textFieldStyle(.roundedBorder).accessibilityIdentifier(identifierPrefix + "Hex")
                    Button("应用") { if MacPresentationOptions.validColor(custom) { draft = custom.uppercased() } }.disabled(custom.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) == nil)
                }
                Text("预设颜色或自定义颜色均可保存，已有颜色保持原值。").appFont(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("使用颜色") { selection = draft; dismiss() }.keyboardShortcut(.defaultAction).accessibilityIdentifier(identifierPrefix + "Confirm") }
        }.onAppear { draft = selection; custom = selection.hasPrefix("#") ? selection : MacAccent.hex(MacAccent.color(selection)) }
    }
}
