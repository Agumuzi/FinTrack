import SwiftUI
import SwiftData
import Charts

struct MacBudgetSettingsView: View {
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
                Button("新建预算", systemImage: "plus") { addBudget() }.disabled(currency == nil).accessibilityIdentifier("settingsBudgetAdd")
            }.padding(.top, MacUI.space(wide ? -64 : 0)).padding(.bottom, MacUI.space(wide ? 12 : 0))
            MacSettingsColumns(wide: wide) {
                MacSettingsCard(title: "", icon: "") {
                    VStack(spacing: MacUI.space(13)) {
                        MacSettingsSegments(selection: $mode, options: ["分类预算", "总预算"]).accessibilityIdentifier("settingsBudgetMode")
                        budgetSummary(allExpense: allExpense)
                        HStack { MacSettingsProgress(value: total > 0 ? allExpense / total : 0, color: .green); Text(total > 0 ? String(format: "%.1f%%", allExpense / total * 100) : "—").appFont(.body, weight: .semibold, design: .default).lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                        HStack { Spacer(); Button("添加分类预算", systemImage: "plus") { addBudget() } }
                        categoryBudgetRows(spending: spending, selectedID: selected?.id)
                    }
                }
            } right: {
                if let row = selected {
                    VStack(spacing: MacUI.space(14)) {
                        MacBudgetInlineEditor(budget: row, category: categoryName(row)) { selectedID = $0.id; month = parseMonth($0.month) }.id(row)
                        MacSettingsCard(title: "支出趋势", icon: "chart.bar", headerColor: .red, compactHeader: true) {
                            let points = trend(row, spending: spending)
                            Chart(points, id: \.date) { item in
                                BarMark(x: .value("月份", item.date, unit: .month), y: .value("支出", item.amount)).foregroundStyle(Calendar.current.isDate(item.date, equalTo: month, toGranularity: .month) ? MacAccent.color(row.displayColor) : MacAccent.color(row.displayColor).opacity(0.3)).cornerRadius(3)
                                RuleMark(y: .value("当前预算", row.amount)).foregroundStyle(MacAccent.color(row.displayColor)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4,4]))
                            }.chartYScale(domain: 0...max(row.amount, points.map(\.amount).max() ?? 0) * 1.15).chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month()) } }.appMinHeight(130)
                        }
                        MacSettingsCard(title: "最近交易", icon: "doc.text", headerColor: .orange, action: AnyView(Button("查看全部") { showRecords(category: categoryName(row)) }.buttonStyle(.link).appFont(.caption, weight: .regular, design: .default)), compactHeader: true) {
                            let related = related(row)
                            if related.isEmpty { Text("本月还没有相关支出").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                            ForEach(related.prefix(3), id: \.id) { item in
                                Button { receipt = item } label: {
                                    HStack(spacing: MacUI.space(10)) { MacCategoryBadge(name: item.category, size: 31, filled: false); VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(MacFinanceNotes.visible(item.note).isEmpty ? item.category : MacFinanceNotes.visible(item.note)).appFont(.body, weight: .medium, design: .default); Text(MacDateDisplay.string(item.date)).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }; Spacer(); Text("−" + MacSettingsVisual.money(item.baseAmount) + " " + MacSettingsVisual.symbol(item.baseCurrencyCode)).appFont(.body, weight: .medium, design: .default).foregroundStyle(.red) }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                } else { MacSettingsCard(title: "预算详情", icon: "chart.bar") { Text("新建或选择预算以查看详情。").foregroundStyle(.secondary) } }
            }
        }
        .sheet(item: $editor) { row in MacBudgetEditor(budget: row, categories: categories.filter { $0.deletedAt == nil && $0.type == "Expense" }) { selectedID = $0 } }
        .sheet(item: $receipt) { MacSettingsReceipt(row: $0) }
    }
    private func addBudget() { editor = MacBudget(month: MacBudgetData.month(month), currency: currency ?? preferredCurrency, amount: 1000) }
    private func budgetSummary(allExpense: Double) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: MacUI.space(14)) {
                metric("预算总额", total, id: "budgetTotal")
                Spacer(minLength: MacUI.space(5))
                metric("已支出", allExpense, id: "budgetSpent")
                editTotalBudgetButton
            }
            VStack(alignment: .leading, spacing: MacUI.space(10)) {
                metric("预算总额", total, id: "budgetTotal")
                metric("已支出", allExpense, id: "budgetSpent")
                HStack { Spacer(); editTotalBudgetButton }
            }
        }
        .appPadding(.top, 5)
    }

    private var editTotalBudgetButton: some View {
        Button("编辑") {
            editor = current.first { $0.categoryID == nil && $0.categoryName == nil }
                ?? MacBudget(month: MacBudgetData.month(month), currency: currency ?? preferredCurrency, amount: total > 0 ? total : 1000)
        }.accessibilityIdentifier("budgetEditTotal")
    }

    private func categoryBudgetRows(spending: MacBudgetSpendingSnapshot, selectedID: UUID?) -> some View {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: MacUI.space(0)) {
                HStack {
                    Text("分类").frame(minWidth: MacUI.space(70), maxWidth: .infinity, alignment: .leading)
                    Text("预算金额").frame(width: MacUI.space(156), alignment: .trailing)
                    Text("已支出").frame(width: MacUI.space(120), alignment: .trailing)
                    Text("进度").frame(width: MacUI.space(105), alignment: .trailing)
                }
                .appFont(.caption, weight: .medium, design: .default).foregroundStyle(.secondary).appPadding(8).background(.gray.opacity(0.04))
                ForEach(rows) { row in budgetRow(row, compact: false, spending: spending, selectedID: selectedID); Divider() }
            }
            VStack(spacing: MacUI.space(9)) {
                ForEach(rows) { row in budgetRow(row, compact: true, spending: spending, selectedID: selectedID) }
            }
        }
        .overlay {
            if rows.isEmpty { ContentUnavailableView("尚未设置预算", systemImage: "chart.bar", description: Text("为所选月份添加预算。")) }
        }
    }

    @ViewBuilder
    private func budgetRow(_ row: MacBudget, compact: Bool, spending: MacBudgetSpendingSnapshot, selectedID effectiveSelection: UUID?) -> some View {
        let name = categoryName(row) ?? "总预算"
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
                        HStack { Text("预算金额").appFont(.caption, weight: .regular).foregroundStyle(.secondary); Spacer(minLength: 8); Text(amountText).appFont(.caption, weight: .medium, design: .default).lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                        HStack { Text("已支出").appFont(.caption, weight: .regular).foregroundStyle(.secondary); Spacer(minLength: 8); Text(spentText).appFont(.caption, weight: .medium, design: .default).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(fraction >= 0.8 ? .red : .primary) }
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
        .buttonStyle(.plain)
        .accessibilityRepresentation { Button(name + "预算") { selectedID = row.id }.accessibilityIdentifier("budgetRow-" + name) }
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
    @State var budget: MacBudget
    var category: String?
    var onSave: (MacBudget) -> Void
    @State private var amount = ""
    @State private var start = Date()
    @State private var error: String?
    @State private var message: String?
    var body: some View {
        MacSettingsCard(title: category.map(MacOverviewStyle.category) ?? "总预算", icon: budget.displayIcon, headerColor: MacAccent.color(budget.displayColor), action: AnyView(Toggle("启用预算", isOn: $budget.enabled).labelsHidden().toggleStyle(.switch).tint(.blue))) {
            MacSettingsRow(label: "预算金额", labelWidth: 98) { HStack { TextField("金额", text: $amount).accessibilityIdentifier("budgetInlineAmount"); Text(MacSettingsVisual.symbol(budget.currency)).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary) } }
            MacSettingsRow(label: "周期", labelWidth: 98) { HStack { Text("每月"); Spacer(); Image(systemName: "calendar").foregroundStyle(.secondary) }.appFont(.body, weight: .regular, design: .default).appPadding(10).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.2))) }
            MacSettingsRow(label: "生效月份", labelWidth: 98) { MacSettingsDateButton(date: $start, monthOnly: true) }
            MacSymbolColorPicker(icon: Binding(get: { budget.displayIcon }, set: { budget.icon = $0 }), color: Binding(get: { budget.displayColor }, set: { budget.color = $0 }), title: "预算", identifierPrefix: "budgetInlineIcon")
            VStack(alignment: .leading, spacing: MacUI.space(7)) { Text("备注（可选）").appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary); MacSettingsNoteField(placeholder: "例如：包含外出就餐、食品饮料等", text: $budget.note).accessibilityIdentifier("budgetInlineNote") }
            HStack { Text(message ?? "按月份独立保存").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary); Spacer(); Button("保存修改") { save() }.accessibilityIdentifier("budgetInlineSave") }
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red) }
        }.onAppear { amount = MacTransactionCRUD.amountEditingText(budget.amount); let parts = budget.month.split(separator: "-").compactMap { Int($0) }; start = Calendar.current.date(from: DateComponents(year: parts.first, month: parts.last, day: 1)) ?? Date() }
    }
    private func save() { do { budget.amount = try MacTransactionCRUD.editedAmount(amount, original: budget.amount); budget.month = MacBudgetData.month(start); try MacBudgetData.save(budget); error = nil; message = "已保存"; onSave(budget) } catch { self.error = MacLocalization.error(error) } }
}

struct MacBudgetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var budget: MacBudget
    var categories: [Category]
    var onSave: (UUID) -> Void
    @State private var amount = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(18)) {
            Text("预算设置 · \(budget.month)").appFont(.dialogTitle, weight: .semibold)
            Picker("范围", selection: $budget.categoryID) {
                Text("总预算").tag(UUID?.none)
                ForEach(categories, id: \.id) { Text(MacOverviewStyle.category($0.name)).tag(Optional($0.id)) }
            }.accessibilityIdentifier("budgetEditorCategory")
            HStack { TextField("预算金额", text: $amount).accessibilityIdentifier("budgetEditorAmount"); Text(budget.currency).foregroundStyle(.secondary) }
            Toggle("启用此预算", isOn: $budget.enabled)
            MacSymbolColorPicker(icon: Binding(get: { budget.displayIcon }, set: { budget.icon = $0 }), color: Binding(get: { budget.displayColor }, set: { budget.color = $0 }), title: "预算", identifierPrefix: "budgetEditorIcon")
            MacSettingsNoteField(placeholder: "备注（可选）", text: $budget.note).accessibilityIdentifier("budgetEditorNote")
            Text("仅对 \(budget.month) 生效，不改动其他月份。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("budgetEditorError") }
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("保存预算") {
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
    var row: Transaction
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(18)) {
            Text("账目详情").appFont(.dialogTitle, weight: .semibold)
            LabeledContent("分类", value: MacOverviewStyle.category(row.category))
            LabeledContent("日期", value: MacDateDisplay.string(row.date))
            LabeledContent("原币金额", value: "\(MacOverviewStyle.money(row.originalAmount)) \(row.originalCurrency)")
            LabeledContent("本位币金额", value: "\(MacOverviewStyle.money(row.baseAmount)) \(row.baseCurrencyCode)")
            LabeledContent("记账汇率", value: String(row.exchangeRateToBase))
            Text(MacFinanceNotes.visible(row.note)).foregroundStyle(.secondary)
            HStack { Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.appPadding(26).appDialog(width: 440)
    }
}
