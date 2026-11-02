import SwiftUI
import SwiftData

struct MacCurrencyRebaseView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var initialCurrency: String? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var currency = "USD"
    @State private var reference = "USD"
    @State private var manual: [String: String] = [:]
    @State private var sources: [String] = []
    @State private var plan: MacCurrencyRebase.Plan?
    @State private var busy = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var preparation: Task<Void, Never>?
    private func invalidate() { requestID = UUID(); preparation?.cancel(); preparation = nil; busy = false; plan = nil }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            Text("Change book currency").appFont(.dialogTitle, weight: .semibold)
            Text(L10n.text("mac.currencyRebaseView.body.ec540c616d")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            MacSettingsRow(label: L10n.text("mac.currencyRebaseView.body.3ba33de97d"), labelWidth: 100) { Text(reference).frame(maxWidth: .infinity, alignment: .leading) }
            MacSettingsRow(label: L10n.text("mac.currencyRebaseView.body.c98f12c978"), labelWidth: 100) { MacBookCurrencyChoice(currency: $currency) }
            DisclosureGroup(L10n.text("mac.currencyRebaseView.DisclosureGroup.2be96d3f4e")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("mac.currencyRebaseView.DisclosureGroup.19ae306beb"))
                        .appFont(.caption).foregroundStyle(.secondary)
                    ForEach(sources.filter { $0 != currency.uppercased() }, id: \.self) { source in
                        HStack {
                            Text("1 " + source + " =").frame(width: 80)
                            TextField(L10n.text("mac.currencyRebaseView.ForEach.57ef2c45ef"), text: Binding(get: { manual[source] ?? "" }, set: { manual[source] = $0; invalidate() }))
                            Text(currency.uppercased()).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.top, 8)
            }
            if let plan { Text("Prepared records: \(plan.count) · \(plan.currency)") }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Prepare conversion") {
                    invalidate(); busy = true; error = nil
                    let token = requestID, target = currency, original = reference, inputs = manual
                    preparation = Task { @MainActor in
                        defer { if requestID == token { busy = false; preparation = nil } }
                        do {
                            var rates: [String: Double] = [:]
                            for (source, value) in inputs where !value.isEmpty { rates[source] = try MacCurrency.rate(value) }
                            let prepared = try await MacCurrencyRebase.prepare(in: context, to: target, referenceCurrency: original, manualRates: rates)
                            guard !Task.isCancelled, token == requestID else { return }
                            plan = prepared
                        } catch { if !Task.isCancelled && token == requestID { self.error = MacLocalization.error(error) } }
                    }
                }.disabled(busy || currency.uppercased() == reference || (try? MacCurrency.code(currency)) == nil)
                .accessibilityIdentifier("prepareCurrencyRebase")
                Button("Back up and apply") {
                    guard let plan else { return }
                    do { try MacCurrencyRebase.commit(plan, in: context); dismiss() }
                    catch { self.error = MacLocalization.error(error) }
                }.disabled(plan == nil || busy).accessibilityIdentifier("applyCurrencyRebase")
            }
        }.appPadding(24).appDialog(width: 590)
        .onDisappear { invalidate() }
        .onChange(of: currency) { _, _ in invalidate() }
        .onChange(of: reference) { _, value in
            invalidate()
            if let code = try? MacCurrency.code(value), !sources.contains(code) { sources.append(code); sources.sort() }
        }
        .onAppear {
            reference = MacPreferences.defaults.string(forKey: "base_currency") ?? "USD"
            currency = initialCurrency ?? reference
            var set = Set((try? context.fetch(FetchDescriptor<Transaction>()).map(\.originalCurrency)) ?? [])
            set.formUnion((try? context.fetch(FetchDescriptor<LoanRule>()).map(\.currency)) ?? [])
            set.formUnion((try? context.fetch(FetchDescriptor<DepositRecord>()).map(\.originalCurrency)) ?? [])
            set.formUnion((try? context.fetch(FetchDescriptor<RecurringTransaction>()).map(\.originalCurrency)) ?? [])
            let budgets: [MacBudget] = MacSettingsStore.load("v2_budgets", fallback: []); set.formUnion(budgets.map(\.currency))
            set.insert(reference); sources = set.sorted()
        }
    }
}
