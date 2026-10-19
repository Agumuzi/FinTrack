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
            Text(existing == nil ? LocalizedStringKey("New finance record") : LocalizedStringKey("Edit finance record"))
                .appFont(.dialogTitle, weight: .semibold)
                .accessibilityIdentifier("financeEditorTitle")
            Text("Book currency: \(currency)")
                .foregroundStyle(.secondary)
            }
        } fields: {
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
                MacFormTextField(panel == .deposits ? LocalizedStringKey("Bank name") : LocalizedStringKey("Title"), text: $name)
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
                MacFormTextField(panel == .goals ? "Target amount" : (panel == .loans ? "Total amount" : "Principal / amount"), text: $amountText)
                    .accessibilityIdentifier("financeEntryAmount")
                if panel != .goals {
                    MacFormTextField("Original currency", text: $originalCurrency).accessibilityIdentifier("financeEntryCurrency")
                    if originalCurrency.uppercased() != currency {
                        MacFormTextField("Exchange rate to book currency", text: $principalFx).accessibilityIdentifier("financeEntryFX")
                        if panel == .deposits {
                            MacFormTextField("Expected-interest exchange rate", text: $interestFx)
                        }
                    }
                }
                if panel == .loans {
                    MacFormTextField("Down payment amount", text: $downPaymentText).accessibilityIdentifier("loanDownPayment")
                    MacFormTextField("Payment category", text: $recurrenceCategory).accessibilityIdentifier("loanEditorCategory")
                }
                if panel == .deposits || panel == .loans {
                    MacFormTextField("Annual rate %", text: $rateText)
                        .accessibilityIdentifier("financeEntryRate")
                }
                if panel == .deposits {
                    Toggle("Edit expected interest", isOn: $overridesInterest)
                    if overridesInterest { MacFormTextField("Expected interest", text: $expectedInterestText) }
                    if existing == nil {
                        Picker("Renew from matured deposit", selection: $renewalSource) {
                            Text("None").tag(nil as UUID?)
                            ForEach(savedDeposits.filter { $0.deletedAt == nil && !$0.isActive && $0.hasCreditedInterest && $0.typedInterestSettlementMode != .monthly }, id: \.id) {
                                Text($0.bankName).tag(Optional($0.id))
                            }
                        }
                    }
                    Picker("Interest settlement", selection: $depositMode) {
                        ForEach(DepositInterestSettlementMode.allCases) { option in
                            Text(LocalizedStringKey(option.rawValue)).tag(option)
                        }
                    }
                    DatePicker("Start date", selection: $start, displayedComponents: .date).appFormControl()
                    DatePicker("Maturity date", selection: $maturity, displayedComponents: .date).appFormControl()
                } else if panel == .loans {
                    Stepper("Payments: \(months) months", value: $months, in: 1...600)
                    Picker("Repayment method", selection: $loanMethod) {
                        ForEach(RepaymentMethod.allCases) { option in
                            Text(LocalizedStringKey(option.rawValue)).tag(option)
                        }
                    }
                    DatePicker("First repayment", selection: $start, displayedComponents: .date).appFormControl()
                } else if panel == .recurring {
                    Picker("Flow", selection: $recurrenceType) {
                        Text("Expense").tag(RecurringTransactionType.expense)
                        Text("Income").tag(RecurringTransactionType.income)
                    }
                    MacFormTextField("Category", text: $recurrenceCategory).accessibilityIdentifier("recurringEditorCategory")
                    Stepper("Every \(recurrenceInterval)", value: $recurrenceInterval, in: 1...365).accessibilityIdentifier("recurringEditorIntervalValue")
                    Picker("Interval", selection: $recurrenceUnit) {
                        ForEach(RecurringIntervalUnit.allCases) { option in
                            Text(LocalizedStringKey(option.rawValue)).tag(option)
                        }
                    }
                    DatePicker("Next due", selection: $start).appFormControl()
                        .accessibilityIdentifier("financeNextDue")
                    Toggle("Set end date", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("End date", selection: $maturity).appFormControl() }
                    Toggle("Active", isOn: $recurrenceActive).accessibilityIdentifier("recurringEditorActive")
                } else {
                    Toggle("Include current assets", isOn: $includesAssets)
                    Toggle("Set target date", isOn: $hasDeadline).accessibilityIdentifier("financeGoalDeadlineToggle")
                    if hasDeadline { MacSettingsRow(label: "目标日期", labelWidth: 90) { MacSettingsDateButton(date: $maturity, identifier: "financeGoalDate") } }
                    if existing != nil { Toggle("Paused", isOn: $goalPaused).accessibilityIdentifier("financeGoalPaused") }
                    MacGoalIconPicker(presentation: $goalPresentation, identifierPrefix: "financeGoalIconOption")
                }
                if panel != .goals { MacFormTextField("Note", text: $notes).accessibilityIdentifier("financeEntryNote") }
                if panel == .deposits || panel == .recurring {
                    Toggle("Reminders", isOn: $reminders)
                    if reminders {
                        Stepper("Remind days before: \(reminderDays)", value: $reminderDays, in: 0...365)
                        DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute).appFormControl()
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
                Button("Cancel") { dismiss() }.buttonStyle(MacStandardButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(MacStandardButtonStyle(primary: true))
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
                    goalIncludesAssets: includesAssets, goalDeadline: hasDeadline ? maturity : nil, goalPaused: goalPaused,
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
                    currency: currency, includesCurrentAssets: includesAssets, in: context)
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
            name = r.title; amountText = String(r.targetAmount); maturity = r.deadline ?? maturity
            includesAssets = r.includesCurrentAssets; hasDeadline = r.deadline != nil; goalPaused = r.isPaused
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
