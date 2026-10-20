import Foundation
import SwiftData

/// A conservative macOS adapter over the ORIGINAL four FinTrack @Model classes.
/// Does not mutate original model schemas, repayment mathematics, or interest rules.
@MainActor
enum MacFinanceRecords {
    enum Failure: LocalizedError {
        case invalidName, invalidDateRange, invalidRate, invalidTerm
        case invalidRecurrence, currencyMismatch, legacyPostingDisabled
        case futureOccurrence, noProgress, tooManyOccurrences, existingOccurrence
        var errorDescription: String? {
            switch self {
            case .invalidName: "Enter a title or bank name."
            case .invalidDateRange: "The end date must be later than the start date."
            case .invalidRate: "Interest rate must be between 0 and 100 percent."
            case .invalidTerm: "Loan term must be from 1 to 600 months."
            case .invalidRecurrence: "Recurring interval must be positive and have a valid unit."
            case .currencyMismatch: "Confirm the ledger currency and the original currency exchange rate."
            case .legacyPostingDisabled: "Legacy recurring rules have no verified occurrence identity. Auto-posting is blocked."
            case .futureOccurrence: "This occurrence is not due yet."
            case .noProgress: "The next recurring date failed to advance. Nothing was committed."
            case .tooManyOccurrences: "More than 24 past occurrences. Review the rule before posting."
            case .existingOccurrence: "An occurrence already exists. Nothing was committed."
            }
        }
    }

    static let managedRecurringTag = "FinTrackMac-V1.6-idempotent"
    static let reviewedRecurringTag = "[FTReviewedRecurring]"
    static let managedDepositTag = "[FTManagedDeposit:V1.6.2]"
    static let managedLoanTag = "[FTManagedLoan:V1.6.3]"
    static func isManagedRecurring(_ rule: RecurringTransaction) -> Bool {
        rule.projectIdentifier == managedRecurringTag || (rule.note ?? "").hasPrefix(reviewedRecurringTag)
    }

    private static func checkedTitle(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty && value.count <= 100 else { throw Failure.invalidName }
        return value
    }

    private static func checkedRate(_ rate: Double) throws -> Double {
        guard rate.isFinite, (0...100).contains(rate) else { throw Failure.invalidRate }
        return FinancialPrecision.roundInterestRateForStorageFallback(rate)
    }

    private static func checkCurrency(_ book: String, against expected: String) throws {
        guard !book.isEmpty && book == expected else { throw Failure.currencyMismatch }
    }

    /// Prevent another finance module from silently creating a second book
    /// currency. Original Goal has no currency field and cannot be checked.
    private static func requireLedgerCurrency(_ currency: String, in context: ModelContext) throws {
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let deposits = try context.fetch(FetchDescriptor<DepositRecord>())
        let loans = try context.fetch(FetchDescriptor<LoanRule>())
        let recurring = try context.fetch(FetchDescriptor<RecurringTransaction>())
        var existing = Set(transactions.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        existing.formUnion(deposits.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        existing.formUnion(loans.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        existing.formUnion(recurring.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        guard currency.count == 3,
              currency.allSatisfy({ $0.isASCII && $0.isUppercase }),
              existing.isEmpty || (existing.count == 1 && existing.contains(currency))
        else { throw Failure.currencyMismatch }
    }

    @discardableResult
    static func addDeposit(
        bank: String, principalText: String, annualRate: Double,
        start: Date, maturity: Date, mode: DepositInterestSettlementMode,
        currency: String, originalCurrency: String? = nil,
        principalRate: Double? = nil, expectedInterestRate: Double? = nil,
        notificationsEnabled: Bool = false, reminder: MacReminderSettings? = nil, userNote: String = "", expectedInterestOverride: Double? = nil,
        saveImmediately: Bool = true, in context: ModelContext
    ) throws -> DepositRecord {
        let bank = try checkedTitle(bank)
        try reminder?.validate()
        let principal = try MacTransactionCRUD.amount(principalText)
        let rate = try checkedRate(annualRate)
        guard maturity > start else { throw Failure.invalidDateRange }
        try requireLedgerCurrency(currency, in: context)
        let terms = try MacDepositTerms.calculate(principal: principal, annualRate: rate, start: start, maturity: maturity, mode: mode, expectedOverride: expectedInterestOverride)
        let source = try MacCurrency.code(originalCurrency ?? currency)
        let principalSnapshot = try MacCurrency.snapshot(amount: principal, original: source, base: currency, rate: principalRate)
        let interestSnapshot = try MacCurrency.snapshot(amount: terms.expectedInterest, original: source, base: currency, rate: expectedInterestRate)
        let deposit = DepositRecord(
            bankName: bank, principal: principal,
            originalPrincipal: principal, originalCurrency: source,
            basePrincipal: principalSnapshot.baseAmount, baseCurrencyCode: currency,
            principalExchangeRateToBase: principalSnapshot.rate,
            annualInterestRate: terms.annualRate, interestSettlementMode: mode.rawValue,
            expectedInterest: terms.expectedInterest,
            baseExpectedInterest: interestSnapshot.baseAmount,
            interestExchangeRateToBase: interestSnapshot.rate,
            isInterestManuallyEdited: terms.manuallyEdited,
            currency: source, startDate: start, maturityDate: maturity,
            nextInterestPayoutDate: mode == .monthly
                ? min(Calendar.current.date(byAdding: .month, value: 1, to: start) ?? maturity, maturity)
                : nil,
            // No automatic settlement / cash transaction until documented and
            // proven idempotent. Save the original expected-interest semantics.
            notificationsEnabled: notificationsEnabled,
            note: MacFinanceNotes.replacing(managedDepositTag, with: userNote)
        )
        if let reminder { deposit.reminderDaysBefore = reminder.daysBefore; deposit.reminderHour = reminder.hour; deposit.reminderMinute = reminder.minute }
        context.insert(deposit)
        do { if saveImmediately { try context.save() } }
        catch { context.rollback(); throw error }
        return deposit
    }

    @discardableResult
    static func addLoan(
        title: String, principalText: String, annualRate: Double,
        months: Int, method: RepaymentMethod, firstPayment: Date,
        currency: String, originalCurrency: String? = nil, exchangeRate: Double? = nil,
        totalAmount: Double? = nil, downPayment: Double = 0, category: String = "Loan", userNote: String = "", in context: ModelContext
    ) throws -> LoanRule {
        let title = try checkedTitle(title)
        let category = try MacTransactionCRUD.validatedCategory(category)
        let principal = try MacTransactionCRUD.amount(principalText)
        let rate = try checkedRate(annualRate)
        guard (1...600).contains(months) else { throw Failure.invalidTerm }
        try requireLedgerCurrency(currency, in: context)
        let source = try MacCurrency.code(originalCurrency ?? currency)
        let snapshot = try MacCurrency.snapshot(amount: principal, original: source, base: currency, rate: exchangeRate)
        guard downPayment.isFinite, downPayment >= 0,
              totalAmount == nil || (totalAmount!.isFinite && abs(totalAmount! - downPayment - principal) < 0.005)
        else { throw Failure.invalidTerm }
        let loan = LoanRule(
            title: title, totalAmount: totalAmount, downPaymentAmount: downPayment,
            downPaymentPercent: (totalAmount ?? principal) > 0 ? FinancialPrecision.roundAmountForDisplay(downPayment / (totalAmount ?? principal) * 100) : 0,
            principal: principal, basePrincipal: snapshot.baseAmount,
            baseCurrencyCode: currency, exchangeRateToBase: snapshot.rate,
            annualRate: rate, termMonths: months, method: method,
            currency: source, startDate: firstPayment,
            category: category, note: MacFinanceNotes.replacing(managedLoanTag, with: userNote) ?? managedLoanTag
        )
        context.insert(loan)
        do { try context.save() }
        catch { context.rollback(); throw error }
        return loan
    }

    @discardableResult
    static func addGoal(
        title: String, targetText: String, deadline: Date?,
        currency: String, includesCurrentAssets: Bool = true, in context: ModelContext
    ) throws -> Goal {
        let title = try checkedTitle(title)
        let target = try MacTransactionCRUD.amount(targetText)
        try requireLedgerCurrency(currency, in: context)
        // Goal is intentionally currency-less in the original schema.
        // V1.6 does not infer progress from a mixed-currency ledger.
        let profile = try context.fetch(FetchDescriptor<FinancialProfile>()).first { $0.deletedAt == nil }
        let current = MacFinancialSettings.snapshot(profile: profile,
            transactions: try context.fetch(FetchDescriptor<Transaction>()), loans: try context.fetch(FetchDescriptor<LoanRule>()),
            deposits: try context.fetch(FetchDescriptor<DepositRecord>()), currency: currency, asOf: Date())
        let goal = Goal(
            title: title, targetAmount: target, startDate: Date(),
            targetDate: deadline, includesCurrentAssets: includesCurrentAssets, creationNetWorth: current.netWorth
        )
        context.insert(goal)
        do { try context.save() }
        catch { context.rollback(); throw error }
        _ = currency  // original Goal @Model has no currency field
        return goal
    }

    @discardableResult
    static func addRecurring(
        title: String, amountText: String, type: RecurringTransactionType,
        category: String, interval: Int, unit: RecurringIntervalUnit,
        next: Date, currency: String, originalCurrency: String? = nil,
        exchangeRate: Double? = nil, notificationsEnabled: Bool = false,
        reminder: MacReminderSettings? = nil, settings: MacRecurringSettings? = nil, userNote: String = "", in context: ModelContext
    ) throws -> RecurringTransaction {
        let title = try checkedTitle(title)
        try reminder?.validate()
        if let end = settings?.endDate, end < next { throw Failure.invalidDateRange }
        let amount = try MacTransactionCRUD.amount(amountText)
        let category = try checkedTitle(category)
        guard (1...365).contains(interval) else { throw Failure.invalidRecurrence }
        try requireLedgerCurrency(currency, in: context)
        let source = try MacCurrency.code(originalCurrency ?? currency)
        let snapshot = try MacCurrency.snapshot(amount: amount, original: source, base: currency, rate: exchangeRate)
        let rule = RecurringTransaction(
            title: title, amount: amount, currency: source,
            type: type, category: category,
            projectIdentifier: managedRecurringTag,
            intervalValue: interval, intervalUnit: unit,
            nextExecutionDate: next, notificationsEnabled: notificationsEnabled,
            originalAmount: amount, originalCurrency: source,
            exchangeRateToBase: snapshot.rate, baseAmount: snapshot.baseAmount, baseCurrencyCode: currency
        )
        if let reminder { rule.reminderDaysBefore = reminder.daysBefore; rule.reminderHour = reminder.hour; rule.reminderMinute = reminder.minute }
        if let settings { rule.endDate = settings.endDate; rule.isActive = settings.isActive }
        rule.note = userNote.isEmpty ? nil : userNote
        context.insert(rule)
        do { try context.save() }
        catch { context.rollback(); throw error }
        return rule
    }

    static func nextDate(_ date: Date, value: Int, unit: String,
                         calendar: Calendar = .current) throws -> Date {
        guard value > 0 && value <= 365,
              let unit = RecurringIntervalUnit(rawValue: unit)
        else { throw Failure.invalidRecurrence }
        let component: Calendar.Component
        switch unit {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        guard let result = calendar.date(byAdding: component, value: value, to: date),
              result > date else { throw Failure.noProgress }
        return result
    }

    /// Explicit (never silent) posting, only for NEW V1.6 rules. Atomic cursor
    /// update + original Transaction insert in one ModelContext.save; occurrence
    /// marker survives app restarts. Old unmarked rules must not be replayed.
    @discardableResult
    static func postDue(
        rule: RecurringTransaction, transactions: [Transaction],
        now: Date, bookCurrency: String, exchangeRates: [Int64: Double] = [:], in context: ModelContext
    ) throws -> Int {
        guard isManagedRecurring(rule) else {
            throw Failure.legacyPostingDisabled
        }
        try checkCurrency(rule.baseCurrencyCode, against: bookCurrency)
        guard rule.originalCurrency == rule.currency, rule.exchangeRateToBase.isFinite,
              rule.exchangeRateToBase > 0,
              rule.baseAmount == FinancialPrecision.roundAmountForStorage(rule.originalAmount * rule.exchangeRateToBase) else {
            throw Failure.currencyMismatch
        }
        try requireLedgerCurrency(bookCurrency, in: context)
        guard rule.isActive, rule.deletedAt == nil,
              rule.nextExecutionDate <= now else { throw Failure.futureOccurrence }
        guard (1...365).contains(rule.intervalValue),
              RecurringIntervalUnit(rawValue: rule.intervalUnit) != nil else {
            throw Failure.invalidRecurrence
        }

        let amount = rule.originalAmount == 0 ? 0 : try MacTransactionCRUD.amount(String(rule.originalAmount))
        // Query the actual ModelContext immediately before posting: caller
        // @Query arrays may be stale across windows or refresh boundaries.
        let persisted = try context.fetch(FetchDescriptor<Transaction>())
        let existingTransactions = persisted + transactions
        var items: [(date: Date, marker: String)] = []
        var cursor = rule.nextExecutionDate
        var checked = Set<String>()
        while cursor <= now {
            if let end = rule.endDate, cursor > end { break }
            guard items.count < 24 else { throw Failure.tooManyOccurrences }
            let marker = occurrenceMarker(ruleID: rule.id, date: cursor)
            guard checked.insert(marker).inserted,
                  !existingTransactions.contains(where: { ($0.note ?? "").contains(marker) })
            else { throw Failure.existingOccurrence }
            items.append((cursor, marker))
            cursor = try nextDate(cursor, value: rule.intervalValue, unit: rule.intervalUnit)
        }
        guard !items.isEmpty else { throw Failure.futureOccurrence }
        let snapshots = try items.map { item in
            try MacCurrency.snapshot(amount: amount, original: rule.originalCurrency,
                base: bookCurrency, rate: rule.originalCurrency == bookCurrency ? 1 : exchangeRates[Int64(item.date.timeIntervalSince1970)])
        }
        do {
            for (item, snapshot) in zip(items, snapshots) where amount > 0 {
                let entry = Transaction(
                    amount: snapshot.baseAmount, currency: bookCurrency,
                    type: rule.typedType == .income ? .income : .expense,
                    category: rule.category,
                    note: "[Auto] \(rule.title) \(rule.note ?? "") \(item.marker)",
                    date: item.date, originalAmount: amount,
                    originalCurrency: rule.originalCurrency,
                    exchangeRateToBase: snapshot.rate, baseAmount: snapshot.baseAmount,
                    baseCurrencyCode: bookCurrency
                )
                context.insert(entry)
            }
            rule.lastExecutionDate = items.last?.date
            rule.baseAmount = snapshots.last!.baseAmount
            rule.exchangeRateToBase = snapshots.last!.rate
            rule.nextExecutionDate = cursor
            if let end = rule.endDate, cursor > end { rule.isActive = false }
            rule.updatedAt = now
            if rule.syncVersion < Int.max { rule.syncVersion += 1 }
            try context.save()
        } catch { context.rollback(); throw error }
        return items.count
    }

    static func occurrenceMarker(ruleID: UUID, date: Date) -> String {
        "[FTRec:\(ruleID.uuidString):\(Int64(date.timeIntervalSince1970))]"
    }
}

private extension FinancialPrecision {
    static func roundInterestRateForStorageFallback(_ amount: Double) -> Double {
        // Original application stores interest rate with four decimal places.
        var source = Decimal(amount)
        var result = Decimal()
        NSDecimalRound(&result, &source, FinancialPrecision.interestRateStorageScale, .plain)
        return NSDecimalNumber(decimal: result).doubleValue
    }
}
