import SwiftUI
import SwiftData

/// Minimal input adapter: validates finance values before one SwiftData save.
/// Existing records remain readable but editing legacy FX is not attempted.
struct MacFinanceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var savedDeposits: [DepositRecord]
    let panel: MacFinancePanel
    let currency: String
    var existing: MacFinanceRecord? = nil
    let onSaved: () -> Void

    @State private var name = ""
    @State private var logoRevision = 0
    @State private var cropInput: MacBankLogos.CropInput?
    @State private var amountText = ""
    @State private var rateText = "10"
    @State private var start = Date()
    @State private var maturity = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var months = 12
    @State private var loanMethod: RepaymentMethod = .equalPayment
    @State private var depositMode: DepositInterestSettlementMode = .maturity
    @State private var recurrenceType: RecurringTransactionType = .expense
    @State private var recurrenceUnit: RecurringIntervalUnit = .month
    @State private var recurrenceInterval = 1
    @State private var recurrenceCategory = "Other"
    @State private var errorMessage: String?
    @State private var originalCurrency = ""
    @State private var principalFx = "1"
    @State private var interestFx = "1"
    @State private var downPaymentText = "0"
    @State private var renewalSource: UUID?
    @State private var reminders = false
    @State private var reminderDays = 0
    @State private var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
    @State private var notes = ""
    @State private var recurrenceActive = true
    @State private var overridesInterest = false
    @State private var expectedInterestText = ""
    @State private var includesAssets = true
    @State private var hasDeadline = false
    @State private var goalPrecision: TargetDatePrecision = .day
    @State private var goalPaused = false
    @State private var goalPresentation = MacGoalPresentation()

    private var storedOriginalCurrency: String? {
        switch existing {
        case .deposit(let r): r.originalCurrency
        case .loan(let r): r.currency
        case .recurring(let r): r.originalCurrency
        default: nil
        }
    }

    var body: some View {
        MacFormShell(width: 560) {
            VStack(alignment: .leading, spacing: MacUI.space(8)) {
            Text(existing == nil ? LocalizedStringKey("新建财务记录") : LocalizedStringKey("编辑财务记录"))
                .appFont(.dialogTitle, weight: .semibold)
                .accessibilityIdentifier("financeEditorTitle")
            Text("本位币：\(currency)")
                .foregroundStyle(.secondary)
            }
        } fields: {
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
                MacFormTextField(panel == .deposits ? LocalizedStringKey("银行名称") : LocalizedStringKey("名称"), text: $name)
                    .accessibilityIdentifier("financeEntryName")
                if panel == .deposits {
                    HStack(spacing: MacUI.space(12)) {
                        MacBankIcon(bank: name, revision: logoRevision)
                            .accessibilityHidden(false).accessibilityLabel(MacBankLogos.image(name) == nil ? "通用银行图标" : "已绑定银行图标")
                            .accessibilityIdentifier("depositEditorLogo")
                        Button("选择银行图标…") {
                            do { cropInput = try MacBankLogos.select(for: name); errorMessage = nil }
                            catch { errorMessage = error.localizedDescription }
                        }.accessibilityIdentifier("depositEditorChooseLogo").disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        VStack(alignment: .leading, spacing: MacUI.space(3)) {
                            Text(MacBankLogos.image(name) == nil ? "通用银行图标" : "已绑定银行图标").accessibilityIdentifier("depositEditorLogoStatus")
                            Text("同名银行自动使用此图标")
                        }.appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    }
                }
                MacFormTextField(panel == .goals ? "目标金额" : (panel == .loans ? "总金额" : "本金 / 金额"), text: $amountText)
                    .accessibilityIdentifier("financeEntryAmount")
                if panel != .goals {
                    MacFormTextField("原币币种", text: $originalCurrency).accessibilityIdentifier("financeEntryCurrency")
                    if originalCurrency.uppercased() != currency {
                        MacFormTextField("兑本位币汇率", text: $principalFx).accessibilityIdentifier("financeEntryFX")
                        if panel == .deposits {
                            MacFormTextField("预期利息汇率", text: $interestFx)
                        }
                    }
                }
                if panel == .loans {
                    MacFormTextField("首付金额", text: $downPaymentText).accessibilityIdentifier("loanDownPayment")
                    MacFormTextField("还款分类", text: $recurrenceCategory).accessibilityIdentifier("loanEditorCategory")
                }
                if panel == .deposits || panel == .loans {
                    MacFormTextField("年利率 %", text: $rateText)
                        .accessibilityIdentifier("financeEntryRate")
                }
                if panel == .deposits {
                    Toggle("手动设置预期利息", isOn: $overridesInterest)
                    if overridesInterest { MacFormTextField("预期利息", text: $expectedInterestText) }
                    if existing == nil {
                        Picker("续存来源", selection: $renewalSource) {
                            Text("无").tag(nil as UUID?)
                            ForEach(savedDeposits.filter { $0.deletedAt == nil && !$0.isActive && $0.hasCreditedInterest && $0.typedInterestSettlementMode != .monthly }, id: \.id) {
                                Text($0.bankName).tag(Optional($0.id))
                            }
                        }
                    }
                    Picker("结息方式", selection: $depositMode) {
                        ForEach(DepositInterestSettlementMode.allCases) { option in
                            Text(LocalizedStringKey(option.rawValue)).tag(option)
                        }
                    }
                    MacDateTimeField(title: "开始日期", date: $start, identifier: "financeStartDate")
                    MacDateTimeField(title: "到期日期", date: $maturity, identifier: "financeMaturityDate")
                } else if panel == .loans {
                    Stepper("还款期数：\(months) 个月", value: $months, in: 1...600)
                    Picker("还款方式", selection: $loanMethod) {
                        ForEach(RepaymentMethod.allCases) { option in
                            Text(LocalizedStringKey(option.rawValue)).tag(option)
                        }
                    }
                    MacDateTimeField(title: "首次还款日期", date: $start, identifier: "financeFirstPayment")
                } else if panel == .recurring {
                    Picker("收支类型", selection: $recurrenceType) {
                        Text("支出").tag(RecurringTransactionType.expense)
                        Text("收入").tag(RecurringTransactionType.income)
                    }
                    MacFormTextField("分类", text: $recurrenceCategory).accessibilityIdentifier("recurringEditorCategory")
                    Stepper("每 \(recurrenceInterval)", value: $recurrenceInterval, in: 1...365).accessibilityIdentifier("recurringEditorIntervalValue")
                    Picker("周期单位", selection: $recurrenceUnit) {
                        ForEach(RecurringIntervalUnit.allCases) { option in
                            Text(LocalizedStringKey(option.rawValue)).tag(option)
                        }
                    }
                    MacDateTimeField(title: "下次执行", date: $start, includesTime: true, identifier: "financeNextDueDate")
                        .accessibilityIdentifier("financeNextDue")
                    Toggle("设置结束时间", isOn: $hasDeadline)
                    if hasDeadline { MacDateTimeField(title: "结束时间", date: $maturity, includesTime: true, identifier: "financeEndDate") }
                    Toggle("启用", isOn: $recurrenceActive).accessibilityIdentifier("recurringEditorActive")
                } else {
                    Toggle("包含当前资产", isOn: $includesAssets)
                    MacGoalTargetTimeField(hasDate: $hasDeadline, precision: $goalPrecision, date: $maturity, identifier: "financeGoal")
                    if existing != nil { Toggle("暂停", isOn: $goalPaused).accessibilityIdentifier("financeGoalPaused") }
                    MacGoalIconPicker(presentation: $goalPresentation, identifierPrefix: "financeGoalIconOption")
                }
                if panel != .goals { MacFormTextField("备注", text: $notes).accessibilityIdentifier("financeEntryNote") }
                if panel == .deposits || panel == .recurring {
                    Toggle("提醒", isOn: $reminders)
                    if reminders {
                        Stepper("提前 \(reminderDays) 天提醒", value: $reminderDays, in: 0...365)
                        DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute).appFormControl()
                    }
                }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
                    .accessibilityIdentifier("financeEditorError")
            }
            }.toggleStyle(.switch)
        } footer: {
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(MacStandardButtonStyle()).keyboardShortcut(.cancelAction)
                Button("保存") { save() }.buttonStyle(MacStandardButtonStyle(primary: true))
                    .accessibilityIdentifier("financeSave")
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(item: $cropInput) { input in
            MacBankLogoCropView(input: input) { logoRevision += 1; cropInput = nil }
        }
        .onAppear { load() }
        .onChange(of: originalCurrency) { _, value in
            if value.uppercased() == currency { principalFx = "1"; interestFx = "1" }
            else if value.uppercased() != storedOriginalCurrency { principalFx = ""; interestFx = "" }
        }
        .onChange(of: expectedInterestText) { syncDepositRate() }
        .onChange(of: start) { syncDepositRate() }
        .onChange(of: maturity) { syncDepositRate() }
        .onChange(of: depositMode) { syncDepositRate() }
        .onChange(of: amountText) { syncDepositRate() }
    }

    private func save() {
        do {
            let source = panel == .goals ? currency : try MacCurrency.code(originalCurrency)
            let fx = source == currency ? 1 : try MacCurrency.rate(principalFx)
            let interestRate = source == currency ? 1 : (panel == .deposits ? try MacCurrency.rate(interestFx) : fx)
            let total = try MacTransactionCRUD.amount(amountText)
            let down = panel == .loans ? try MacFinancialSettings.nonnegativeAmount(downPaymentText) : 0
            let principal = panel == .loans ? FinancialPrecision.roundAmountForStorage(total - down) : total
            let expectedOverride = panel == .deposits && overridesInterest ? try MacFinancialSettings.nonnegativeAmount(expectedInterestText) : nil
            let reminder = MacReminderSettings(daysBefore: reminderDays, hour: Calendar.current.component(.hour, from: reminderTime), minute: Calendar.current.component(.minute, from: reminderTime))
            guard principal > 0 else { throw MacFinanceRecords.Failure.invalidTerm }
            if let existing {
                guard let annual = Double(rateText.replacingOccurrences(of: ",", with: ".")) else { throw MacFinanceRecords.Failure.invalidRate }
                try MacFinanceEditing.update(existing, name: name, amountText: String(principal), annualRate: annual,
                    start: start, maturity: maturity, months: months, method: loanMethod,
                    depositMode: depositMode, type: recurrenceType, category: recurrenceCategory,
                    interval: recurrenceInterval, unit: recurrenceUnit, book: currency, source: source,
                    principalRate: fx, interestRate: interestRate, totalAmount: panel == .loans ? total : nil,
                    downPayment: down, notificationsEnabled: reminders,
                    goalIncludesAssets: includesAssets, goalDeadline: hasDeadline ? maturity : nil, goalPaused: goalPaused, goalPrecision: goalPrecision,
                    reminder: reminder, recurringSettings: panel == .recurring ? MacRecurringSettings(endDate: hasDeadline ? maturity : nil, isActive: recurrenceActive) : nil,
                    userNote: panel == .goals ? nil : notes, expectedInterestOverride: expectedOverride, in: context)
                if case .goal(let goal) = existing { try saveGoalPresentation(for: goal) }
                onSaved(); dismiss(); return
            }
            switch panel {
            case .deposits:
                guard let rate = Double(rateText.replacingOccurrences(of: ",", with: ".")) else {
                    throw MacFinanceRecords.Failure.invalidRate
                }
                if let sourceID = renewalSource, let parent = savedDeposits.first(where: { $0.id == sourceID }) {
                    _ = try MacFinanceReview.renewal(source: parent, bank: name, principal: amountText, annualRate: rate,
                        start: start, maturity: maturity, mode: depositMode, book: currency, sourceCurrency: source,
                        principalRate: fx, interestRate: interestRate, notificationsEnabled: reminders, reminder: reminder, userNote: notes, expectedInterestOverride: expectedOverride, in: context)
                } else {
                    try MacFinanceRecords.addDeposit(bank: name, principalText: amountText, annualRate: rate,
                        start: start, maturity: maturity, mode: depositMode, currency: currency, originalCurrency: source,
                        principalRate: fx, expectedInterestRate: interestRate, notificationsEnabled: reminders, reminder: reminder, userNote: notes, expectedInterestOverride: expectedOverride, in: context)
                }
            case .loans:
                guard let rate = Double(rateText.replacingOccurrences(of: ",", with: ".")) else {
                    throw MacFinanceRecords.Failure.invalidRate
                }
                try MacFinanceRecords.addLoan(
                    title: name, principalText: String(principal), annualRate: rate,
                    months: months, method: loanMethod, firstPayment: start,
                    currency: currency, originalCurrency: source, exchangeRate: fx,
                    totalAmount: total, downPayment: down, category: recurrenceCategory, userNote: notes, in: context)
            case .recurring:
                try MacFinanceRecords.addRecurring(
                    title: name, amountText: amountText,
                    type: recurrenceType, category: recurrenceCategory,
                    interval: recurrenceInterval, unit: recurrenceUnit,
                    next: start, currency: currency, originalCurrency: source, exchangeRate: fx, notificationsEnabled: reminders,
                    reminder: reminder, settings: MacRecurringSettings(endDate: hasDeadline ? maturity : nil, isActive: recurrenceActive), userNote: notes, in: context)
            case .goals:
                let goal = try MacFinanceRecords.addGoal(
                    title: name, targetText: amountText, deadline: hasDeadline ? maturity : nil,
                    currency: currency, includesCurrentAssets: includesAssets, targetDatePrecision: goalPrecision, in: context)
                try saveGoalPresentation(for: goal)
            }
            onSaved()
            dismiss()
        } catch { errorMessage = MacLocalization.error(error) }
    }

    private func load() {
        originalCurrency = currency
        if panel == .loans { recurrenceCategory = "Loan" }
        if case .goal(let goal) = existing {
            let all: [String: MacGoalPresentation] = MacSettingsStore.load("v2_goal_presentation", fallback: [:])
            goalPresentation = all[goal.id.uuidString] ?? .init()
        }
        guard let existing else { return }
        switch existing {
        case .deposit(let r):
            name = r.bankName; amountText = String(r.originalPrincipal); rateText = String(r.annualInterestRate)
            start = r.startDate; maturity = r.maturityDate; depositMode = r.typedInterestSettlementMode
            originalCurrency = r.originalCurrency; principalFx = String(r.principalExchangeRateToBase); interestFx = String(r.interestExchangeRateToBase)
            reminders = r.notificationsEnabled
            overridesInterest = r.isInterestManuallyEdited; expectedInterestText = String(r.expectedInterest)
            notes = MacFinanceNotes.visible(r.note); reminderDays = r.reminderDaysBefore
            reminderTime = Calendar.current.date(bySettingHour: r.reminderHour, minute: r.reminderMinute, second: 0, of: Date()) ?? reminderTime
        case .loan(let r):
            notes = MacFinanceNotes.visible(r.note)
            name = r.title; amountText = String(r.totalAmount); downPaymentText = String(r.downPaymentAmount)
            rateText = String(r.annualRate); start = r.startDate; months = r.termMonths; loanMethod = r.method
            originalCurrency = r.currency; principalFx = String(r.exchangeRateToBase); recurrenceCategory = r.category
        case .recurring(let r):
            notes = MacFinanceNotes.visible(r.note); hasDeadline = r.endDate != nil; maturity = r.endDate ?? maturity; recurrenceActive = r.isActive
            reminderDays = r.reminderDaysBefore
            reminderTime = Calendar.current.date(bySettingHour: r.reminderHour, minute: r.reminderMinute, second: 0, of: Date()) ?? reminderTime
            name = r.title; amountText = String(r.originalAmount); start = r.nextExecutionDate
            recurrenceType = r.typedType; recurrenceCategory = r.category; recurrenceInterval = r.intervalValue; recurrenceUnit = r.typedIntervalUnit
            originalCurrency = r.originalCurrency; principalFx = String(r.exchangeRateToBase)
            reminders = r.notificationsEnabled
        case .goal(let r):
            name = r.title; amountText = String(r.targetAmount); maturity = r.targetTime.resolvedDate() ?? maturity
            includesAssets = r.includesCurrentAssets; hasDeadline = r.deadline != nil; goalPaused = r.isPaused; goalPrecision = r.targetTime.precision
        }
    }

    private func saveGoalPresentation(for goal: Goal) throws {
        var all: [String: MacGoalPresentation] = MacSettingsStore.load("v2_goal_presentation", fallback: [:])
        all[goal.id.uuidString] = goalPresentation
        try MacSettingsStore.save(all, key: "v2_goal_presentation")
    }

    private func syncDepositRate() {
        guard panel == .deposits, overridesInterest,
              let principal = try? MacTransactionCRUD.amount(amountText),
              let interest = try? MacFinancialSettings.nonnegativeAmount(expectedInterestText),
              let rate = DepositSettlementRule.annualInterestRate(principal: principal, totalInterest: interest,
                startDate: start, maturityDate: maturity, settlementMode: depositMode) else { return }
        rateText = String(rate)
    }
}
