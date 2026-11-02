import SwiftUI
import SwiftData
import Charts

struct MacBudgetSettingsView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var wide: Bool
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var workspace: MacWorkspaceSession
    @Query private var transactions: [Transaction]
    @Query private var categories: [Category]
    @AppStorage("base_currency") private var preferredCurrency = "USD"
    @AppStorage("v2_budgets") private var budgetBytes = Data()
    @State private var month = Date()
    @State private var mode = "分类预算"
    @State private var selectedID: UUID?
    @State private var editor: MacBudget?
    @State private var receipt: Transaction?
    private var currency: String? { try? MacCurrency.ledgerCurrency(in: context, preferred: preferredCurrency) }
    private var budgets: [MacBudget] { (try? JSONDecoder().decode([MacBudget].self, from: budgetBytes)) ?? [] }
    private var current: [MacBudget] {
        let currency = self.currency, month = MacBudgetData.month(month)
        return budgets.filter { $0.month == month && $0.currency == currency }
    }
    private var rows: [MacBudget] { current.filter { ($0.categoryID == nil && $0.categoryName == nil) == (mode == "总预算") } }
    private var selected: MacBudget? { rows.first { $0.id == selectedID } ?? rows.first }
    private var total: Double { current.first { $0.enabled && $0.categoryID == nil && $0.categoryName == nil }?.amount ?? current.filter { $0.enabled }.reduce(0) { $0 + $1.amount } }
    var body: some View {
        let spending = MacBudgetSpendingSnapshot(rows: transactions, categories: categories)
        let allExpense = spending.spent(MacBudget(month: MacBudgetData.month(month), currency: currency ?? preferredCurrency, amount: 1))
        let selected = self.selected
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            HStack {
                Spacer()
                HStack(spacing: MacUI.space(0)) { Button { shift(-1) } label: { Image(systemName: "chevron.left") }; Text(MacDisplayPreferences.month(month)).appFont(.body, weight: .semibold, design: .default).frame(minWidth: MacUI.space(124)).accessibilityIdentifier("budgetMonth"); Button { shift(1) } label: { Image(systemName: "chevron.right") } }
                Button(L10n.text("mac.budgetSettingsView.body.74c95225b9"), systemImage: "plus") { addBudget() }.disabled(currency == nil).accessibilityIdentifier("settingsBudgetAdd")
            }.padding(.top, MacUI.space(wide ? -64 : 0)).padding(.bottom, MacUI.space(wide ? 12 : 0))
            MacSettingsColumns(wide: wide) {
                MacSettingsCard(title: "", icon: "") {
                    VStack(spacing: MacUI.space(13)) {
                        MacSettingsSegments(selection: $mode, options: ["分类预算", "总预算"]).accessibilityIdentifier("settingsBudgetMode")
                        budgetSummary(allExpense: allExpense)
                        HStack { MacSettingsProgress(value: total > 0 ? allExpense / total : 0, color: .green); Text(total > 0 ? String(format: "%.1f%%", allExpense / total * 100) : "—").appFont(.body, weight: .semibold, design: .default).lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                        HStack { Spacer(); Button(L10n.text("mac.budgetSettingsView.MacSettingsColumns.c04c51ae30"), systemImage: "plus") { addBudget() } }
                        categoryBudgetRows(spending: spending, selectedID: selected?.id)
                    }
                }
            } right: {
                if let row = selected {
                    VStack(spacing: MacUI.space(14)) {
                        MacBudgetInlineEditor(budget: row, category: categoryName(row)) { selectedID = $0.id; month = parseMonth($0.month) }.id(row)
                        MacSettingsCard(title: L10n.text("mac.budgetSettingsView.MacSettingsColumns.ea765644c3"), icon: "chart.bar", headerColor: .red, compactHeader: true) {
                            let points = trend(row, spending: spending)
                            Chart(points, id: \.date) { item in
                                BarMark(x: .value(L10n.text("mac.budgetSettingsView.BarMark.a27822d135"), item.date, unit: .month), y: .value(L10n.text("mac.budgetSettingsView.BarMark.e679096865"), item.amount)).foregroundStyle(Calendar.current.isDate(item.date, equalTo: month, toGranularity: .month) ? MacAccent.color(row.displayColor) : MacAccent.color(row.displayColor).opacity(0.3)).cornerRadius(3)
                                RuleMark(y: .value(L10n.text("mac.budgetSettingsView.RuleMark.49f156ef03"), row.amount)).foregroundStyle(MacAccent.color(row.displayColor)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4,4]))
                            }.chartYScale(domain: 0...max(row.amount, points.map(\.amount).max() ?? 0) * 1.15).chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month()) } }.appMinHeight(130)
                        }
                        MacSettingsCard(title: L10n.text("mac.budgetSettingsView.MacSettingsColumns.c2233955c3"), icon: "doc.text", headerColor: .orange, action: AnyView(Button(L10n.text("mac.budgetSettingsView.AnyView.fa2ff3c379")) { showRecords(category: categoryName(row)) }.buttonStyle(.link).appFont(.caption, weight: .regular, design: .default)), compactHeader: true) {
                            let related = related(row)
                            if related.isEmpty { Text(L10n.text("mac.budgetSettingsView.MacSettingsColumns.ce1e8044ec")).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                            ForEach(related.prefix(3), id: \.id) { item in
                                Button { receipt = item } label: {
                                    HStack(spacing: MacUI.space(10)) { MacCategoryBadge(name: item.category, size: 31, filled: false); VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(MacFinanceNotes.visible(item.note).isEmpty ? item.category : MacFinanceNotes.visible(item.note)).appFont(.body, weight: .medium, design: .default); Text(MacDateDisplay.string(item.date)).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }; Spacer(); Text("−" + MacSettingsVisual.money(item.baseAmount) + " " + MacSettingsVisual.symbol(item.baseCurrencyCode)).appFont(.body, weight: .medium, design: .default).foregroundStyle(.red) }.contentShape(Rectangle())
                                }.buttonStyle(MacInteractiveButtonStyle())
                            }
                        }
                    }
                } else { MacSettingsCard(title: L10n.text("mac.budgetSettingsView.MacSettingsColumns.38937b4440"), icon: "chart.bar") { Text(L10n.text("mac.budgetSettingsView.MacSettingsColumns.35db4ca3e5")).foregroundStyle(.secondary) } }
            }
        }
        .sheet(item: $editor) { row in MacBudgetEditor(budget: row, categories: categories.filter { $0.deletedAt == nil && $0.type == "Expense" }) { selectedID = $0 } }
        .sheet(item: $receipt) { MacSettingsReceipt(row: $0) }
    }
    private func addBudget() { editor = MacBudget(month: MacBudgetData.month(month), currency: currency ?? preferredCurrency, amount: 1000) }
    private func budgetSummary(allExpense: Double) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: MacUI.space(14)) {
                metric(L10n.text("mac.budgetSettingsView.metric.e627835c1f"), total, id: "budgetTotal")
                Spacer(minLength: MacUI.space(5))
                metric(L10n.text("mac.budgetSettingsView.metric.5dcf5d928d"), allExpense, id: "budgetSpent")
                editTotalBudgetButton
            }
            VStack(alignment: .leading, spacing: MacUI.space(10)) {
                metric(L10n.text("mac.budgetSettingsView.metric.e627835c1f"), total, id: "budgetTotal")
                metric(L10n.text("mac.budgetSettingsView.metric.5dcf5d928d"), allExpense, id: "budgetSpent")
                HStack { Spacer(); editTotalBudgetButton }
            }
        }
        .appPadding(.top, 5)
    }

    private var editTotalBudgetButton: some View {
        Button(L10n.text("mac.budgetSettingsView.editTotalBudgetButton.0518365699")) {
            editor = current.first { $0.categoryID == nil && $0.categoryName == nil }
                ?? MacBudget(month: MacBudgetData.month(month), currency: currency ?? preferredCurrency, amount: total > 0 ? total : 1000)
        }.accessibilityIdentifier("budgetEditTotal")
    }

    private func categoryBudgetRows(spending: MacBudgetSpendingSnapshot, selectedID: UUID?) -> some View {
        Group {
        if rows.isEmpty {
            VStack(spacing: 8) { Label(L10n.text("mac.budgetSettingsView.categoryBudgetRows.d9fc8655c1"), systemImage: "chart.bar").appFont(.body, weight: .semibold); Text(L10n.text("mac.budgetSettingsView.categoryBudgetRows.6b08574287")).appFont(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 28)
        } else {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: MacUI.space(0)) {
                HStack {
                    Text(L10n.text("mac.budgetSettingsView.ViewThatFits.515559957f")).frame(minWidth: MacUI.space(70), maxWidth: .infinity, alignment: .leading)
                    Text(L10n.text("mac.budgetSettingsView.ViewThatFits.ba33c3687a")).frame(width: MacUI.space(156), alignment: .trailing)
                    Text(L10n.text("mac.budgetSettingsView.ViewThatFits.5dcf5d928d")).frame(width: MacUI.space(120), alignment: .trailing)
                    Text(L10n.text("mac.budgetSettingsView.ViewThatFits.f81ff55de1")).frame(width: MacUI.space(105), alignment: .trailing)
                }
                .appFont(.caption, weight: .medium, design: .default).foregroundStyle(.secondary).appPadding(8).background(.gray.opacity(0.04))
                ForEach(rows) { row in budgetRow(row, compact: false, spending: spending, selectedID: selectedID); Divider() }
            }
            VStack(spacing: MacUI.space(9)) {
                ForEach(rows) { row in budgetRow(row, compact: true, spending: spending, selectedID: selectedID) }
            }
        }
        }
        }
    }

    @ViewBuilder
    private func budgetRow(_ row: MacBudget, compact: Bool, spending: MacBudgetSpendingSnapshot, selectedID effectiveSelection: UUID?) -> some View {
        let name = categoryName(row) ?? L10n.text("mac.budgetSettingsView.name.4bb6f35152")
        let used = spending.spent(row)
        let fraction = used / row.amount
        let amountText = MacSettingsVisual.money(row.amount) + " " + MacSettingsVisual.symbol(row.currency)
        let spentText = MacSettingsVisual.money(used) + " " + MacSettingsVisual.symbol(row.currency)
        let percentText = String(format: "%.1f%%", fraction * 100)
        Button { selectedID = row.id } label: {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: MacUI.space(7)) {
                        HStack(spacing: MacUI.space(8)) {
                            MacSettingsIcon(symbol: row.displayIcon, color: MacAccent.color(row.displayColor), size: 27)
                            Text(MacOverviewStyle.category(name)).appFont(.body, weight: .medium, design: .default).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 3)
                            Text(percentText).appFont(.caption, weight: .regular, design: .default).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Text(L10n.text("mac.budgetSettingsView.budgetRow.c97be8ceef") + spentText).foregroundStyle(fraction >= 0.8 ? .red : .primary)
                            Spacer(minLength: 4)
                            Text(L10n.text("mac.budgetSettingsView.budgetRow.eaff3e0c21") + amountText).foregroundStyle(.secondary)
                        }.appFont(.caption).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        MacSettingsProgress(value: fraction, color: fraction >= 0.8 ? .red : .green, height: 7)
                    }.appPadding(.horizontal, 9).appPadding(.vertical, 9)
                } else {
                    HStack(spacing: MacUI.space(8)) {
                        MacSettingsIcon(symbol: row.displayIcon, color: MacAccent.color(row.displayColor), size: 28)
                        Text(MacOverviewStyle.category(name)).appFont(.body, weight: .medium, design: .default).lineLimit(1).truncationMode(.tail).frame(minWidth: MacUI.space(70), maxWidth: .infinity, alignment: .leading)
                        Text(amountText).appFont(.caption, weight: .medium, design: .default).lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(width: MacUI.space(156), alignment: .trailing)
                        Text(spentText).appFont(.caption, weight: .medium, design: .default).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(fraction >= 0.8 ? .red : .primary).frame(width: MacUI.space(120), alignment: .trailing)
                        HStack(spacing: MacUI.space(5)) {
                            MacSettingsProgress(value: fraction, color: fraction >= 0.8 ? .red : .green, height: 7)
                            Text(percentText).appFont(.caption, weight: .regular, design: .default).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(.secondary)
                        }.frame(width: MacUI.space(105))
                        Image(systemName: "chevron.right").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                    }.appPadding(.horizontal, 5).appMinHeight(44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(effectiveSelection == row.id ? MacSettingsVisual.accent.opacity(0.025) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(MacInteractiveButtonStyle())
        .accessibilityRepresentation { Button(name + L10n.text("mac.budgetSettingsView.budgetRow.bd8dbd5724")) { selectedID = row.id }.accessibilityIdentifier("budgetRow-" + name) }
    }

    private func metric(_ title: String, _ value: Double, id: String) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(9)) {
            Text(title).appFont(.body, weight: .medium, design: .default)
            Text(MacSettingsVisual.money(value) + " " + MacSettingsVisual.symbol(currency ?? ""))
                .appFont(.amount, weight: .bold, design: .default).monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityRepresentation { Text(title + " " + MacSettingsVisual.money(value) + " " + MacSettingsVisual.symbol(currency ?? "")).accessibilityIdentifier(id) }
    }
    private func categoryName(_ row: MacBudget) -> String? { row.categoryID.flatMap { id in categories.first { $0.id == id }?.name } ?? row.categoryName }
    private func shift(_ n: Int) { month = Calendar.current.date(byAdding: .month, value: n, to: month)!; selectedID = nil }
    private func parseMonth(_ text: String) -> Date { let p = text.split(separator: "-").compactMap { Int($0) }; return Calendar.current.date(from: DateComponents(year: p.first, month: p.last, day: 1)) ?? month }
    private func related(_ row: MacBudget) -> [Transaction] { transactions.filter { $0.deletedAt == nil && $0.typedType == .expense && $0.baseCurrencyCode == row.currency && MacBudgetData.month($0.date) == row.month && (categoryName(row) == nil || $0.category == categoryName(row)) }.sorted { $0.date > $1.date } }
    private struct Point { var date: Date; var amount: Double }
    private func trend(_ row: MacBudget, spending: MacBudgetSpendingSnapshot) -> [Point] { (0..<6).reversed().map { offset in let date = Calendar.current.date(byAdding: .month, value: -offset, to: month)!; var b = row; b.month = MacBudgetData.month(date); return Point(date: date, amount: spending.spent(b)) } }
    private func showRecords(category: String?) { var scope = MacOverviewScope(); scope.reference = month; scope.type = .expense; scope.category = category; workspace.showRecords(scope) }
}

struct MacBudgetInlineEditor: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @State var budget: MacBudget
    var category: String?
    var onSave: (MacBudget) -> Void
    @Environment(\.modelContext) private var context
    private struct Draft { let budget: MacBudget; let original: MacBudget; let amount: String; let start: Date; let generation: Int }
    @State private var original: MacBudget?
    @State private var generation = 0
    @State private var discard = false
    private var draftKey: String { MacEditorDraftStore.key("budget", budget.id.uuidString, context: context) }
    private func loadDraft(reset: Bool = false) {
        if reset { MacEditorDraftStore.shared.remove(draftKey) }
        if let d = MacEditorDraftStore.shared.load(draftKey, as: Draft.self) {
            budget=d.budget;original=d.original;amount=d.amount;start=d.start;generation=d.generation
        } else {
            let rows: [MacBudget] = MacSettingsStore.load("v2_budgets", fallback: [])
            if let fresh=rows.first(where:{$0.id == budget.id}) {budget=fresh}
            original=budget;amount=MacTransactionCRUD.amountEditingText(budget.amount)
            let parts=budget.month.split(separator:"-").compactMap{Int($0)}
            start=Calendar.current.date(from:DateComponents(year:parts.first,month:parts.last,day:1)) ?? Date()
            generation=MacEditorDraftStore.shared.generation
        }
    }
    @State private var amount = ""
    @State private var start = Date()
    @State private var error: String?
    @State private var message: String?
    var body: some View {
        MacSettingsCard(title: category.map(MacOverviewStyle.category) ?? L10n.text("mac.budgetSettingsView.body.4bb6f35152"), icon: budget.displayIcon, headerColor: MacAccent.color(budget.displayColor), action: AnyView(Toggle(L10n.text("mac.budgetSettingsView.AnyView.e37e0d1a68"), isOn: $budget.enabled).labelsHidden().toggleStyle(.switch).tint(.blue))) {
            MacSettingsRow(label: L10n.text("mac.budgetSettingsView.body.ba33c3687a"), labelWidth: 98) { HStack { MacNumericInput(text: $amount, identifier: "budgetInlineAmount").frame(minHeight: 24).appFormControl(); Text(MacSettingsVisual.symbol(budget.currency)).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary) } }
            MacSettingsRow(label: L10n.text("mac.budgetSettingsView.body.e9bf2c2fea"), labelWidth: 98) { HStack { Text(L10n.text("mac.budgetSettingsView.body.68b21af949")); Spacer(); Image(systemName: "calendar").foregroundStyle(.secondary) }.appFont(.body, weight: .regular, design: .default).appPadding(10).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.2))) }
            MacSettingsRow(label: L10n.text("mac.budgetSettingsView.body.f37515d806"), labelWidth: 98) { MacSettingsDateButton(date: $start, monthOnly: true) }
            MacSymbolColorPicker(icon: Binding(get: { budget.displayIcon }, set: { budget.icon = $0 }), color: Binding(get: { budget.displayColor }, set: { budget.color = $0 }), title: L10n.text("mac.budgetSettingsView.MacSymbolColorPicker.bd8dbd5724"), identifierPrefix: "budgetInlineIcon")
            VStack(alignment: .leading, spacing: MacUI.space(7)) { Text(L10n.text("mac.budgetSettingsView.body.b405227c7e")).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary); MacSettingsNoteField(placeholder: L10n.text("mac.budgetSettingsView.MacSettingsNoteField.32832320ec"), text: $budget.note).accessibilityIdentifier("budgetInlineNote") }
            HStack { Text(message ?? L10n.text("mac.budgetSettingsView.body.a58e658f04")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary); Spacer(); Button(L10n.text("mac.budgetSettingsView.body.991bb7cfe5")) { save() }.accessibilityIdentifier("budgetInlineSave") }
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red);Button(L10n.text("mac.budgetSettingsView.body.f057369770")) {discard=true} }
        }.onAppear { loadDraft() }.onDisappear {
            if let original {MacEditorDraftStore.shared.save(Draft(budget:budget,original:original,amount:amount,start:start,generation:generation),key:draftKey,generation:generation)}
        }.confirmationDialog(L10n.text("mac.budgetSettingsView.body.46c8da8a29"),isPresented:$discard) {
            Button(L10n.text("mac.budgetSettingsView.body.ab0eba1876"),role:.destructive) {loadDraft(reset:true);error=nil}
        }

    }
    private func save() { do {
        let rows:[MacBudget]=MacSettingsStore.load("v2_budgets",fallback:[])
        guard rows.first(where:{$0.id == budget.id}) == original, generation == MacEditorDraftStore.shared.generation else {throw MacSettingsFailure.invalid(L10n.text("mac.budgetSettingsView.save.d9e7fea94b"))}
        budget.amount = try MacTransactionCRUD.editedAmount(amount, original: budget.amount); budget.month = MacBudgetData.month(start); try MacBudgetData.save(budget); error = nil; message = L10n.text("mac.budgetSettingsView.save.1bd91a7d0c"); original=budget;MacEditorDraftStore.shared.remove(draftKey);onSave(budget) } catch { self.error = MacLocalization.error(error) } }
}

struct MacBudgetEditor: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @Environment(\.dismiss) private var dismiss
    @State var budget: MacBudget
    var categories: [Category]
    var onSave: (UUID) -> Void
    @State private var amount = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(18)) {
            Text(L10n.format("mac.budgetSettingsView.body.ab7bd40f33", "\(budget.month)")).appFont(.dialogTitle, weight: .semibold)
            HStack {
                Text(L10n.text("mac.budgetSettingsView.body.ae72b532f4")).foregroundStyle(.secondary); Spacer()
                MacSettingsMenu(selection: $budget.categoryID, options: [(L10n.text("mac.budgetSettingsView.MacSettingsMenu.4bb6f35152"), UUID?.none)] + categories.map { (MacOverviewStyle.category($0.name), Optional($0.id)) }).frame(width: 220).accessibilityIdentifier("budgetEditorCategory")
            }
            HStack { MacNumericInput(text: $amount, identifier: "budgetEditorAmount").frame(minHeight: 24).appFormControl(); Text(budget.currency).foregroundStyle(.secondary) }
            Toggle(L10n.text("mac.budgetSettingsView.body.3252557e90"), isOn: $budget.enabled)
            MacSymbolColorPicker(icon: Binding(get: { budget.displayIcon }, set: { budget.icon = $0 }), color: Binding(get: { budget.displayColor }, set: { budget.color = $0 }), title: L10n.text("mac.budgetSettingsView.MacSymbolColorPicker.bd8dbd5724"), identifierPrefix: "budgetEditorIcon")
            MacSettingsNoteField(placeholder: L10n.text("mac.budgetSettingsView.MacSettingsNoteField.b405227c7e"), text: $budget.note).accessibilityIdentifier("budgetEditorNote")
            Text(L10n.format("mac.budgetSettingsView.body.522f00538e", "\(budget.month)")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("budgetEditorError") }
            HStack { Button(L10n.text("mac.budgetSettingsView.body.2cd0f3be87")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(L10n.text("mac.budgetSettingsView.body.93f637f4e3")) {
                do {
                    budget.amount = try MacTransactionCRUD.editedAmount(amount, original: budget.amount)
                    budget.categoryName = budget.categoryID.flatMap { id in categories.first { $0.id == id }?.name }
                    try MacBudgetData.save(budget); onSave(budget.id); dismiss()
                } catch { self.error = MacLocalization.error(error) }
            }.keyboardShortcut(.defaultAction).accessibilityIdentifier("budgetEditorSave") }
        }.appPadding(26).appDialog(width: 500).onAppear { amount = String(budget.amount) }
    }
}

struct MacSettingsReceipt: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var row: Transaction
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(18)) {
            Text(L10n.text("mac.budgetSettingsView.body.cad00c1016")).appFont(.dialogTitle, weight: .semibold)
            LabeledContent(L10n.text("mac.budgetSettingsView.LabeledContent.515559957f"), value: MacOverviewStyle.category(row.category))
            LabeledContent(L10n.text("mac.budgetSettingsView.LabeledContent.70d0c1b336"), value: MacDateDisplay.string(row.date))
            LabeledContent(L10n.text("mac.budgetSettingsView.LabeledContent.fee8c0943c"), value: "\(MacOverviewStyle.money(row.originalAmount)) \(row.originalCurrency)")
            LabeledContent(L10n.text("mac.budgetSettingsView.LabeledContent.b85770b711"), value: "\(MacOverviewStyle.money(row.baseAmount)) \(row.baseCurrencyCode)")
            LabeledContent(L10n.text("mac.budgetSettingsView.LabeledContent.77084c2fe4"), value: String(row.exchangeRateToBase))
            Text(MacFinanceNotes.visible(row.note)).foregroundStyle(.secondary)
            HStack { Spacer(); Button(L10n.text("mac.budgetSettingsView.body.3fd47edce4")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.appPadding(26).appDialog(width: 440)
    }
}
