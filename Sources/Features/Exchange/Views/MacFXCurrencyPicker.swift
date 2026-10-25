import SwiftUI

/// Conversion selection is independent of the watched currency-pair list.
struct MacFXCurrencyPicker: View {
    @ObservedObject var service: MacFXMonitor
    var close: () -> Void
    @State private var search = ""
    @State private var selected: String?
    @State private var error: String?
    private var codes: [String] {
        var all = Set(Locale.commonISOCurrencyCodes + MacFXCatalog.codes)
        let typed = search.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        if (try? MacFXPair(base:typed,quote:typed)) != nil { all.insert(typed) }
        return all.sorted().filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) || name($0).localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("添加换算币种").appFont(.section,weight:.semibold)
            TextField("搜索代码或名称",text:$search).textFieldStyle(MacSettingsFieldStyle()).accessibilityIdentifier("fxCurrencySearch")
            ScrollView {
                LazyVStack(spacing:5) {
                    ForEach(codes,id:\.self) { code in
                        Button { selected = code } label: {
                            HStack(spacing:10) {
                                MacCurrencyFlag(code:code,width:24)
                                Text(code + " · " + name(code)).appFont(.body,weight:.medium)
                                Spacer()
                                if service.configuration.converterCurrencies.contains(code) { Text("已添加").appFont(.caption,weight:.regular).foregroundStyle(.secondary) }
                                else if selected == code { Image(systemName:"checkmark").foregroundStyle(MacUI.accent) }
                            }.padding(8).frame(maxWidth:.infinity,minHeight:40).contentShape(Rectangle())
                                .background(selected == code ? MacUI.accent.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:9))
                        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("fxChooseCurrency-" + code)
                    }
                }
            }.frame(height:220)
            if let error { Text(error).appFont(.caption,weight:.regular).foregroundStyle(.red) }
            HStack {
                Button("关闭",action:close).accessibilityIdentifier("fxCurrencyCancel")
                Spacer()
                Button("加入换算") {
                    guard let selected else { return }
                    do { try MacFXApplication.shared.addConverterCurrency(selected); close(); Task { await service.pageOpened() } }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(MacSettingsButtonStyle(primary:true,height:40)).disabled(selected == nil || service.configuration.converterCurrencies.contains(selected ?? "")).accessibilityIdentifier("fxConverterAddConfirm")
            }
        }.appFont(.body).padding(16).frame(width:340)
    }
    private func name(_ code:String) -> String {
        let known = MacSettingsVisual.currencyName(code)
        return known == code ? Locale(identifier:"zh_CN").localizedString(forCurrencyCode:code) ?? code : known
    }
}

struct MacFXLastUpdatedView: View {
    @ObservedObject var service: MacFXMonitor
    var body: some View {
        Text(service.quotes.map(\.retrievedAt).max().map { "上次更新 " + MacDisplayPreferences.time($0) } ?? "尚未更新")
            .appFont(.caption,weight:.regular).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            .accessibilityIdentifier("fxLastUpdated").appHelp(service.status)
    }
}
