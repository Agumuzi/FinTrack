import SwiftUI
import SwiftData

struct MacGoalSettingsView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var wide: Bool
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Query private var transactions: [Transaction]
    @Query private var deposits: [DepositRecord]
    @Query private var loans: [LoanRule]
    @Query private var recurring: [RecurringTransaction]
    @Query(sort: \FinancialProfile.createdAt) private var profiles: [FinancialProfile]
    @AppStorage("base_currency") private var preferredCurrency = "USD"
    @AppStorage("v2_goal_presentation") private var presentationBytes = Data()
    @State private var filter = "全部目标"
    @State private var selectedID: UUID?
    @State private var adding = false
    private var currencyResolution: MacLedgerCurrencyResolution {
        MacCurrency.resolveLedgerCurrency(transactions: transactions, deposits: deposits, loans: loans,
                                          recurring: recurring, preferred: preferredCurrency)
    }
    private var presentation: [String: MacGoalPresentation] { (try? JSONDecoder().decode([String: MacGoalPresentation].self, from: presentationBytes)) ?? [:] }
    private var activeGoals: [Goal] { goals.filter { $0.deletedAt == nil } }
    private func meta(_ goal: Goal) -> MacGoalPresentation { presentation[goal.id.uuidString] ?? .init() }
    var body: some View {
        let resolution = currencyResolution
        let currency = resolution.displayCurrency
        let writeCurrency = resolution.matchesPreference ? currency : nil
        let netWorth = currency.map {
            MacFinancialSettings.snapshot(profile: MacLiquidity.preferredProfile(in: profiles), transactions: transactions, loans: loans, deposits: deposits, currency: $0, asOf: Date()).netWorth
        }
        let statuses = Dictionary(grouping: activeGoals) { $0.progressStatus(netWorth: netWorth) }
        let rows = filter == "全部目标" ? activeGoals : statuses[filter, default: []]
        let selected = rows.first { $0.id == selectedID } ?? rows.first
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            HStack { Spacer(); Button(L10n.text("mac.goalSettingsView.body.da6caff0fb"), systemImage: "plus") { adding = true }.disabled(writeCurrency == nil).accessibilityIdentifier("settingsGoalAdd") }.padding(.top, MacUI.space(wide ? -64 : 0)).padding(.bottom, MacUI.space(wide ? 12 : 0))
            MacSettingsColumns(wide: wide) {
                MacSettingsCard(title: "", icon: "") {
                    VStack(spacing: MacUI.space(7)) {
                        HStack(spacing: MacUI.space(2)) {
                            ForEach(["全部目标", "进行中", "已完成", "已暂停"], id: \.self) { title in
                                Button { filter = title } label: { Text(L10n.builtIn(title) + " (" + String(title == "全部目标" ? activeGoals.count : statuses[title, default: []].count) + ")").appFont(.caption, weight: .semibold, design: .default).lineLimit(1).frame(maxWidth: .infinity).appMinHeight(36).foregroundStyle(filter == title ? MacSettingsVisual.accent : .secondary).background(filter == title ? MacSettingsVisual.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(MacInteractiveButtonStyle())
                            }
                        }.appPadding(3).background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).accessibilityIdentifier("settingsGoalFilter")
                        if rows.isEmpty { ContentUnavailableView(L10n.text("mac.goalSettingsView.ContentUnavailableView.3dbe9f0f1f"), systemImage: "target") }
                        ForEach(rows, id: \.id) { row in
                            let status = row.progressStatus(netWorth: netWorth)
                            let progress = netWorth.map { row.progress(netWorth: $0).fraction } ?? 0
                            let percent = netWorth.map { "\(row.progress(netWorth: $0).percent)%" } ?? "—"
                            let current = netWorth.map { MacSettingsVisual.money(row.progress(netWorth: $0).current) } ?? "—"
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
                                        HStack { Text(meta(row).note).lineLimit(1); Spacer(); Text(percent).fontWeight(.medium) }.appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                                        MacSettingsProgress(value: progress, color: .green, height: 8)
                                        HStack { Text(current + " / " + MacSettingsVisual.money(row.targetAmount) + " " + MacSettingsVisual.symbol(currency ?? "")); Spacer(); if status != "进行中" { Text(L10n.builtIn(status)).foregroundStyle(row.isPaused ? .orange : .green).appPadding(.horizontal, 6).appPadding(.vertical, 2).background((row.isPaused ? Color.orange : .green).opacity(0.1), in: Capsule()) }; Text(MacGoalTargetDate.label(row)) }.appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                                    }
                                }.appPadding(.horizontal, 10).appPadding(.vertical, 8).background(selected?.id == row.id ? .gray.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                            }.buttonStyle(MacInteractiveButtonStyle()).accessibilityRepresentation { Button(row.title + " · " + L10n.builtIn(status) + " · " + current + " / " + MacSettingsVisual.money(row.targetAmount) + " " + (currency ?? "") + " · " + percent) { selectedID = row.id }.accessibilityIdentifier("settingsGoalRow-" + row.title) }
                            if row.id != rows.last?.id { Divider() }
                        }
                    }
                }
            } right: {
                if let goal = selected {
                    MacGoalInlineEditor(goal: goal, currency: currency, canSave: writeCurrency != nil, netWorth: netWorth).id(goal.id)
                } else { MacSettingsCard(title: L10n.text("mac.goalSettingsView.MacSettingsColumns.10886293c5"), icon: "target") { Text(L10n.text("mac.goalSettingsView.MacSettingsColumns.70cb43cf01")).foregroundStyle(.secondary) } }
            }
        }
        .sheet(isPresented: $adding) { if let currency = writeCurrency { MacFinanceEditor(panel: .goals, currency: currency, onSaved: {}) } }
    }
}

struct MacGoalInlineEditor: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var goal: Goal
    var currency: String?
    var canSave: Bool
    var netWorth: Double?
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
    private var progress: Double { netWorth.map { goal.progress(netWorth: $0).fraction } ?? 0 }
    private var gap: Double? { netWorth.map { goal.progress(netWorth: $0).remaining } }
    private var status: String { L10n.builtIn(goal.progressStatus(netWorth: netWorth)) }
    private func amountLabel(_ amount: Double?) -> String {
        amount.map { MacSettingsVisual.money($0) + " " + (currency ?? "") } ?? "—"
    }
    private var months: Int? { goal.targetTime.remainingMonths(from: Date()) }
    var body: some View {
        MacSettingsCard(title: goal.title, icon: presentation.icon, subtitle: presentation.note, headerColor: MacAccent.color(presentation.color), action: AnyView(Toggle(L10n.text("mac.goalSettingsView.AnyView.d0c0721383"), isOn: Binding(get: { !goal.isPaused }, set: { active in guard canSave else { return }; goal.isPaused = !active; goal.updatedAt = Date(); do { try context.save(); loadedRevision = goal.updatedAt } catch { context.rollback(); self.error = error.localizedDescription } })).labelsHidden().toggleStyle(.switch).tint(.blue).accessibilityIdentifier("settingsGoalPause").disabled(!canSave)), heading: AnyView(TextField(L10n.text("mac.goalSettingsView.AnyView.cb9877f3a9"), text: $title).textFieldStyle(.plain).appFont(.section, weight: .semibold, design: .default).accessibilityIdentifier("goalInlineTitle"))) {
            MacSettingsRow(label: L10n.text("mac.goalSettingsView.body.83ea3be5cc"), labelWidth: 90) { HStack { MacNumericInput(text: $amount, identifier: "goalInlineAmount").frame(minHeight: 24).appFormControl(); Text(MacSettingsVisual.symbol(currency ?? "")).foregroundStyle(.secondary) } }
            MacSettingsRow(label: L10n.text(goal.includesCurrentAssets ? "mac.goalSettingsView.body.8d1288c011" : "goal.currentGrowth"), labelWidth: 90) { Text(amountLabel(netWorth.map { goal.progress(netWorth: $0).current })).appFont(.body, weight: .medium, design: .default).frame(maxWidth: .infinity, alignment: .leading).appPadding(.horizontal, 12).appMinHeight(36).background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)) }
            MacSettingsRow(label: L10n.text("mac.goalSettingsView.body.bf2cb28701"), labelWidth: 90) { MacGoalTargetTimeField(hasDate: $hasDeadline, precision: $timePrecision, date: $deadline, identifier: "settingsGoalTime") }
            MacSettingsRow(label: L10n.text("mac.goalSettingsView.body.565d64601d"), labelWidth: 90) { MacSettingsMenu(selection: $presentation.priority, options: [(L10n.text("mac.goalSettingsView.MacSettingsMenu.b1c27820fe"),"高"), (L10n.text("mac.goalSettingsView.MacSettingsMenu.de907d10df"),"普通"), (L10n.text("mac.goalSettingsView.MacSettingsMenu.aa9e366f68"),"低")]).accessibilityIdentifier("goalPriorityMenu") }
            MacGoalIconPicker(presentation: $presentation, identifierPrefix: "settingsGoalIconOption")
            VStack(alignment: .leading, spacing: MacUI.space(7)) { Text(L10n.text("mac.goalSettingsView.body.b405227c7e")).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary); MacSettingsNoteField(placeholder: L10n.text("mac.goalSettingsView.MacSettingsNoteField.62ec9ceb3b"), text: $presentation.note).accessibilityIdentifier("goalInlineNote") }
            HStack { Text(L10n.text("mac.goalSettingsView.body.b0763fd1e5")).appFont(.body, weight: .semibold, design: .default); Spacer(); Text(netWorth.map { "\(goal.progress(netWorth: $0).percent)%" } ?? "—").appFont(.dialogTitle, weight: .bold, design: .default).accessibilityIdentifier("settingsGoalProgress") }
            MacSettingsProgress(value: progress, color: .green, height: 10)
            HStack { Text(goal.includesCurrentAssets ? L10n.text("mac.goalSettingsView.body.8b61957eea") : L10n.text("mac.goalSettingsView.body.c552c0838c")); Spacer(); Text(status).accessibilityIdentifier("settingsGoalStatus") }.appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).accessibilityRepresentation { Text(status).accessibilityIdentifier("settingsGoalStatus") }
            MacAdaptiveEqualCardLayout(spacing: MacUI.space(8), minimumCardWidth: 0) {
                stat(amountLabel(gap), L10n.text("mac.goalSettingsView.stat.c7e9ef171c"), identifier: "goalGapAmount")
                stat(months.map { $0 > 0 ? L10n.format("mac.goalSettingsView.stat.f6f52074ad", "\($0)") : L10n.text("mac.goalSettingsView.stat.f21192d465") } ?? L10n.text("mac.goalSettingsView.stat.2f5f1d6fbf"), L10n.text("mac.goalSettingsView.stat.7d708f9ab3"), identifier: "goalPlanningTime")
                stat(amountLabel(months.flatMap { count in count > 0 ? gap.map { $0 / Double(count) } : nil }), L10n.text("mac.goalSettingsView.stat.213647e1f3"), identifier: "goalMonthlyGrowth")
            }
            HStack { Text(dirty ? L10n.text("mac.goalSettingsView.body.58937dd581") : saved ? L10n.text("mac.goalSettingsView.body.1bd91a7d0c") : L10n.text("mac.goalSettingsView.body.a66d2e029f")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary); Spacer(); Button(L10n.text("mac.goalSettingsView.body.991bb7cfe5")) { save() }.disabled(!canSave).accessibilityIdentifier("settingsGoalSave") }
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
            guard canSave, loadedRevision == goal.updatedAt, loadedCurrency == currency, loadedGeneration == MacEditorDraftStore.shared.generation else { throw MacSettingsFailure.invalid(L10n.text("mac.goalSettingsView.save.4ec1589fe2")) }
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
