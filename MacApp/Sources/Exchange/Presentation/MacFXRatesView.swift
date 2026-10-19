import SwiftUI

struct MacFXRatesView: View {
    @ObservedObject var service: MacFXMonitor
    @ObservedObject var query: MacFXQuerySession
    var showsTools = true
    @State private var adding = false
    private var app: MacFXApplication { .shared }
    var body: some View {
        VStack(spacing: 10) {
            if showsTools {
            HStack {
                Text("关注 \(service.configuration.watchedPairs.count) 个汇率").appFont(.body, weight: .semibold)
                Spacer()
                Picker("显示单位", selection: Binding(get: { service.configuration.displayUnits }, set: { value in DispatchQueue.main.async { app.update { $0.displayUnits = value } } })) {
                    Text("1单位").tag(1); Text("100单位").tag(100)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 154).accessibilityIdentifier("fxDisplayUnits")
            }
            HStack {
                Button("添加汇率", systemImage: "plus") { adding = true }.buttonStyle(MacSettingsButtonStyle(height: 40)).accessibilityIdentifier("fxAddPair")
                    .popover(isPresented: $adding) { MacFXPairPicker { _ in adding = false } }
                Spacer()
                Button(service.busy ? "正在更新…" : "更新", systemImage: "arrow.clockwise") { Task { await service.refresh(reason: .manual) } }
                    .buttonStyle(MacSettingsButtonStyle(height: 40)).disabled(service.busy).accessibilityIdentifier("fxUpdateRates")
            }
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(service.configuration.watchedPairs, id: \.key) { pair in
                        MacFXRateCard(pair: pair, service: service, query: query, history: app.history).id(pair.key)
                    }
                }.scrollTargetLayout().padding(.bottom, 8)
                if service.configuration.watchedPairs.isEmpty { ContentUnavailableView("尚未关注汇率", systemImage: "chart.line.uptrend.xyaxis", description: Text("从货币列表中添加需要关注的货币对。")) }
            }.scrollPosition(id: $query.ratesScrollPair, anchor: .top).accessibilityIdentifier("fxRatesScroll")
            MacFXLastUpdatedView(service:service)
        }
        .onChange(of: service.configuration.watchedPairs) { _, pairs in
            if let key = query.expandedPair, !pairs.contains(where: { $0.key == key }) { query.expandedPair = nil }
            let valid = Set(pairs.map(\.key))
            query.cardInputs = query.cardInputs.filter { valid.contains($0.key) }
            query.cardModes = query.cardModes.filter { valid.contains($0.key) }
            query.cardRanges = query.cardRanges.filter { valid.contains($0.key) }
        }
        .task { await service.pageOpened() }
    }
}

struct MacFXPairPicker: View {
    var onChoose: (MacFXPair) -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("添加关注汇率").appFont(.section,weight:.semibold)
            MacFXPairAddForm(onAdded:onChoose)
        }.appFont(.body).padding(18).frame(width:360)
    }
}
