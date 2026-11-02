import SwiftUI
import SwiftData

/// Minimal input adapter: validates finance values before one SwiftData save.
/// Existing records remain readable but editing legacy FX is not attempted.
struct MacFinanceEditor: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var savedDeposits: [DepositRecord]
    let panel: MacFinancePanel
    let currency: String
    var existing: MacFinanceRecord? = nil
    var copyFrom: DepositRecord? = nil
    let onSaved: () -> Void

    @State private var name = ""
    @State private var logoRevision = 0
    @State private var reusableLogos: [MacBankLogos.SavedLogo] = []
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
    @State private var customCurrency = false
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
    @State private var termValue = 12
    @State private var termUnit = "month"
    @State private var manualMaturity = false
    @State private var advancedTime = false
    private var title: String { (existing == nil ? L10n.text("mac.financeEditor.title.50ef2f4cf6") : L10n.text("mac.financeEditor.title.0518365699")) + [MacFinancePanel.deposits: L10n.text("mac.financeEditor.title.759472586f"), .loans: L10n.text("mac.financeEditor.title.f87e87c10a"), .recurring: L10n.text("mac.financeEditor.title.e9bf2c2fea"), .goals: L10n.text("mac.financeEditor.title.57060c88a3")][panel, default: L10n.text("mac.financeEditor.title.9fad24e2c3")] }
    private var currencyCodes: [String] { MacSettingsStore.load("v2_currencies", fallback: [String]()) }
    private func updateMaturity() {
        guard panel == .deposits, !manualMaturity else { return }
        maturity = Calendar.current.date(byAdding: termUnit == "year" ? .year : termUnit == "day" ? .day : .month, value: termValue, to: start) ?? maturity
    }

    private var storedOriginalCurrency: String? {
        switch existing {
        case .deposit(let r): r.originalCurrency
        case .loan(let r): r.currency
        case .recurring(let r): r.originalCurrency
        default: nil
        }
    }

    private var editorForm: some View {
        MacFormShell(width: 560) {
            VStack(alignment: .leading, spacing: MacUI.space(8)) {
            HStack {
                Text(title).appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("financeEditorTitle")
                Spacer()
                Text(L10n.text("mac.financeEditor.MacFormShell.a46fe86e1c") + currency).appFont(.caption).foregroundStyle(.secondary)
            }
            if panel == .recurring {
                MacEntryTypeSwitcher(type: Binding(get: { recurrenceType == .income ? .income : .expense }, set: { recurrenceType = $0 == .income ? .income : .expense }), prefix: "financeRecurring")
            }
            }
        } fields: {
            VStack(alignment: .leading, spacing: MacUI.space(12)) {
                MacFormTextField(panel == .deposits ? LocalizedStringKey(L10n.text("mac.financeEditor.LocalizedStringKey.641a9c1dbd")) : LocalizedStringKey(L10n.text("mac.financeEditor.LocalizedStringKey.d44e9b3d3b")), text: $name)
                    .accessibilityIdentifier("financeEntryName")
                if panel == .deposits {
                    HStack(spacing: MacUI.space(12)) {
                        MacBankIcon(bank: name, revision: logoRevision)
                            .accessibilityHidden(false).accessibilityLabel(MacBankLogos.image(name) == nil ? L10n.text("mac.financeEditor.MacFormShell.2e5033edcf") : L10n.text("mac.financeEditor.MacFormShell.7c6fb09845"))
                            .accessibilityIdentifier("depositEditorLogo")
                        Button(L10n.text("mac.financeEditor.MacFormShell.0481d5ba76")) {
                            do { cropInput = try MacBankLogos.select(for: name); errorMessage = nil }
                            catch { errorMessage = error.localizedDescription }
                        }.accessibilityIdentifier("depositEditorChooseLogo").disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        VStack(alignment: .leading, spacing: MacUI.space(3)) {
                            Text(MacBankLogos.image(name) == nil ? L10n.text("mac.financeEditor.MacFormShell.2e5033edcf") : L10n.text("mac.financeEditor.MacFormShell.7c6fb09845")).accessibilityIdentifier("depositEditorLogoStatus")
                            Text(L10n.text("mac.financeEditor.MacFormShell.e36ade2601"))
                        }.appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    }
                    if !reusableLogos.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                Text(L10n.text("mac.financeEditor.ScrollView.16e874f805")).appFont(.caption).foregroundStyle(.secondary)
                                ForEach(Array(reusableLogos.enumerated()), id: \.element.id) { index, asset in
                                    Button {
                                        do { try MacBankLogos.save(asset.data, bank: name); logoRevision += 1 } catch { errorMessage = MacLocalization.error(error) }
                                    } label: { if let image = asset.image { Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 32) } }.buttonStyle(MacInteractiveButtonStyle()).appHelp(L10n.format("mac.financeEditor.ForEach.113ede8ba7", "\(index + 1)")).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }.frame(height: 36)
                    }
                }
                if panel == .goals { amountField }
                else {
                    ViewThatFits(in:.horizontal) {
                        HStack(alignment:.top,spacing:14) {amountField.frame(minWidth:MacNumberInput.minimumEditingWidth());currencyField}
                        VStack(alignment:.leading,spacing:14) {amountField;currencyField}
                    }
                }
                if panel != .goals, originalCurrency.uppercased() != currency {
                    MacFinanceNumberField(title: L10n.text("mac.financeEditor.MacFinanceNumberField.1c77c0bc7d"), text: $principalFx, identifier: "financeEntryFX", digits: 6)
                    if panel == .deposits { MacFinanceNumberField(title: L10n.text("mac.financeEditor.MacFinanceNumberField.7e6f35d893"), text: $interestFx, identifier: "financeInterestFX", digits: 6) }
                }
                if panel == .loans {
                    HStack(alignment: .top) {
                        MacFinanceNumberField(title: L10n.text("mac.financeEditor.MacFinanceNumberField.09166c29bd"), text: $downPaymentText, identifier: "loanDownPayment")
                        MacFinanceCategoryField(category: $recurrenceCategory, type: "Expense", identifier: "loanEditorCategory")
                    }
                }
                if panel == .loans {
                    MacFinanceNumberField(title: L10n.text("mac.financeEditor.MacFinanceNumberField.0d085dfcb5"), text: $rateText, rate: true, identifier: "financeEntryRate")
                }
                if panel == .deposits {
                    HStack(alignment: .top, spacing: 14) {
                        MacFinanceNumberField(title: L10n.text("mac.financeEditor.MacFinanceNumberField.0d085dfcb5"), text: $rateText, rate: true, identifier: "financeEntryRate")
                        MacEntryField(title: L10n.text("mac.financeEditor.MacEntryField.3f194d4874")) { MacSettingsMenu(selection: $depositMode, options: DepositInterestSettlementMode.allCases.map { (MacLocalization.value($0.rawValue), $0) }) }
                    }
                    HStack(alignment: .center, spacing: 14) {
                        Toggle(L10n.text("mac.financeEditor.MacFormShell.d0be385678"), isOn: $overridesInterest).fixedSize()
                        if overridesInterest { MacFinanceNumberField(title: L10n.text("mac.financeEditor.MacFinanceNumberField.0a28602bf4"), text: $expectedInterestText, identifier: "financeExpectedInterest") }
                        else { Spacer(minLength: 0) }
                    }
                    if existing == nil {
                        MacEntryField(title: L10n.text("mac.financeEditor.MacEntryField.af08715054")) { MacSettingsMenu(selection: $renewalSource, options: [(L10n.text("mac.financeEditor.MacSettingsMenu.484d556139"), UUID?.none)] + savedDeposits.filter { $0.deletedAt == nil && !$0.isActive && $0.hasCreditedInterest && $0.typedInterestSettlementMode != .monthly }.map { ($0.bankName, Optional($0.id)) }) }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        MacDateTimeField(title: L10n.text("mac.financeEditor.MacDateTimeField.760506491e"), date: $start, identifier: "financeStartDate")
                        if manualMaturity { MacDateTimeField(title: L10n.text("mac.financeEditor.MacDateTimeField.7589d263a3"), date: $maturity, identifier: "financeMaturityDate") }
                    }
                    HStack {
                        Toggle(L10n.text("mac.financeEditor.MacFormShell.1fcdd2920b"), isOn: $manualMaturity)
                        Spacer()
                        if !manualMaturity {
                            Stepper(L10n.format("mac.financeEditor.Stepper.b3e2dc8e87", "\(termValue)"), value: $termValue, in: 1...99).fixedSize()
                            MacSettingsMenu(selection: $termUnit, options: [("日", "day"), ("月", "month"), ("年", "year")]).frame(width: 90)
                        }
                    }
                    if !manualMaturity { Text(L10n.text("mac.financeEditor.MacFormShell.cd41276bc8") + MacDateDisplay.string(maturity)).appFont(.caption).foregroundStyle(.secondary) }
                } else if panel == .loans {
                    HStack {
                        Stepper(L10n.format("mac.financeEditor.Stepper.b7cc7e2f4a", "\(months)"), value: $months, in: 1...600).fixedSize()
                        Spacer(minLength: 16)
                        MacSettingsMenu(selection: $loanMethod, options: RepaymentMethod.allCases.map { (MacLocalization.value($0.rawValue), $0) }).frame(width: 160)
                    }
                    MacDateTimeField(title: L10n.text("mac.financeEditor.MacDateTimeField.8d07202f41"), date: $start, identifier: "financeFirstPayment")
                } else if panel == .recurring {
                    MacFinanceCategoryField(category: $recurrenceCategory, type: recurrenceType == .income ? "Income" : "Expense", identifier: "recurringEditorCategory")
                    HStack {
                        Stepper(L10n.format("mac.financeEditor.Stepper.fd1458c192", "\(recurrenceInterval)"), value: $recurrenceInterval, in: 1...365).accessibilityIdentifier("recurringEditorIntervalValue").fixedSize()
                        Spacer(minLength: 16)
                        MacSettingsMenu(selection: $recurrenceUnit, options: RecurringIntervalUnit.allCases.map { (MacLocalization.value($0.rawValue), $0) }).frame(width: 160)
                    }
                    MacDateTimeField(title: L10n.text("mac.financeEditor.MacDateTimeField.b8e094966d"), date: $start, includesTime: advancedTime, identifier: "financeNextDueDate")
                        .accessibilityIdentifier("financeNextDue")
                    Toggle(L10n.text("mac.financeEditor.MacFormShell.b7a15ad137"), isOn: $advancedTime)
                    if !advancedTime { Text(L10n.text("mac.financeEditor.MacFormShell.768d1795fb")).appFont(.caption).foregroundStyle(.secondary) }
                    Toggle(L10n.text("mac.financeEditor.MacFormShell.62f458be19"), isOn: $hasDeadline)
                    if hasDeadline { MacDateTimeField(title: L10n.text("mac.financeEditor.MacDateTimeField.f502764499"), date: $maturity, includesTime: true, identifier: "financeEndDate") }
                } else {
                    MacGoalTargetTimeField(hasDate: $hasDeadline, precision: $goalPrecision, date: $maturity, identifier: "financeGoal", includesAssets: $includesAssets)
                    if existing != nil { Toggle(L10n.text("mac.financeEditor.MacFormShell.8d12fc0d4e"), isOn: $goalPaused).accessibilityIdentifier("financeGoalPaused") }
                    MacGoalIconPicker(presentation: $goalPresentation, identifierPrefix: "financeGoalIconOption")
                }
                if panel != .goals { MacFormTextField(L10n.text("mac.financeEditor.MacFormTextField.daede98817"), text: $notes).accessibilityIdentifier("financeEntryNote") }
                if panel == .deposits || panel == .recurring {
                    if panel == .recurring {
                        HStack { Toggle(L10n.text("mac.financeEditor.MacFormShell.f4f0ead111"), isOn: $recurrenceActive).accessibilityIdentifier("recurringEditorActive"); Spacer(); Toggle(L10n.text("mac.financeEditor.MacFormShell.8f29b3132c"), isOn: $reminders) }
                    }
                    MacReminderEditor(enabled: $reminders, days: $reminderDays, time: $reminderTime, showsToggle: panel != .recurring)
                }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
                    .accessibilityIdentifier("financeEditorError")
            }
            }.toggleStyle(.switch)
        } footer: {
            HStack {
                Spacer()
                Button(L10n.text("mac.financeEditor.MacFormShell.2cd0f3be87")) { dismiss() }.buttonStyle(MacStandardButtonStyle()).keyboardShortcut(.cancelAction)
                Button(L10n.text("mac.financeEditor.MacFormShell.a3030bf8f1")) { save() }.buttonStyle(MacStandardButtonStyle(primary: true))
                    .accessibilityIdentifier("financeSave")
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    var body: some View {
        editorForm
        .sheet(item: $cropInput) { input in
            MacBankLogoCropView(input: input) { logoRevision += 1; reusableLogos = MacBankLogos.savedLogos(); cropInput = nil }
        }
        .onAppear { load() }
        .onChange(of: originalCurrency) { _, value in
            if value.uppercased() == currency { principalFx = "1"; interestFx = "1" }
            else if value.uppercased() != storedOriginalCurrency { principalFx = ""; interestFx = "" }
        }
        .onChange(of: expectedInterestText) { syncDepositRate() }
        .onChange(of: start) { updateMaturity(); syncDepositRate() }
        .onChange(of: termValue) { updateMaturity() }
        .onChange(of: termUnit) { updateMaturity() }
        .onChange(of: manualMaturity) { updateMaturity() }
        .onChange(of: advancedTime) { _, value in if !value, panel == .recurring { start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: start) ?? start } }
        .onChange(of: recurrenceType) { _, value in
            let type = value == .income ? "Income" : "Expense"
            let rows = (try? context.fetch(FetchDescriptor<Category>())) ?? []
            if !rows.contains(where: { $0.deletedAt == nil && $0.type == type && $0.name == recurrenceCategory }) {
                recurrenceCategory = rows.first(where: { $0.deletedAt == nil && $0.type == type })?.name ?? "Other"
            }
        }
        .onChange(of: maturity) { syncDepositRate() }
        .onChange(of: depositMode) { syncDepositRate() }
        .onChange(of: amountText) { syncDepositRate() }
    }

    private var amountField:some View {
        MacFinanceNumberField(title:panel == .goals ? L10n.text("mac.financeEditor.MacFinanceNumberField.83ea3be5cc"):panel == .loans ? L10n.text("mac.financeEditor.MacFinanceNumberField.89ba454870"):L10n.text("mac.financeEditor.MacFinanceNumberField.b8939c57a2"),text:$amountText,identifier:"financeEntryAmount")
    }
    private var currencyField:some View {
        MacEntryField(title:L10n.text("mac.financeEditor.MacEntryField.04ee13cd1d")) {MacEditableCurrencyMenu(currency:$originalCurrency,custom:$customCurrency,codes:currencyCodes,identifier:"financeCurrencyMenu",textIdentifier:"financeEntryCurrency")}.frame(width:MacCurrencyMenuStyle.fieldWidth)
    }

    private func save() {
        do {
            let source = panel == .goals ? currency : try MacCurrency.code(originalCurrency)
            let fx = source == currency ? 1 : try MacCurrency.rate(principalFx)
            let interestRate = source == currency ? 1 : (panel == .deposits ? try MacCurrency.rate(interestFx) : fx)
            let parsed=try MacFinanceEditing.inputAmounts(amountText,downText:downPaymentText,existing:existing)
            let total=parsed.total
            let down=panel == .loans && existing == nil ? try MacFinancialSettings.nonnegativeAmount(downPaymentText):parsed.down
            let principal=panel == .loans && existing == nil ? FinancialPrecision.roundAmountForStorage(total-down):parsed.principal
            let expectedOverride:Double?
            if panel == .deposits && overridesInterest {
                if case .deposit(let r)=existing {expectedOverride=try MacFinanceEditing.unchangedNonnegative(expectedInterestText,original:r.expectedInterest)}
                else {expectedOverride=try MacFinancialSettings.nonnegativeAmount(expectedInterestText)}
            } else {expectedOverride=nil}
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
        reusableLogos = MacBankLogos.savedLogos()
        originalCurrency = currency
        if panel == .loans { recurrenceCategory = "Loan" }
        if case .goal(let goal) = existing {
            let all: [String: MacGoalPresentation] = MacSettingsStore.load("v2_goal_presentation", fallback: [:])
            goalPresentation = all[goal.id.uuidString] ?? .init()
        }
        if existing == nil {
            if panel == .recurring { start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: start) ?? start }
            if let r = copyFrom {
                name = r.bankName; amountText = String(r.originalPrincipal); rateText = String(r.annualInterestRate)
                originalCurrency = r.originalCurrency; principalFx = String(r.principalExchangeRateToBase); interestFx = String(r.interestExchangeRateToBase)
                depositMode = r.typedInterestSettlementMode; overridesInterest = r.isInterestManuallyEdited; expectedInterestText = String(r.expectedInterest)
                notes = MacFinanceNotes.visible(r.note); reminders = r.notificationsEnabled; reminderDays = r.reminderDaysBefore
                start = r.startDate; maturity = r.maturityDate
                manualMaturity = true
            } else { updateMaturity() }
            return
        }
        guard let existing else { return }
        switch existing {
        case .deposit(let r):
            name = r.bankName; amountText = String(r.originalPrincipal); rateText = String(r.annualInterestRate)
            start = r.startDate; maturity = r.maturityDate; depositMode = r.typedInterestSettlementMode; manualMaturity = true
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
            advancedTime = Calendar.current.component(.hour, from: start) != 9 || Calendar.current.component(.minute, from: start) != 0
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
        // Hydrating an existing editor is not a financial edit. In particular,
        // deriving a displayed rate from a rounded legacy interest value would
        // turn a name-only save into a different contract (or a paid-history error).
        if case .deposit(let row) = existing,
           overridesInterest == row.isInterestManuallyEdited,
           (try? MacTransactionCRUD.editedAmount(amountText, original: row.originalPrincipal)) == row.originalPrincipal,
           (try? MacFinanceEditing.unchangedNonnegative(expectedInterestText, original: row.expectedInterest)) == row.expectedInterest,
           start == row.startDate, maturity == row.maturityDate, depositMode == row.typedInterestSettlementMode { return }
        guard panel == .deposits, overridesInterest,
              let principal = try? MacTransactionCRUD.amount(amountText),
              let interest = try? MacFinancialSettings.nonnegativeAmount(expectedInterestText),
              let rate = DepositSettlementRule.annualInterestRate(principal: principal, totalInterest: interest,
                startDate: start, maturityDate: maturity, settlementMode: depositMode) else { return }
        rateText = String(rate)
    }
}
