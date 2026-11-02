import SwiftUI

struct MacFXRatesView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @ObservedObject var service: MacFXMonitor
    @ObservedObject var query: MacFXQuerySession
    var showsTools = true
    @State private var adding = false
    private var app: MacFXApplication { .shared }
    var body: some View {
        VStack(spacing: 10) {
            if showsTools {
            HStack {
                Text(L10n.format("mac.fXRatesView.body.63807509c6", Int64(service.configuration.watchedPairs.count))).appFont(.body, weight: .semibold)
                Spacer()
                Picker(L10n.text("mac.fXRatesView.Picker.7f92957e2e"), selection: Binding(get: { service.configuration.displayUnits }, set: { value in DispatchQueue.main.async { app.update { $0.displayUnits = value } } })) {
                    Text(L10n.text("mac.fXRatesView.Picker.741dcea7b4")).tag(1); Text(L10n.text("mac.fXRatesView.Picker.b6e384046e")).tag(100)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 154).accessibilityIdentifier("fxDisplayUnits")
            }
            HStack {
                Button(L10n.text("mac.fXRatesView.body.fce6c36a18"), systemImage: "plus") { adding = true }.buttonStyle(MacSettingsButtonStyle(height: 40)).accessibilityIdentifier("fxAddPair")

                Spacer()
                Button(service.busy ? L10n.text("mac.fXRatesView.body.e6442ce18f") : L10n.text("mac.fXRatesView.body.3055a035f0"), systemImage: "arrow.clockwise") { Task { await service.refresh(reason: .manual) } }
                    .buttonStyle(MacSettingsButtonStyle(height: 40)).disabled(service.busy).accessibilityIdentifier("fxUpdateRates")
            }
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(service.configuration.watchedPairs, id: \.key) { pair in
                        MacFXRateCard(pair: pair, service: service, query: query, history: app.history).id(pair.key)
                    }
                }.scrollTargetLayout().padding(.bottom, 8)
                if service.configuration.watchedPairs.isEmpty {ContentUnavailableView {Label(L10n.text("mac.fXRatesView.ContentUnavailableView.c180208d3f"),systemImage:"chart.line.uptrend.xyaxis")} description:{Text(L10n.text("mac.fXRatesView.ContentUnavailableView.0f27f21be3"))} actions:{Button(L10n.text("mac.fXRatesView.ContentUnavailableView.00c06565a0")) {adding=true}.accessibilityIdentifier("fxEmptyAddPair")}}
            }.scrollPosition(id: $query.ratesScrollPair, anchor: .top).accessibilityIdentifier("fxRatesScroll")
            MacFXLastUpdatedView(service:service)
        }
        .popover(isPresented:$adding) {MacFXPairPicker {_ in adding=false}}
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
    @ObservedObject private var localizationState = LocalizationController.shared
    var onChoose: (MacFXPair) -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text(L10n.text("mac.fXRatesView.body.e7461b42f4")).appFont(.section,weight:.semibold)
            MacFXPairAddForm(onAdded:onChoose)
        }.appFont(.body).padding(18).frame(width:360)
    }
}
