import SwiftUI
import SwiftData

struct MacInsightsView: View {
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
                        Text("期间对比").appFont(.pageTitle, weight: .bold).accessibilityIdentifier("insightsPageTitle")
                        Text("比较不同期间的收入、支出与净额。").appFont(.caption).foregroundStyle(.secondary)
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
    let currency: String
    let profile: FinancialProfile?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var assets = "0"
    @State private var debt = "0"
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            Text("初始资产与负债").appFont(.dialogTitle, weight: .semibold)
            Text(currency).foregroundStyle(.secondary)
            TextField("初始资产", text: $assets).accessibilityIdentifier("profileAssets")
            TextField("初始负债", text: $debt).accessibilityIdentifier("profileDebt")
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
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
