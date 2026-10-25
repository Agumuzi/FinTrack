import SwiftUI
import UniformTypeIdentifiers

nonisolated enum MacFXListOrder {
    static func moving<T:Equatable>(_ values:[T],item:T,to target:T?) -> [T] {
        guard let from = values.firstIndex(of:item) else { return values }
        if let target {
            guard let to = values.firstIndex(of:target), from != to else { return values }
            var result = values; let value = result.remove(at:from)
            result.insert(value,at:min(to,result.count)); return result
        }
        var result = values; result.append(result.remove(at:from)); return result
    }
}

private enum MacFXSettingsDrag {
    static let pair = "pair"
    static let currency = "currency"
    static func payload(_ id:String,type:String,token:String) -> String { "fintrack.fx." + type + "|" + token + "|" + id }
    static func provider(_ id:String,type:String,token:String) -> NSItemProvider {
        NSItemProvider(object:payload(id,type:type,token:token) as NSString)
    }
}

private struct MacFXSettingsDrop: DropDelegate {
    let type: String
    let token: String
    let target: String?
    @Binding var dragged: String?
    var move: (String,String?) -> Void
    func validateDrop(info:DropInfo) -> Bool { dragged != nil && info.hasItemsConforming(to:[UTType.text]) }
    func dropUpdated(info:DropInfo) -> DropProposal? { validateDrop(info:info) ? DropProposal(operation:.move) : nil }
    func performDrop(info:DropInfo) -> Bool {
        guard validateDrop(info:info), let id = dragged, let provider = info.itemProviders(for:[UTType.text]).first else { return false }
        let expected = MacFXSettingsDrag.payload(id,type:type,token:token)
        _ = provider.loadObject(ofClass:NSString.self) { object,_ in
            DispatchQueue.main.async {
                guard dragged == id else { return }
                if object as? String == expected { move(id,target) }
                dragged = nil
            }
        }
        return true
    }
}

private enum MacFXSettingsCurrencySearch {
    static func name(_ code:String,language:String = "zh_CN") -> String {
        Locale(identifier:language).localizedString(forCurrencyCode:code) ?? code
    }
    static func codes(_ query:String) -> [String] {
        guard !query.isEmpty else { return MacFXCatalog.codes }
        return Set(MacFXCatalog.codes + Locale.commonISOCurrencyCodes).sorted().filter {
            $0.localizedCaseInsensitiveContains(query) || name($0).localizedCaseInsensitiveContains(query) || name($0,language:"en").localizedCaseInsensitiveContains(query)
        }
    }
}

struct MacFXPairAddForm: View {
    var onAdded: (MacFXPair) -> Void = { _ in }
    @ObservedObject private var service = MacFXApplication.shared.monitor
    @State private var base = "USD"
    @State private var quote = "CNY"
    @State private var customBase = false
    @State private var customQuote = false
    @State private var search = ""
    @State private var error: String?
    private var pair: MacFXPair? { try? MacFXPair(base:base,quote:quote) }
    private var duplicate: Bool { pair.map { service.configuration.watchedPairs.contains($0) } ?? false }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            TextField("搜索代码、中文名或英文名",text:$search).textFieldStyle(MacSettingsFieldStyle()).accessibilityIdentifier("fxPairSearch")
            HStack { Text("原币"); Spacer(minLength:8); MacEditableCurrencyMenu(currency:$base,custom:$customBase,codes:MacFXSettingsCurrencySearch.codes(search),identifier:"fxPairBase",textIdentifier:"fxPairBaseCustom") }
            HStack { Text("目标币"); Spacer(minLength:8); MacEditableCurrencyMenu(currency:$quote,custom:$customQuote,codes:MacFXSettingsCurrencySearch.codes(search),identifier:"fxPairQuote",textIdentifier:"fxPairQuoteCustom") }
            HStack {
                Button("加入汇率列表") { add() }.buttonStyle(MacSettingsButtonStyle(primary:true,height:40))
                    .disabled(pair == nil || pair?.base == pair?.quote || duplicate).accessibilityIdentifier("fxPairConfirm")
                Spacer(minLength:0)
                Button { swap(&base,&quote); swap(&customBase,&customQuote) } label: { Image(systemName:"arrow.left.arrow.right").frame(width:36,height:36) }
                    .buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel("交换货币").accessibilityIdentifier("fxPairSwap")
            }
            if duplicate { Text("这个汇率已经存在").appFont(.caption).foregroundStyle(.secondary) }
            else if pair == nil { Text("请输入三位英文字母货币代码").appFont(.caption).foregroundStyle(.secondary) }
            else if pair?.base == pair?.quote { Text("请选择不同的原币和目标币").appFont(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).appFont(.caption).foregroundStyle(.red) }
        }.appFont(.body).onAppear {
            if !MacFXCatalog.codes.contains(base) { base = MacFXCatalog.codes.first ?? "USD" }
            if !MacFXCatalog.codes.contains(quote) || quote == base { quote = MacFXCatalog.codes.first { $0 != base } ?? base }
        }
    }
    private func add() {
        guard let pair, pair.base != pair.quote else { return }
        do {
            try MacFXApplication.shared.addWatchedPair(base:pair.base,quote:pair.quote)
            base = pair.base; quote = pair.quote; customBase = false; customQuote = false; error = nil
            onAdded(pair); Task { await service.pageOpened() }
        } catch { self.error = "未能添加汇率，请检查货币代码" }
    }
}

struct MacFXDisplaySettings: View {
    @ObservedObject private var service = MacFXApplication.shared.monitor
    var availableHeight: CGFloat = 600
    @State private var addingPair = false
    @State private var addingCurrency = false
    @State private var draggedPair: String?
    @State private var draggedCurrency: String?
    @State private var dragToken = UUID().uuidString
    @State private var availableWidth: CGFloat = 0
    private var app: MacFXApplication { .shared }
    private var listHeight: CGFloat { availableWidth >= 740 ? max(250,min(520,availableHeight-150)) : 340 }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            let layout = availableWidth >= 740 ? AnyLayout(HStackLayout(alignment:.top,spacing:16)) : AnyLayout(VStackLayout(spacing:16))
            VStack(spacing:0) { layout { pairsCard; converterCard } }.frame(maxWidth:.infinity)
                .accessibilityElement(children:.contain).accessibilityIdentifier("fxDisplayLists")
                .onGeometryChange(for:CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            Text("拖动左侧把手或使用上下箭头排序，顺序会同步到菜单栏。").appFont(.caption).foregroundStyle(.secondary)
        }
    }
    private var pairsCard: some View {
        MacSettingsCard(title:"汇率列表",icon:"chart.xyaxis.line",subtitle:"关注的货币对",action:AnyView(HStack(spacing:10) { count(service.configuration.watchedPairs.count); Button("添加",systemImage:"plus") { addingPair = true }.accessibilityIdentifier("fxSettingsAddPair").popover(isPresented:$addingPair) { MacFXPairPicker { _ in addingPair = false } } })) {
            ScrollView { VStack(spacing:6) {
                if service.configuration.watchedPairs.isEmpty { empty("尚未关注货币对") }
                ForEach(service.configuration.watchedPairs,id:\.key) { pair in
                    HStack(spacing:8) {
                        handle("fxSettingsPairDrag-" + pair.key) .onDrag { draggedPair = pair.key; draggedCurrency = nil; return MacFXSettingsDrag.provider(pair.key,type:MacFXSettingsDrag.pair,token:dragToken) }
                        VStack(alignment:.leading,spacing:4) {
                            Text(MacFXSettingsCurrencySearch.name(pair.base) + " / " + MacFXSettingsCurrencySearch.name(pair.quote)).appFont(.body,weight:.medium).lineLimit(2)
                            Text("\(service.configuration.displayUnits) " + pair.base + " → " + pair.quote).appFont(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        orderControls(pair.key,ids:service.configuration.watchedPairs.map(\.key),prefix:"fxPairOrder") { delta in stepPair(pair,delta) }
                        Button("移除") { app.update { $0.watchedPairs.removeAll { $0 == pair } } }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("fxSettingsRemovePair-" + pair.key)
                    }.modifier(ListRow()).accessibilityElement(children:.contain).accessibilityIdentifier("fxSettingsPair-" + pair.key)
                        .onDrop(of:[UTType.text],delegate:MacFXSettingsDrop(type:MacFXSettingsDrag.pair,token:dragToken,target:pair.key,dragged:$draggedPair,move:movePair))
                }
                endStrip("fxPairDropEnd",type:MacFXSettingsDrag.pair,dragged:$draggedPair,move:movePair)
            }.padding(.trailing,3) }.frame(height:listHeight).accessibilityIdentifier("fxPairsSettingsScroll")
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxPairsSettingsCard")
    }
    private var converterCard: some View {
        MacSettingsCard(title:"汇率换算",icon:"arrow.left.arrow.right",subtitle:"独立维护换算页币种",action:AnyView(HStack(spacing:10) { count(service.configuration.converterCurrencies.count); Button("添加",systemImage:"plus") { addingCurrency = true }.accessibilityIdentifier("fxSettingsAddCurrencyButton").popover(isPresented:$addingCurrency) { MacFXCurrencyPicker(service:service) { addingCurrency = false } } })) {
            ScrollView { VStack(spacing:6) {
                if service.configuration.converterCurrencies.isEmpty { empty("尚未添加换算币种") }
                ForEach(service.configuration.converterCurrencies,id:\.self) { code in
                    HStack(spacing:8) {
                        handle("fxSettingsCurrencyDrag-" + code) .onDrag { draggedCurrency = code; draggedPair = nil; return MacFXSettingsDrag.provider(code,type:MacFXSettingsDrag.currency,token:dragToken) }
                        MacCurrencyFlag(code:code,width:24).fixedSize()
                        VStack(alignment:.leading,spacing:3) {
                            Text(code).appFont(.body,weight:.semibold)
                            Text(MacFXSettingsCurrencySearch.name(code)).appFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        orderControls(code,ids:service.configuration.converterCurrencies,prefix:"fxCurrencyOrder") { delta in stepCurrency(code,delta) }
                        Button("移除") { app.update { $0.converterCurrencies.removeAll { $0 == code } } }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("fxSettingsRemoveCurrency-" + code)
                    }.modifier(ListRow()).accessibilityElement(children:.contain).accessibilityIdentifier("fxSettingsCurrency-" + code)
                        .onDrop(of:[UTType.text],delegate:MacFXSettingsDrop(type:MacFXSettingsDrag.currency,token:dragToken,target:code,dragged:$draggedCurrency,move:moveCurrency))
                }
                endStrip("fxCurrencyDropEnd",type:MacFXSettingsDrag.currency,dragged:$draggedCurrency,move:moveCurrency)
            }.padding(.trailing,3) }.frame(height:listHeight).accessibilityIdentifier("fxCurrenciesSettingsScroll")
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxConverterSettingsCard")
    }
    private func count(_ value:Int) -> some View { Text(String(value)).appFont(.caption,weight:.semibold).padding(8).foregroundStyle(MacUI.accent).background(MacUI.accent.opacity(0.12),in:Circle()) }
    private func empty(_ text:String) -> some View { Text(text).appFont(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:54) }
    private func handle(_ id:String) -> some View { Image(systemName:"line.3.horizontal").appIconFont(14).foregroundStyle(.secondary).frame(width:24,height:36).contentShape(Rectangle()).accessibilityLabel("拖动排序").accessibilityIdentifier(id) }
    private func orderControls(_ id:String,ids:[String],prefix:String,move:@escaping (Int)->Void) -> some View {
        HStack(spacing:0) {
            Button { move(-1) } label: { Image(systemName:"chevron.up").frame(width:26,height:32).contentShape(Rectangle()) }.disabled(ids.first == id).accessibilityLabel("上移").accessibilityIdentifier(prefix + "Up-" + id)
            Button { move(1) } label: { Image(systemName:"chevron.down").frame(width:26,height:32).contentShape(Rectangle()) }.disabled(ids.last == id).accessibilityLabel("下移").accessibilityIdentifier(prefix + "Down-" + id)
        }.buttonStyle(MacInteractiveButtonStyle()).appIconFont(12).background(MacOverviewStyle.canvas,in:RoundedRectangle(cornerRadius:7))
    }
    private func endStrip(_ id:String,type:String,dragged:Binding<String?>,move:@escaping (String,String?)->Void) -> some View {
        Label("移至末尾",systemImage:"arrow.down.to.line").appFont(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:28).background(MacOverviewStyle.filters,in:RoundedRectangle(cornerRadius:8)).contentShape(Rectangle()).accessibilityIdentifier(id)
            .onDrop(of:[UTType.text],delegate:MacFXSettingsDrop(type:type,token:dragToken,target:nil,dragged:dragged,move:move))
    }
    private func stepPair(_ pair:MacFXPair,_ delta:Int) {
        app.update { config in guard let index = config.watchedPairs.firstIndex(of:pair), config.watchedPairs.indices.contains(index+delta) else { return }; config.watchedPairs.swapAt(index,index+delta) }
    }
    private func stepCurrency(_ code:String,_ delta:Int) {
        app.update { config in guard let index = config.converterCurrencies.firstIndex(of:code), config.converterCurrencies.indices.contains(index+delta) else { return }; config.converterCurrencies.swapAt(index,index+delta) }
    }
    private func movePair(_ key:String,_ target:String?) {
        app.update { config in
            guard let item = config.watchedPairs.first(where:{$0.key == key}) else { return }
            let destination = target.flatMap { key in config.watchedPairs.first { $0.key == key } }
            guard target == nil || destination != nil else { return }
            config.watchedPairs = MacFXListOrder.moving(config.watchedPairs,item:item,to:destination)
        }
    }
    private func moveCurrency(_ code:String,_ target:String?) { app.update { $0.converterCurrencies = MacFXListOrder.moving($0.converterCurrencies,item:code,to:target) } }
    private struct ListRow: ViewModifier {
        func body(content:Content) -> some View {
            content.appFont(.body).padding(.horizontal,10).padding(.vertical,8).frame(maxWidth:.infinity,minHeight:56).background(MacOverviewStyle.filters,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(.secondary.opacity(0.12))).contentShape(RoundedRectangle(cornerRadius:10))
        }
    }

}
