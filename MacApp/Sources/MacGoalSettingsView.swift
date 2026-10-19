import SwiftUI
import SwiftData
import Charts

struct MacGoalSettingsView: View {
    var wide: Bool
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Query private var transactions: [Transaction]
    @Query private var deposits: [DepositRecord]
    @Query private var loans: [LoanRule]
    @Query(sort: \FinancialProfile.createdAt) private var profiles: [FinancialProfile]
    @AppStorage("base_currency") private var preferredCurrency = "USD"
    @AppStorage("v2_goal_presentation") private var presentationBytes = Data()
    @State private var filter = "全部目标"
    @State private var selectedID: UUID?
    @State private var adding = false
    @State private var range = "1年"
    @State private var removing = false
    @State private var error: String?
    private var currency: String? { try? MacCurrency.ledgerCurrency(in: context, preferred: preferredCurrency) }
    private var profile: FinancialProfile? { profiles.first { $0.deletedAt == nil } }
    private var netWorth: Double { MacFinancialSettings.snapshot(profile: profile, transactions: transactions.filter { $0.date <= Date() }, loans: loans, deposits: deposits, currency: currency ?? preferredCurrency, asOf: Date()).netWorth }
    private var baseline: Double { Goal.baselineNetWorth(from: profile) }
    private var presentation: [String: MacGoalPresentation] { (try? JSONDecoder().decode([String: MacGoalPresentation].self, from: presentationBytes)) ?? [:] }
    private var activeGoals: [Goal] { goals.filter { $0.deletedAt == nil } }
    private func meta(_ goal: Goal) -> MacGoalPresentation { presentation[goal.id.uuidString] ?? .init() }
    private func status(_ row: Goal) -> String { row.isPaused ? "已暂停" : row.isAccomplished || (currency != nil && row.isCompleted(currentNetWorth: netWorth, baselineNetWorth: baseline)) ? "已完成" : "进行中" }
    private var rows: [Goal] { activeGoals.filter { filter == "全部目标" || status($0) == filter } }
    private var selected: Goal? { rows.first { $0.id == selectedID } ?? rows.first }
    private func progress(_ row: Goal) -> Double { currency == nil ? 0 : row.clampedProgressValue(currentNetWorth: netWorth, baselineNetWorth: baseline) }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            HStack { Spacer(); Button("新建目标", systemImage: "plus") { adding = true }.disabled(currency == nil).accessibilityIdentifier("settingsGoalAdd") }.padding(.top, MacUI.space(wide ? -64 : 0)).padding(.bottom, MacUI.space(wide ? 12 : 0))
            MacSettingsColumns(wide: wide) {
                MacSettingsCard(title: "", icon: "") {
                    VStack(spacing: MacUI.space(7)) {
                        HStack(spacing: MacUI.space(2)) {
                            ForEach(["全部目标", "进行中", "已完成", "已暂停"], id: \.self) { title in
                                Button { filter = title } label: { Text(title + " (" + String(title == "全部目标" ? activeGoals.count : activeGoals.filter { status($0) == title }.count) + ")").appFont(.caption, weight: .semibold, design: .default).lineLimit(1).frame(maxWidth: .infinity).appMinHeight(36).foregroundStyle(filter == title ? MacSettingsVisual.accent : .secondary).background(filter == title ? MacSettingsVisual.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain)
                            }
                        }.appPadding(3).background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).accessibilityIdentifier("settingsGoalFilter")
                        if rows.isEmpty { ContentUnavailableView("暂无符合条件的目标", systemImage: "target") }
                        ForEach(rows, id: \.id) { row in
                            Button { selectedID = row.id } label: {
                                HStack(alignment: .top, spacing: MacUI.space(13)) {
                                    MacSettingsIcon(symbol: meta(row).icon, color: MacAccent.color(meta(row).color), size: 44)
                                    VStack(alignment: .leading, spacing: MacUI.space(5)) {
                                        HStack(alignment: .top, spacing: MacUI.space(8)) {
                                            Text(row.title).appFont(.body, weight: .semibold, design: .default).lineLimit(2).truncationMode(.tail)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(MacSettingsVisual.money(row.targetAmount) + " " + MacSettingsVisual.symbol(currency ?? ""))
                                                .appFont(.body, weight: .semibold, design: .default).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                        }
                                        HStack { Text(meta(row).note).lineLimit(1); Spacer(); Text(String(format: "%.1f%%", progress(row) * 100)).fontWeight(.medium) }.appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                                        MacSettingsProgress(value: progress(row), color: .green, height: 8)
                                        HStack { Text(MacSettingsVisual.money(row.targetAmount * progress(row)) + " / " + MacSettingsVisual.money(row.targetAmount) + " " + MacSettingsVisual.symbol(currency ?? "")); Spacer(); if status(row) != "进行中" { Text(status(row)).foregroundStyle(row.isPaused ? .orange : .green).appPadding(.horizontal, 6).appPadding(.vertical, 2).background((row.isPaused ? Color.orange : .green).opacity(0.1), in: Capsule()) }; Text(row.deadline.map(MacDisplayPreferences.month) ?? "未设日期") }.appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                                    }
                                }.appPadding(.horizontal, 10).appPadding(.vertical, 8).background(selected?.id == row.id ? .gray.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityRepresentation { Button(row.title + " " + status(row)) { selectedID = row.id }.accessibilityIdentifier("settingsGoalRow-" + row.title) }
                            if row.id != rows.last?.id { Divider() }
                        }
                    }
                }
            } right: {
                if let goal = selected {
                    VStack(spacing: MacUI.space(14)) {
                        MacGoalInlineEditor(goal: goal, currency: currency, netWorth: netWorth, baseline: baseline).id(goal.id)
                        MacSettingsCard(title: "目标趋势", icon: "chart.bar", headerColor: .blue, action: AnyView(MacSettingsSegments(selection: $range, options: ["6个月", "1年", "全部"]).frame(width: MacUI.space(190)))) {
                            if MacSettingsVisual.preview {
                                let count = range == "6个月" ? 6 : 12
                                Chart(0..<count, id: \.self) { index in
                                    BarMark(x: .value("月份", Calendar.current.date(byAdding: .month, value: index - count + 1, to: Date())!, unit: .month), y: .value("演示进展", max(0, netWorth * (0.25 + Double(index) / Double(count) * 0.75)))).foregroundStyle(.blue.opacity(0.35)).cornerRadius(2)
                                }.chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month()) } }.frame(height: MacUI.space(145))
                            } else { ContentUnavailableView("暂无历史记录", systemImage: "chart.bar", description: Text("已有净资产进度显示在上方。 ")).frame(height: MacUI.space(145)) }
                        }
                    }
                } else { MacSettingsCard(title: "目标详情", icon: "target") { Text("选择或创建财务目标。").foregroundStyle(.secondary) } }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .sheet(isPresented: $adding) { if let currency { MacFinanceEditor(panel: .goals, currency: currency, onSaved: {}) } }
    }
}

struct MacGoalInlineEditor: View {
    var goal: Goal
    var currency: String?
    var netWorth: Double
    var baseline: Double
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var amount = ""
    @State private var deadline = Date()
    @State private var hasDeadline = true
    @State private var presentation = MacGoalPresentation()
    @State private var error: String?
    @State private var saved = false
    private var progress: Double { goal.clampedProgressValue(currentNetWorth: netWorth, baselineNetWorth: baseline) }
    private var gap: Double { max(0, (goal.includesCurrentAssets ? goal.targetAmount : goal.creationNetWorth + goal.targetAmount) - netWorth) }
    private var status: String { goal.isPaused ? "已暂停" : goal.isAccomplished || goal.isCompleted(currentNetWorth: netWorth, baselineNetWorth: baseline) ? "已完成" : "进行中" }
    private var months: Int { max(0, Calendar.current.dateComponents([.month], from: Date(), to: goal.deadline ?? Date()).month ?? 0) }
    var body: some View {
        MacSettingsCard(title: goal.title, icon: presentation.icon, subtitle: presentation.note, headerColor: MacAccent.color(presentation.color), action: AnyView(Toggle("目标启用状态", isOn: Binding(get: { !goal.isPaused }, set: { active in goal.isPaused = !active; goal.updatedAt = Date(); do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription } })).labelsHidden().toggleStyle(.switch).tint(.blue).accessibilityIdentifier("settingsGoalPause")), heading: AnyView(TextField("目标名称", text: $title).textFieldStyle(.plain).appFont(.section, weight: .semibold, design: .default).accessibilityIdentifier("goalInlineTitle"))) {
            MacSettingsRow(label: "目标金额", labelWidth: 90) { HStack { TextField("金额", text: $amount).accessibilityIdentifier("goalInlineAmount"); Text(MacSettingsVisual.symbol(currency ?? "")).foregroundStyle(.secondary) } }
            MacSettingsRow(label: "当前净资产", labelWidth: 90) { Text(MacSettingsVisual.money(netWorth) + " " + MacSettingsVisual.symbol(currency ?? "")).appFont(.body, weight: .medium, design: .default).frame(maxWidth: .infinity, alignment: .leading).appPadding(.horizontal, 12).appMinHeight(36).background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)) }
            MacSettingsRow(label: "目标日期", labelWidth: 90) { HStack { if hasDeadline { MacSettingsDateButton(date: $deadline, monthOnly: true) } else { Button("设置目标日期") { hasDeadline = true } }; Menu { Button("不设截止日期") { hasDeadline = false }; Button("设置日期") { hasDeadline = true } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize() } }
            MacSettingsRow(label: "优先级", labelWidth: 90) { MacSettingsMenu(selection: $presentation.priority, options: [("高","高"), ("普通","普通"), ("低","低")]).accessibilityIdentifier("goalPriorityMenu") }
            MacGoalIconPicker(presentation: $presentation, identifierPrefix: "settingsGoalIconOption")
            VStack(alignment: .leading, spacing: MacUI.space(7)) { Text("备注（可选）").appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary); MacSettingsNoteField(placeholder: "为这个目标添加备注…", text: $presentation.note).accessibilityIdentifier("goalInlineNote") }
            HStack { Text("目标进度").appFont(.body, weight: .semibold, design: .default); Spacer(); Text(String(format: "%.1f%%", progress * 100)).appFont(.dialogTitle, weight: .bold, design: .default).accessibilityIdentifier("settingsGoalProgress") }
            MacSettingsProgress(value: progress, color: .green, height: 10)
            HStack { Text(goal.includesCurrentAssets ? "净资产目标" : "新增净资产目标"); Spacer(); Text(status).accessibilityIdentifier("settingsGoalStatus") }.appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).accessibilityRepresentation { Text(status).accessibilityIdentifier("settingsGoalStatus") }
            HStack(spacing: MacUI.space(8)) { stat(MacSettingsVisual.money(gap) + " " + MacSettingsVisual.symbol(currency ?? ""), "距目标差额"); stat("\(months) 个月", "剩余时间"); stat(months > 0 ? MacSettingsVisual.money(gap / Double(months)) : "—", "参考每月增长") }
            HStack { Text(saved ? "已保存" : "进度按净资产自动计算").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary); Spacer(); Button("保存修改") { save() }.disabled(currency == nil).accessibilityIdentifier("settingsGoalSave") }
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red) }
        }.onAppear { title = goal.title; amount = String(format: "%.0f", goal.targetAmount); deadline = goal.deadline ?? Calendar.current.date(byAdding: .year, value: 1, to: Date())!; hasDeadline = goal.deadline != nil; let all: [String: MacGoalPresentation] = MacSettingsStore.load("v2_goal_presentation", fallback: [:]); presentation = all[goal.id.uuidString] ?? .init() }
    }
    private func stat(_ value: String, _ label: String) -> some View { VStack(spacing: MacUI.space(6)) { Text(value).appFont(.amount, weight: .semibold, design: .default).fixedSize(horizontal: false, vertical: true); Text(label).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).appPadding(.vertical, 11).background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 7)) }
    private func save() {
        do {
            let title = try MacTransactionCRUD.validatedCategory(title), amount = try MacTransactionCRUD.amount(amount)
            guard presentation.note.count <= 200 else { throw MacSettingsFailure.invalid("备注请保持在200字以内") }
            var all: [String: MacGoalPresentation] = MacSettingsStore.load("v2_goal_presentation", fallback: [:]); all[goal.id.uuidString] = presentation
            let bytes = try JSONEncoder().encode(all)
            goal.title = title; goal.targetAmount = amount; goal.deadline = hasDeadline ? deadline : nil; goal.updatedAt = Date()
            try context.save(); MacPreferences.defaults.set(bytes, forKey: "v2_goal_presentation"); saved = true; error = nil
        } catch { context.rollback(); self.error = MacLocalization.error(error) }
    }
}
