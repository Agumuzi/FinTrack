import SwiftUI
import SwiftData

struct MacCurrencyRebaseView: View {
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
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            Text("Change book currency").appFont(.dialogTitle, weight: .semibold)
            Text("将按原币金额重算现有账目（包括手动本币金额）、金融规则、目标、初始资产与月度预算；准备阶段不写入，确认时先创建原生完整备份。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            MacSettingsRow(label: "当前本位币", labelWidth: 100) { Text(reference).frame(maxWidth: .infinity, alignment: .leading) }
            MacSettingsRow(label: "换算为", labelWidth: 100) { MacBookCurrencyChoice(currency: $currency) }
            DisclosureGroup("手动指定已核实汇率（可选）") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("留空时按每笔记录的日期获取汇率。手动汇率会覆盖对应原币的全部记录。")
                        .appFont(.caption).foregroundStyle(.secondary)
                    ForEach(sources.filter { $0 != currency.uppercased() }, id: \.self) { source in
                        HStack {
                            Text("1 " + source + " =").frame(width: 80)
                            TextField("汇率", text: Binding(get: { manual[source] ?? "" }, set: { manual[source] = $0; plan = nil }))
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
                    busy = true; error = nil
                    Task { @MainActor in
                        defer { busy = false }
                        do {
                            var rates: [String: Double] = [:]
                            for (source, value) in manual where !value.isEmpty { rates[source] = try MacCurrency.rate(value) }
                            plan = try await MacCurrencyRebase.prepare(in: context, to: currency, referenceCurrency: reference, manualRates: rates)
                        } catch { self.error = MacLocalization.error(error) }
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
        .onChange(of: currency) { _, _ in plan = nil }
        .onChange(of: reference) { _, value in
            plan = nil
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
