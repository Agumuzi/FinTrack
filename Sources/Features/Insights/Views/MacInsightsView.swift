import SwiftUI
import SwiftData

struct MacInsightsView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    let previewCurrency: String
    @Query(sort: \Transaction.date) private var transactions: [Transaction]
    @Query private var deposits: [DepositRecord]
    @Query private var loans: [LoanRule]
    @Query private var recurring: [RecurringTransaction]
    @AppStorage("base_currency") private var preferredCurrency = "USD"
    @State private var chosenCurrency = ""
    var body: some View {
        let codes = MacCurrency.resolveLedgerCurrency(transactions: transactions, deposits: deposits, loans: loans, recurring: recurring, preferred: preferredCurrency).availableCurrencies
        let currency = codes.contains(chosenCurrency) ? chosenCurrency : (codes.contains(preferredCurrency) ? preferredCurrency : codes[0])
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("mac.insightsView.ScrollView.36af57a907")).appFont(.pageTitle, weight: .bold).accessibilityIdentifier("insightsPageTitle")
                        Text(L10n.text("mac.insightsView.ScrollView.e9132cb3dc")).appFont(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if codes.count > 1 {
                        MacCurrencyMenu(selection:Binding(get:{currency},set:{chosenCurrency = $0}),codes:codes,identifier:"insightsCurrency")
                    } else { Text(currency).appFont(.body, weight: .medium).foregroundStyle(.secondary) }
                }
                MacPeriodComparisonDashboard(transactions: transactions, currency: currency)
            }.padding(24)
        }.background(MacOverviewStyle.canvas)
    }
}

struct MacFinancialProfileEditor: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    let currency: String
    let profile: FinancialProfile?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var assets = "0"
    @State private var debt = "0"
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            Text(L10n.text("mac.insightsView.body.0e199d4bbe")).appFont(.dialogTitle, weight: .semibold)
            Text(currency).foregroundStyle(.secondary)
            TextField(L10n.text("mac.insightsView.body.dc57eb2e51"), text: $assets).accessibilityIdentifier("profileAssets")
            TextField(L10n.text("mac.insightsView.body.eaf3ae29c3"), text: $debt).accessibilityIdentifier("profileDebt")
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L10n.text("mac.insightsView.body.2cd0f3be87")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("mac.insightsView.body.a3030bf8f1")) {
                    do {
                        try MacFinancialSettings.saveProfile(assets: assets, debt: debt, currency: currency, in: context)
                        dismiss()
                    } catch { self.error = MacLocalization.error(error) }
                }.keyboardShortcut(.defaultAction).accessibilityIdentifier("saveFinancialProfile")
            }
        }.appPadding(24).appDialog(width: 480)
        .onAppear {
            assets = String(profile?.initialAssets ?? 0)
            debt = String(abs(profile?.initialDebt ?? 0))
        }
    }
}
