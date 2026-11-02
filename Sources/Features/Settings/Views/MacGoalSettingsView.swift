import SwiftUI
import SwiftData
import Charts

struct MacGoalSettingsView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
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
            HStack { Spacer(); Button(L10n.text("mac.goalSettingsView.body.da6caff0fb"), systemImage: "plus") { adding = true }.disabled(currency == nil).accessibilityIdentifier("settingsGoalAdd") }.padding(.top, MacUI.space(wide ? -64 : 0)).padding(.bottom, MacUI.space(wide ? 12 : 0))
            MacSettingsColumns(wide: wide) {
                MacSettingsCard(title: "", icon: "") {
                    VStack(spacing: MacUI.space(7)) {
                        HStack(spacing: MacUI.space(2)) {
                            ForEach(["全部目标", "进行中", "已完成", "已暂停"], id: \.self) { title in
                                Button { filter = title } label: { Text(L10n.builtIn(title) + " (" + String(title == "全部目标" ? activeGoals.count : activeGoals.filter { status($0) == title }.count) + ")").appFont(.caption, weight: .semibold, design: .default).lineLimit(1).frame(maxWidth: .infinity).appMinHeight(36).foregroundStyle(filter == title ? MacSettingsVisual.accent : .secondary).background(filter == title ? MacSettingsVisual.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(MacInteractiveButtonStyle())
                            }
                        }.appPadding(3).background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).accessibilityIdentifier("settingsGoalFilter")
                        if rows.isEmpty { ContentUnavailableView(L10n.text("mac.goalSettingsView.ContentUnavailableView.3dbe9f0f1f"), systemImage: "target") }
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
                                        HStack { Text(MacSettingsVisual.money(row.targetAmount * progress(row)) + " / " + MacSettingsVisual.money(row.targetAmount) + " " + MacSettingsVisual.symbol(currency ?? "")); Spacer(); if status(row) != "进行中" { Text(L10n.builtIn(status(row))).foregroundStyle(row.isPaused ? .orange : .green).appPadding(.horizontal, 6).appPadding(.vertical, 2).background((row.isPaused ? Color.orange : .green).opacity(0.1), in: Capsule()) }; Text(MacGoalTargetDate.label(row)) }.appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                                    }
                                }.appPadding(.horizontal, 10).appPadding(.vertical, 8).background(selected?.id == row.id ? .gray.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                            }.buttonStyle(MacInteractiveButtonStyle()).accessibilityRepresentation { Button(row.title + " " + L10n.builtIn(status(row))) { selectedID = row.id }.accessibilityIdentifier("settingsGoalRow-" + row.title) }
                            if row.id != rows.last?.id { Divider() }
                        }
                    }
                }
            } right: {
                if let goal = selected {
                    VStack(spacing: MacUI.space(14)) {
                        MacGoalInlineEditor(goal: goal, currency: currency, netWorth: netWorth, baseline: baseline).id(goal.id)
                        MacSettingsCard(title: L10n.text("mac.goalSettingsView.MacSettingsColumns.22c2037c96"), icon: "chart.bar", headerColor: .blue, action: MacSettingsVisual.preview ? AnyView(MacSettingsSegments(selection: $range, options: ["6个月", "1年", "全部"]).frame(width: MacUI.space(190))) : nil) {
                            if MacSettingsVisual.preview {
                                let count = range == "6个月" ? 6 : 12
                                Chart(0..<count, id: \.self) { index in
                                    BarMark(x: .value(L10n.text("mac.goalSettingsView.BarMark.a27822d135"), Calendar.current.date(byAdding: .month, value: index - count + 1, to: Date())!, unit: .month), y: .value(L10n.text("mac.goalSettingsView.BarMark.db86cb3952"), max(0, netWorth * (0.25 + Double(index) / Double(count) * 0.75)))).foregroundStyle(.blue.opacity(0.35)).cornerRadius(2)
                                }.chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month()) } }.frame(height: MacUI.space(145))
                            } else { ContentUnavailableView(L10n.text("mac.goalSettingsView.ContentUnavailableView.88f60ba89c"), systemImage: "chart.bar", description: Text(L10n.text("mac.goalSettingsView.ContentUnavailableView.38c218d18e"))).frame(height: MacUI.space(145)) }
                        }
                    }
                } else { MacSettingsCard(title: L10n.text("mac.goalSettingsView.MacSettingsColumns.10886293c5"), icon: "target") { Text(L10n.text("mac.goalSettingsView.MacSettingsColumns.70cb43cf01")).foregroundStyle(.secondary) } }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .sheet(isPresented: $adding) { if let currency { MacFinanceEditor(panel: .goals, currency: currency, onSaved: {}) } }
    }
}

struct MacGoalInlineEditor: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var goal: Goal
    var currency: String?
    var netWorth: Double
    var baseline: Double
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var amount = ""
    @State private var deadline = Date()
    @State private var hasDeadline = true
    @State private var timePrecision: TargetDatePrecision = .day
    @State private var presentation = MacGoalPresentation()
    @State private var error: String?
    @State private var saved = false
    private struct Draft {
        let title: String; let amount: String; let deadline: Date; let hasDeadline: Bool
        let precision: TargetDatePrecision; let presentation: MacGoalPresentation
        let revision: Date; let currency: String?; let generation: Int
    }
    @State private var discardDraft = false
    @State private var loadedRevision = Date.distantPast
    @State private var loadedCurrency: String?
    @State private var loadedGeneration = 0
    private var draftKey: String { MacEditorDraftStore.key("goal", goal.id.uuidString, context: context) }
    private var dirty: Bool { title != goal.title || amount != MacTransactionCRUD.amountEditingText(goal.targetAmount) || hasDeadline != (goal.deadline != nil) || (hasDeadline && (deadline != goal.targetTime.resolvedDate() || timePrecision != goal.targetTime.precision)) || presentation != currentPresentation }
    private var currentPresentation: MacGoalPresentation { let all: [String: MacGoalPresentation] = MacSettingsStore.load("v2_goal_presentation", fallback: [:]); return all[goal.id.uuidString] ?? .init() }
    private func loadDraft(discard: Bool = false) {
        if discard { MacEditorDraftStore.shared.remove(draftKey) }
        if let d = MacEditorDraftStore.shared.load(draftKey, as: Draft.self) {
            title=d.title; amount=d.amount; deadline=d.deadline; hasDeadline=d.hasDeadline; timePrecision=d.precision
            presentation=d.presentation; loadedRevision=d.revision; loadedCurrency=d.currency; loadedGeneration=d.generation
        } else {
            title=goal.title; amount=MacTransactionCRUD.amountEditingText(goal.targetAmount)
            deadline=goal.targetTime.resolvedDate() ?? Calendar.current.date(byAdding:.year,value:1,to:Date())!
            hasDeadline=goal.deadline != nil; timePrecision=goal.targetTime.precision; presentation=currentPresentation
            loadedRevision=goal.updatedAt; loadedCurrency=currency; loadedGeneration=MacEditorDraftStore.shared.generation
        }
    }
    private func keepDraft() {
        MacEditorDraftStore.shared.save(Draft(title:title,amount:amount,deadline:deadline,hasDeadline:hasDeadline,precision:timePrecision,presentation:presentation,revision:loadedRevision,currency:loadedCurrency,generation:loadedGeneration),key:draftKey,generation:loadedGeneration)
    }
    private var progress: Double { goal.clampedProgressValue(currentNetWorth: netWorth, baselineNetWorth: baseline) }
    private var gap: Double { max(0, (goal.includesCurrentAssets ? goal.targetAmount : goal.creationNetWorth + goal.targetAmount) - netWorth) }
    private var status: String { L10n.builtIn(goal.isPaused ? "已暂停" : goal.isAccomplished || goal.isCompleted(currentNetWorth: netWorth, baselineNetWorth: baseline) ? "已完成" : "进行中") }
    private var months: Int? { goal.targetTime.remainingMonths(from: Date()) }
    var body: some View {
        MacSettingsCard(title: goal.title, icon: presentation.icon, subtitle: presentation.note, headerColor: MacAccent.color(presentation.color), action: AnyView(Toggle(L10n.text("mac.goalSettingsView.AnyView.d0c0721383"), isOn: Binding(get: { !goal.isPaused }, set: { active in goal.isPaused = !active; goal.updatedAt = Date(); do { try context.save(); loadedRevision = goal.updatedAt } catch { context.rollback(); self.error = error.localizedDescription } })).labelsHidden().toggleStyle(.switch).tint(.blue).accessibilityIdentifier("settingsGoalPause")), heading: AnyView(TextField(L10n.text("mac.goalSettingsView.AnyView.cb9877f3a9"), text: $title).textFieldStyle(.plain).appFont(.section, weight: .semibold, design: .default).accessibilityIdentifier("goalInlineTitle"))) {
            MacSettingsRow(label: L10n.text("mac.goalSettingsView.body.83ea3be5cc"), labelWidth: 90) { HStack { MacNumericInput(text: $amount, identifier: "goalInlineAmount").frame(minHeight: 24).appFormControl(); Text(MacSettingsVisual.symbol(currency ?? "")).foregroundStyle(.secondary) } }
            MacSettingsRow(label: L10n.text("mac.goalSettingsView.body.8d1288c011"), labelWidth: 90) { Text(MacSettingsVisual.money(netWorth) + " " + MacSettingsVisual.symbol(currency ?? "")).appFont(.body, weight: .medium, design: .default).frame(maxWidth: .infinity, alignment: .leading).appPadding(.horizontal, 12).appMinHeight(36).background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)) }
            MacSettingsRow(label: L10n.text("mac.goalSettingsView.body.bf2cb28701"), labelWidth: 90) { MacGoalTargetTimeField(hasDate: $hasDeadline, precision: $timePrecision, date: $deadline, identifier: "settingsGoalTime") }
            MacSettingsRow(label: L10n.text("mac.goalSettingsView.body.565d64601d"), labelWidth: 90) { MacSettingsMenu(selection: $presentation.priority, options: [(L10n.text("mac.goalSettingsView.MacSettingsMenu.b1c27820fe"),"高"), (L10n.text("mac.goalSettingsView.MacSettingsMenu.de907d10df"),"普通"), (L10n.text("mac.goalSettingsView.MacSettingsMenu.aa9e366f68"),"低")]).accessibilityIdentifier("goalPriorityMenu") }
            MacGoalIconPicker(presentation: $presentation, identifierPrefix: "settingsGoalIconOption")
            VStack(alignment: .leading, spacing: MacUI.space(7)) { Text(L10n.text("mac.goalSettingsView.body.b405227c7e")).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary); MacSettingsNoteField(placeholder: L10n.text("mac.goalSettingsView.MacSettingsNoteField.62ec9ceb3b"), text: $presentation.note).accessibilityIdentifier("goalInlineNote") }
            HStack { Text(L10n.text("mac.goalSettingsView.body.b0763fd1e5")).appFont(.body, weight: .semibold, design: .default); Spacer(); Text(String(format: "%.1f%%", progress * 100)).appFont(.dialogTitle, weight: .bold, design: .default).accessibilityIdentifier("settingsGoalProgress") }
            MacSettingsProgress(value: progress, color: .green, height: 10)
            HStack { Text(goal.includesCurrentAssets ? L10n.text("mac.goalSettingsView.body.8b61957eea") : L10n.text("mac.goalSettingsView.body.c552c0838c")); Spacer(); Text(status).accessibilityIdentifier("settingsGoalStatus") }.appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).accessibilityRepresentation { Text(status).accessibilityIdentifier("settingsGoalStatus") }
            MacAdaptiveEqualCardLayout(spacing: MacUI.space(8), minimumCardWidth: 0) {
                stat(MacSettingsVisual.money(gap) + " " + MacSettingsVisual.symbol(currency ?? ""), L10n.text("mac.goalSettingsView.stat.c7e9ef171c"), identifier: "goalGapAmount")
                stat(months.map { $0 > 0 ? L10n.format("mac.goalSettingsView.stat.f6f52074ad", "\($0)") : L10n.text("mac.goalSettingsView.stat.f21192d465") } ?? L10n.text("mac.goalSettingsView.stat.2f5f1d6fbf"), L10n.text("mac.goalSettingsView.stat.7d708f9ab3"), identifier: "goalPlanningTime")
                stat(months.flatMap { $0 > 0 ? MacSettingsVisual.money(gap / Double($0)) : nil } ?? "—", L10n.text("mac.goalSettingsView.stat.213647e1f3"), identifier: "goalMonthlyGrowth")
            }
            HStack { Text(dirty ? L10n.text("mac.goalSettingsView.body.58937dd581") : saved ? L10n.text("mac.goalSettingsView.body.1bd91a7d0c") : L10n.text("mac.goalSettingsView.body.a66d2e029f")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary); Spacer(); Button(L10n.text("mac.goalSettingsView.body.991bb7cfe5")) { save() }.disabled(currency == nil).accessibilityIdentifier("settingsGoalSave") }
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red); Button(L10n.text("mac.goalSettingsView.body.f057369770")) { discardDraft = true } }
        }.onAppear { loadDraft() }.onDisappear { keepDraft() }
        .confirmationDialog(L10n.text("mac.goalSettingsView.body.46c8da8a29"), isPresented: $discardDraft) {
            Button(L10n.text("mac.goalSettingsView.body.ab0eba1876"), role: .destructive) { loadDraft(discard: true); error = nil }
        }

    }
    private func stat(_ value: String, _ label: String, identifier: String) -> some View {
        VStack(spacing: MacUI.space(6)) {
            Text(value).appFont(.amount, weight: .semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .fixedSize(horizontal: true, vertical: false).accessibilityIdentifier(identifier)
            Text(label).appFont(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).appPadding(.vertical, 11)
            .background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
    }
    private func save() {
        do {
            guard loadedRevision == goal.updatedAt, loadedCurrency == currency, loadedGeneration == MacEditorDraftStore.shared.generation else { throw MacSettingsFailure.invalid(L10n.text("mac.goalSettingsView.save.4ec1589fe2")) }
            let title = try MacTransactionCRUD.validatedCategory(title), amount = try MacTransactionCRUD.editedAmount(amount, original: goal.targetAmount)
            guard presentation.note.count <= 200 else { throw MacSettingsFailure.invalid(L10n.text("mac.goalSettingsView.save.57a2385b39")) }
            var all: [String: MacGoalPresentation] = MacSettingsStore.load("v2_goal_presentation", fallback: [:]); all[goal.id.uuidString] = presentation
            let bytes = try JSONEncoder().encode(all)
            let timeValue = hasDeadline ? GoalTargetTime.capturedValue(deadline, precision: timePrecision) : nil
            guard timeValue == nil || GoalTargetTime.components(timeValue!, precision: timePrecision) != nil else { throw MacSettingsFailure.invalid(L10n.text("mac.goalSettingsView.save.520803061b")) }
            try MacRecoveryJournal.perform(in: context) {
            goal.title = title; goal.targetAmount = amount; goal.deadline = hasDeadline ? deadline : nil; goal.targetDatePrecisionRaw = hasDeadline ? timePrecision.rawValue : nil; goal.targetDateValueRaw = timeValue; goal.updatedAt = Date()
            try context.save(); MacPreferences.defaults.set(bytes, forKey: "v2_goal_presentation"); loadedRevision = goal.updatedAt; MacEditorDraftStore.shared.remove(draftKey); saved = true; error = nil
            }
        } catch { context.rollback(); self.error = MacLocalization.error(error) }
    }
}
