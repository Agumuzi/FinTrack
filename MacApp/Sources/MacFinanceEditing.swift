import Foundation
import SwiftData

enum MacFinancePanel: String, CaseIterable, Identifiable {
    case deposits = "Deposits", loans = "Loans", recurring = "Recurring", goals = "Goals"
    var id: String { rawValue }
}

enum MacFinanceRecord: Identifiable {
    case deposit(DepositRecord), loan(LoanRule), recurring(RecurringTransaction), goal(Goal)
    var id: UUID {
        switch self {
        case .deposit(let r): r.id
        case .loan(let r): r.id
        case .recurring(let r): r.id
        case .goal(let r): r.id
        }
    }
    var panel: MacFinancePanel {
        switch self { case .deposit: .deposits; case .loan: .loans; case .recurring: .recurring; case .goal: .goals }
    }
}

enum MacFinanceEditing {
    enum Failure: LocalizedError {
        case paidHistory, badDate, legacyRules
        var errorDescription: String? {
            switch self {
            case .paidHistory: "Amounts or dates with posted receipts require reconciliation. The saved history was not changed."
            case .badDate: "The next occurrence must be later than the last recorded occurrence."
            case .legacyRules: "Review the old loan payment rules before changing its schedule."
            }
        }
    }

    static func update(_ target: MacFinanceRecord, name: String, amountText: String, annualRate: Double,
                       start: Date, maturity: Date, months: Int, method: RepaymentMethod,
                       depositMode: DepositInterestSettlementMode, type: RecurringTransactionType,
                       category: String, interval: Int, unit: RecurringIntervalUnit,
                       book: String, source: String, principalRate: Double?, interestRate: Double?,
                       totalAmount: Double? = nil, downPayment: Double = 0,
                       notificationsEnabled: Bool? = nil, goalIncludesAssets: Bool? = nil, goalDeadline: Date? = nil,
                       goalPaused: Bool? = nil, reminder: MacReminderSettings? = nil,
                       recurringSettings: MacRecurringSettings? = nil, userNote: String? = nil,
                       expectedInterestOverride: Double? = nil, in context: ModelContext) throws {
        try reminder?.validate()
        if let end = recurringSettings?.endDate, end < start { throw MacFinanceRecords.Failure.invalidDateRange }
        _ = try MacCurrency.ledgerCurrency(in: context, preferred: book)
        let name = try MacTransactionCRUD.validatedCategory(name)
        let amount = try MacTransactionCRUD.amount(amountText)
        let rows = try context.fetch(FetchDescriptor<Transaction>())
        let snapshot = try MacCurrency.snapshot(amount: amount, original: source, base: book, rate: principalRate)
        guard annualRate.isFinite, (0...100).contains(annualRate) else { throw MacFinanceRecords.Failure.invalidRate }
        switch target {
        case .deposit(let r):
            guard start < maturity else { throw MacFinanceRecords.Failure.invalidDateRange }
            let terms = try MacDepositTerms.calculate(principal: amount, annualRate: annualRate, start: start, maturity: maturity, mode: depositMode, expectedOverride: expectedInterestOverride)
            let changed = r.originalPrincipal != amount || r.originalCurrency != snapshot.originalCurrency ||
                r.annualInterestRate != terms.annualRate || r.expectedInterest != terms.expectedInterest || r.isInterestManuallyEdited != terms.manuallyEdited || r.startDate != start || r.maturityDate != maturity || r.typedInterestSettlementMode != depositMode ||
                r.principalExchangeRateToBase != snapshot.rate || (interestRate != nil && r.interestExchangeRateToBase != interestRate)
            if changed {
                guard !r.hasCreditedInterest, r.lastInterestPayoutDate == nil, r.sourceDepositID == nil,
                      !rows.contains(where: { ($0.note ?? "").contains("[FTDep:\(r.id.uuidString):") })
                else { throw Failure.paidHistory }
            }
            let interest = terms.expectedInterest
            let expected = try MacCurrency.snapshot(amount: interest, original: source, base: book, rate: interestRate)
            // Compute everything before touching managed models.
            r.bankName = name
            if changed {
                r.principal = amount; r.originalPrincipal = amount; r.originalCurrency = snapshot.originalCurrency
                r.basePrincipal = snapshot.baseAmount; r.principalExchangeRateToBase = snapshot.rate
                r.currency = snapshot.originalCurrency; r.baseCurrencyCode = book
                r.annualInterestRate = FinancialPrecision.roundInterestRateForStorage(terms.annualRate)
                r.startDate = start; r.maturityDate = maturity; r.typedInterestSettlementMode = depositMode
                r.expectedInterest = interest; r.baseExpectedInterest = expected.baseAmount
                r.interestExchangeRateToBase = expected.rate; r.isInterestManuallyEdited = terms.manuallyEdited
                r.nextInterestPayoutDate = depositMode == .monthly
                    ? min(Calendar.current.date(byAdding: .month, value: 1, to: start)!, maturity) : nil
            }
            r.updatedAt = Date(); if r.syncVersion < Int.max { r.syncVersion += 1 }
            if let notificationsEnabled { r.notificationsEnabled = notificationsEnabled }
            if let reminder { r.reminderDaysBefore = reminder.daysBefore; r.reminderHour = reminder.hour; r.reminderMinute = reminder.minute }
            if let userNote { r.note = MacFinanceNotes.replacing(r.note, with: userNote) }
        case .loan(let r):
            guard (1...600).contains(months) else { throw MacFinanceRecords.Failure.invalidTerm }
            let category = try MacTransactionCRUD.validatedCategory(category)
            guard downPayment.isFinite, downPayment >= 0,
                  totalAmount == nil || (totalAmount!.isFinite && abs(totalAmount! - downPayment - amount) < 0.005)
            else { throw MacFinanceRecords.Failure.invalidTerm }
            let changed = r.principal != amount || r.currency != snapshot.originalCurrency ||
                r.annualRate != annualRate || r.startDate != start || r.termMonths != months || r.method != method || r.exchangeRateToBase != snapshot.rate
            if changed {
                guard !rows.contains(where: { ($0.note ?? "").contains("[FTLoan:\(r.id.uuidString):") }) else { throw Failure.paidHistory }
                guard r.generatedRules.isEmpty else { throw Failure.legacyRules }
            }
            r.title = name
            r.category = category
            if let userNote { r.note = MacFinanceNotes.replacing(r.note, with: userNote) ?? "" }
            if changed {
                r.principal = amount; r.basePrincipal = snapshot.baseAmount; r.currency = snapshot.originalCurrency
                r.baseCurrencyCode = book; r.exchangeRateToBase = snapshot.rate
                r.totalAmount = totalAmount ?? amount; r.downPaymentAmount = downPayment
                r.downPaymentPercent = r.totalAmount > 0 ? FinancialPrecision.roundAmountForDisplay(downPayment / r.totalAmount * 100) : 0
                r.annualRate = FinancialPrecision.roundInterestRateForStorage(annualRate)
                r.startDate = start; r.termMonths = months; r.method = method
            }
            r.updatedAt = Date(); if r.syncVersion < Int.max { r.syncVersion += 1 }
        case .recurring(let r):
            guard (1...365).contains(interval) else { throw MacFinanceRecords.Failure.invalidRecurrence }
            if let last = r.lastExecutionDate, start <= last { throw Failure.badDate }
            guard !(r.projectIdentifier ?? "").hasPrefix("loan_generated:") else { throw Failure.legacyRules }
            let category = try MacTransactionCRUD.validatedCategory(category)
            r.title = name; r.amount = amount; r.originalAmount = amount; r.originalCurrency = snapshot.originalCurrency
            r.currency = snapshot.originalCurrency; r.baseAmount = snapshot.baseAmount; r.baseCurrencyCode = book
            r.exchangeRateToBase = snapshot.rate; r.typedType = type; r.category = category
            r.intervalValue = interval; r.typedIntervalUnit = unit; r.nextExecutionDate = start
            if let notificationsEnabled { r.notificationsEnabled = notificationsEnabled }
            if let reminder { r.reminderDaysBefore = reminder.daysBefore; r.reminderHour = reminder.hour; r.reminderMinute = reminder.minute }
            if let recurringSettings { r.endDate = recurringSettings.endDate; r.isActive = recurringSettings.isActive }
            if let userNote { r.note = MacFinanceNotes.replacing(r.note, with: userNote) }
            r.updatedAt = Date(); if r.syncVersion < Int.max { r.syncVersion += 1 }
        case .goal(let r):
            r.title = name; r.targetAmount = amount; r.deadline = goalDeadline
            if let goalIncludesAssets { r.includesCurrentAssets = goalIncludesAssets }
            if let goalPaused { r.isPaused = goalPaused }
            r.updatedAt = Date(); if r.syncVersion < Int.max { r.syncVersion += 1 }
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func retire(_ target: MacFinanceRecord, in context: ModelContext) throws {
        let now = Date()
        let rules = try context.fetch(FetchDescriptor<RecurringTransaction>())
        switch target {
        case .deposit(let r): r.deletedAt = now; r.isActive = false; r.updatedAt = now
        case .loan(let r):
            r.deletedAt = now; r.updatedAt = now
            let prefix = "loan_generated:\(r.id.uuidString):"
            for rule in rules where r.generatedRules.contains(where: { $0.id == rule.id }) || (rule.projectIdentifier ?? "").hasPrefix(prefix) {
                rule.isActive = false; rule.updatedAt = now
            }
        case .recurring(let r): r.deletedAt = now; r.isActive = false; r.updatedAt = now
        case .goal(let r): r.deletedAt = now; r.updatedAt = now
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
