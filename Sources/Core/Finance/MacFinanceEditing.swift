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

    static func inputAmounts(_ text: String, downText: String, existing: MacFinanceRecord?) throws -> (total:Double,down:Double,principal:Double) {
        let original:Double?
        switch existing {case .deposit(let r):original=r.originalPrincipal;case .recurring(let r):original=r.originalAmount;case .goal(let r):original=r.targetAmount;case .loan(let r):original=r.totalAmount;case nil:original=nil}
        let total=try original.map {try MacTransactionCRUD.editedAmount(text,original:$0)} ?? MacTransactionCRUD.amount(text)
        guard case .loan(let loan)=existing else{return(total,0,total)}
        let down=try unchangedNonnegative(downText,original:loan.downPaymentAmount)
        let principal=total == loan.totalAmount && down == loan.downPaymentAmount ? loan.principal:FinancialPrecision.roundAmountForStorage(total-down)
        return(total,down,principal)
    }
    static func unchangedNonnegative(_ text:String,original:Double) throws -> Double {
        if text == String(original),original.isFinite,(0...1e12).contains(original){return original}
        return try MacFinancialSettings.nonnegativeAmount(text)
    }

    static func update(_ target: MacFinanceRecord, name: String, amountText: String, annualRate: Double,
                       start: Date, maturity: Date, months: Int, method: RepaymentMethod,
                       depositMode: DepositInterestSettlementMode, type: RecurringTransactionType,
                       category: String, interval: Int, unit: RecurringIntervalUnit,
                       book: String, source: String, principalRate: Double?, interestRate: Double?,
                       totalAmount: Double? = nil, downPayment: Double = 0,
                       notificationsEnabled: Bool? = nil, goalIncludesAssets: Bool? = nil, goalDeadline: Date? = nil,
                       goalPaused: Bool? = nil, goalPrecision: TargetDatePrecision? = nil, reminder: MacReminderSettings? = nil,
                       recurringSettings: MacRecurringSettings? = nil, userNote: String? = nil,
                       expectedInterestOverride: Double? = nil, in context: ModelContext) throws {
        try MacRecoveryJournal.assertWritable(in:context)
        try reminder?.validate()
        var capturedGoalValue: String?
        if case .goal = target, let goalDeadline, let goalPrecision {
            let raw = GoalTargetTime.capturedValue(goalDeadline, precision: goalPrecision)
            guard GoalTargetTime.components(raw, precision: goalPrecision) != nil else { throw MacSettingsFailure.invalid("期望时间超出支持范围") }
            capturedGoalValue = raw
        }
        if let end = recurringSettings?.endDate, end < start { throw MacFinanceRecords.Failure.invalidDateRange }
        guard try MacCurrency.ledgerCurrency(in: context, preferred: book) == book else { throw MacCurrency.Failure.mixedBooks }
        let name = try MacTransactionCRUD.validatedCategory(name)
        let original: Double
        switch target {
        case .deposit(let row): original = row.originalPrincipal
        case .loan(let row): original = row.principal
        case .recurring(let row): original = row.originalAmount
        case .goal(let row): original = row.targetAmount
        }
        let amount = try MacTransactionCRUD.editedAmount(amountText, original: original)
        let rows = try context.fetch(FetchDescriptor<Transaction>())
        let previous:MacCurrencySnapshot?
        switch target {
        case .deposit(let r):previous = .init(originalAmount:r.originalPrincipal,originalCurrency:r.originalCurrency,baseAmount:r.basePrincipal,baseCurrency:r.baseCurrencyCode,rate:r.principalExchangeRateToBase)
        case .loan(let r):previous = .init(originalAmount:r.principal,originalCurrency:r.currency,baseAmount:r.basePrincipal,baseCurrency:r.baseCurrencyCode,rate:r.exchangeRateToBase)
        case .recurring(let r):previous = .init(originalAmount:r.originalAmount,originalCurrency:r.originalCurrency,baseAmount:r.baseAmount,baseCurrency:r.baseCurrencyCode,rate:r.exchangeRateToBase)
        case .goal:previous=nil
        }
        let snapshot:MacCurrencySnapshot
        if let previous,amount == previous.originalAmount,source == previous.originalCurrency,book == previous.baseCurrency,
           (principalRate ?? previous.rate) == previous.rate {
            try MacBankSettlement.validateSavedSnapshot(amount:amount,actual:previous.baseAmount,source:source,base:book,rate:previous.rate,allowLegacyPrecision:true)
            snapshot=previous
        } else {snapshot=try MacCurrency.snapshot(amount:amount,original:source,base:book,rate:principalRate)}
        guard annualRate.isFinite, (0...100).contains(annualRate) else { throw MacFinanceRecords.Failure.invalidRate }
        switch target {
        case .deposit(let r):
            guard start < maturity else { throw MacFinanceRecords.Failure.invalidDateRange }
            // Compare submitted inputs before deriving or rounding anything.
            // Unchanged legacy financial values are authoritative, including
            // independent principal/interest FX snapshots and posted history.
            let changed = r.originalPrincipal != amount || r.originalCurrency != snapshot.originalCurrency ||
                r.annualInterestRate != annualRate ||
                (expectedInterestOverride != nil && r.expectedInterest != expectedInterestOverride) ||
                r.isInterestManuallyEdited != (expectedInterestOverride != nil) ||
                r.startDate != start || r.maturityDate != maturity || r.typedInterestSettlementMode != depositMode ||
                r.principalExchangeRateToBase != snapshot.rate || (interestRate != nil && r.interestExchangeRateToBase != interestRate)
            if changed {
                guard !r.hasCreditedInterest, r.lastInterestPayoutDate == nil, r.sourceDepositID == nil,
                      !rows.contains(where: { ($0.note ?? "").contains("[FTDep:\(r.id.uuidString):") })
                else { throw Failure.paidHistory }
            }
            if changed {
                let terms = try MacDepositTerms.calculate(principal: amount, annualRate: annualRate, start: start, maturity: maturity, mode: depositMode, expectedOverride: expectedInterestOverride)
                let interest = terms.expectedInterest
                let expected = try MacCurrency.snapshot(amount: interest, original: source, base: book, rate: interestRate)
                r.principal = amount; r.originalPrincipal = amount; r.originalCurrency = snapshot.originalCurrency
                r.basePrincipal = snapshot.baseAmount; r.principalExchangeRateToBase = snapshot.rate
                r.currency = snapshot.originalCurrency; r.baseCurrencyCode = book
                r.annualInterestRate = terms.annualRate
                r.startDate = start; r.maturityDate = maturity; r.typedInterestSettlementMode = depositMode
                r.expectedInterest = interest; r.baseExpectedInterest = expected.baseAmount
                r.interestExchangeRateToBase = expected.rate; r.isInterestManuallyEdited = terms.manuallyEdited
                r.nextInterestPayoutDate = depositMode == .monthly
                    ? min(Calendar.current.date(byAdding: .month, value: 1, to: start)!, maturity) : nil
            }
            r.bankName = name
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
            // Build date metadata before touching a managed model; on failure
            // an editor must not leave partial changes in its ModelContext.
            let candidate = LoanRule(title: name, principal: amount, annualRate: annualRate, termMonths: months,
                methodRawValue: method.rawValue, currency: snapshot.originalCurrency, startDate: start,
                category: category, note: MacFinanceNotes.replacing(r.note, with: userNote ?? MacFinanceNotes.visible(r.note)) ?? "")
            if changed { try MacLoanSchedule.pin(candidate, replacingExisting: true) }
            r.title = name
            r.category = category
            if let userNote { r.note = MacFinanceNotes.replacing(r.note, with: userNote) ?? "" }
            if changed {
                r.principal = amount; r.basePrincipal = snapshot.baseAmount; r.currency = snapshot.originalCurrency
                r.baseCurrencyCode = book; r.exchangeRateToBase = snapshot.rate
                r.annualRate = FinancialPrecision.roundInterestRateForStorage(annualRate)
                r.startDate = start; r.termMonths = months; r.method = method
                r.note = candidate.note
            }
            if r.totalAmount != (totalAmount ?? amount) || r.downPaymentAmount != downPayment {
                r.totalAmount = totalAmount ?? amount; r.downPaymentAmount = downPayment
                r.downPaymentPercent = r.totalAmount > 0 ? FinancialPrecision.roundAmountForDisplay(downPayment / r.totalAmount * 100) : 0
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
            let oldDeadline = r.deadline
            r.title = name; r.targetAmount = amount; r.deadline = goalDeadline
            if goalDeadline == nil { r.targetDatePrecisionRaw = nil; r.targetDateValueRaw = nil }
            else if let goalPrecision {
                r.targetDatePrecisionRaw = goalPrecision.rawValue
                r.targetDateValueRaw = capturedGoalValue
            } else if oldDeadline != goalDeadline { r.targetDateValueRaw = nil }
            if let goalIncludesAssets { r.includesCurrentAssets = goalIncludesAssets }
            if let goalPaused { r.isPaused = goalPaused }
            r.updatedAt = Date(); if r.syncVersion < Int.max { r.syncVersion += 1 }
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func retire(_ target: MacFinanceRecord, in context: ModelContext) throws {
        try MacRecoveryJournal.assertWritable(in:context)
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
