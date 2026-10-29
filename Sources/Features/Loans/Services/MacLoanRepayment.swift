import Foundation
import SwiftData

/// Manual *recording* of an actual loan payment, not a bank debit.
///
/// Reuses original LoanRule.amortizationSchedule directly, including all three
/// repayment modes, and original Transaction's original/base snapshots.
/// Only loans created by the V1.6.3 Mac form and without any old generated
/// recurring payment link are eligible. No schema migration or automation.
@MainActor
enum MacLoanRepayment {
    enum PostingError: LocalizedError {
        case legacyLoan, generatedRecurringConflict, foreignCurrency
        case notDue, allPaid, alreadyPosted, inconsistentLedger, zeroCashPayment

        var errorDescription: String? {
            switch self {
            case .legacyLoan:
                "Previous loan records require historical payment reconciliation."
            case .generatedRecurringConflict:
                "This loan already has linked scheduled repayments. Disable duplicate flows before posting."
            case .foreignCurrency:
                "Confirm the ledger currency and payment exchange rate before recording this payment."
            case .notDue:
                "This payment is not due yet."
            case .allPaid:
                "All scheduled installments already have a receipt."
            case .alreadyPosted:
                "This installment is already recorded. A duplicate was blocked."
            case .inconsistentLedger:
                "Loan payment receipts do not match the saved schedule or cash ledger. Review existing payments before recording another installment."
            case .zeroCashPayment:
                "The original schedule has a zero-amount installment; manual cash posting is not appropriate."
            }
        }
    }

    static let originalGeneratedPrefix = "loan_generated:"

    struct Preview {
        let payment: LoanAmortizationEngine.Payment
        let completedCount: Int
        let totalCount: Int
    }

    struct Recorded {
        let installment: Int
        let principal: Double
        let interest: Double
        let total: Double
    }

    static func marker(loanID: UUID, payment: LoanAmortizationEngine.Payment) -> String {
        "[FTLoan:\(loanID.uuidString):\(payment.index):\(Int64(payment.date.timeIntervalSince1970))]"
    }

    private static func receiptNote(_ loan: LoanRule, payment: LoanAmortizationEngine.Payment) -> String {
        "Loan installment \(payment.index)/\(loan.termMonths) — Principal: \(payment.principal); Interest: \(payment.interest) \(marker(loanID: loan.id, payment: payment))"
    }

    static func resolvedSchedule(_ loan: LoanRule, transactions: [Transaction], calendar: Calendar = .current) -> [LoanAmortizationEngine.Payment] {
        let pinned = MacLoanSchedule.dates(loan)
        let legacy = LoanAmortizationEngine.legacySchedule(principal: loan.principal, annualRate: loan.annualRate,
            termMonths: loan.termMonths, method: loan.method, firstPaymentDate: loan.startDate, calendar: calendar).enumerated().map { index, p in
            LoanAmortizationEngine.Payment(index: p.index, date: pinned?[index] ?? p.date, total: p.total,
                principal: p.principal, interest: p.interest, remainingBalance: p.remainingBalance)
        }
        let prefix="[FTLoan:\(loan.id.uuidString):"
        let scoped:[(Int,Transaction)]=transactions.compactMap { row in
            guard let note=row.note,let marker=note.range(of:prefix),let index=Int(note[marker.upperBound...].prefix(while:{$0 != ":"})),(1...legacy.count).contains(index) else{return nil}
            return(index,row)
        }
        var historical: [Int: LoanAmortizationEngine.Payment] = [:]
        // Original legacy receipts and reconciled-cent receipts both retain
        // their own proven date. Never infer payment from date/amount alone.
        for _ in 0..<2 {
            let candidates = historical.isEmpty ? legacy : LoanAmortizationEngine.reconciled(principal: loan.principal, schedule: legacy, historical: historical)
            for (index,row) in scoped {
                let payment=candidates[index-1]
                let dated = LoanAmortizationEngine.Payment(index: payment.index, date: row.date, total: payment.total,
                    principal: payment.principal, interest: payment.interest, remainingBalance: payment.remainingBalance)
                if row.note == receiptNote(loan, payment: dated), row.originalAmount == payment.total { historical[payment.index] = dated }
            }
        }
        return LoanAmortizationEngine.reconciled(principal: loan.principal, schedule: legacy, historical: historical)
    }

    /// Validate every receipt scoped to this loan, including deleted rows and
    /// markers that no longer match an edited schedule. Ignoring either can
    /// incorrectly advance progress or replay a previously paid installment.
    /// Only the exact note written by this adapter is supported; ambiguous
    /// identity or altered principal/interest text requires reconciliation.
    static func verifiedPaidIndices(
        _ loan: LoanRule, schedule: [LoanAmortizationEngine.Payment],
        transactions: [Transaction], book: String
    ) throws -> Set<Int> {
        let prefix = "[FTLoan:\(loan.id.uuidString):"
        let receipts = transactions.filter {
            ($0.note ?? "").range(of: prefix, options: .caseInsensitive) != nil
        }
        var indices = Set<Int>()
        for row in receipts {
            guard let payment = schedule.first(where: { row.note == receiptNote(loan, payment: $0) }),
                  row.deletedAt == nil,
                  row.type == TransactionType.expense.rawValue,
                  row.originalCurrency == loan.currency, row.baseCurrencyCode == book,
                  row.exchangeRateToBase.isFinite, row.exchangeRateToBase > 0,
                  loan.currency != book || row.exchangeRateToBase == 1,
                  row.originalAmount.isFinite, row.baseAmount.isFinite,
                  row.originalAmount == payment.total,
                  row.baseAmount == FinancialPrecision.roundAmountForStorage(payment.total * row.exchangeRateToBase),
                  row.date == payment.date,
                  indices.insert(payment.index).inserted
            else { throw PostingError.inconsistentLedger }
        }
        return indices
    }

    static func isManaged(_ loan: LoanRule) -> Bool {
        (loan.note == MacFinanceRecords.managedLoanTag || loan.note.hasPrefix(MacFinanceRecords.managedLoanTag + " ") || loan.note.hasPrefix(MacFinanceRecords.managedLoanTag + "\n")) &&
            loan.deletedAt == nil && loan.generatedRules.isEmpty
    }

    private static func oldRulesConflict(_ loan: LoanRule, rules: [RecurringTransaction]) -> Bool {
        // Original MoreToolsListRule.loanGeneratedRecurringProjectIdentifier:
        // "loan_generated:<UUID>:<paymentIndex>". Deliberately examine deleted
        // old rules as well, since they may already have created cash debits.
        let prefix = "\(originalGeneratedPrefix)\(loan.id.uuidString):"
        return !loan.generatedRules.isEmpty ||
            rules.contains(where: { ($0.projectIdentifier ?? "").hasPrefix(prefix) })
    }

    private static func validateCurrency(
        _ loan: LoanRule, book: String,
        transactions: [Transaction], deposits: [DepositRecord],
        loans: [LoanRule], recurring: [RecurringTransaction]
    ) throws {
        guard loan.baseCurrencyCode == book, loan.exchangeRateToBase.isFinite, loan.exchangeRateToBase > 0,
              loan.basePrincipal == FinancialPrecision.roundAmountForStorage(loan.principal * loan.exchangeRateToBase),
              loan.currency != book || loan.exchangeRateToBase == 1
        else { throw PostingError.foreignCurrency }
        var all = Set(transactions.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        all.formUnion(deposits.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        all.formUnion(loans.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        all.formUnion(recurring.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        guard all == Set([book]) else { throw PostingError.foreignCurrency }
    }

    /// Preview requires fetch from current SQLite-backed ModelContext. Other
    /// window/actor concurrency is NOT guaranteed without DB-level uniqueness.
    static func nextPayment(
        _ loan: LoanRule, now: Date, bookCurrency: String,
        in context: ModelContext
    ) throws -> Preview {
        guard MacLoanSchedule.valid(loan) else { throw PostingError.inconsistentLedger }
        guard isManaged(loan) else { throw PostingError.legacyLoan }
        guard !MacLoanSchedule.requiresReview(loan) else { throw MacSettingsFailure.invalid("旧贷款未保存合同所在时区，请先在贷款详情核对并固定还款日期。已有收据保持不变。") }
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let deposits = try context.fetch(FetchDescriptor<DepositRecord>())
        let loans = try context.fetch(FetchDescriptor<LoanRule>())
        let recurring = try context.fetch(FetchDescriptor<RecurringTransaction>())
        guard !oldRulesConflict(loan, rules: recurring) else {
            throw PostingError.generatedRecurringConflict
        }
        try validateCurrency(loan, book: bookCurrency, transactions: transactions,
                             deposits: deposits, loans: loans, recurring: recurring)

        let schedule = resolvedSchedule(loan, transactions: transactions)
        let paid = try verifiedPaidIndices(loan, schedule: schedule,
                                          transactions: transactions, book: bookCurrency)
        // A posted later period with an earlier period missing is unsafe:
        // never guess whether someone manually deleted a prior payment.
        var completed = 0
        var firstMissing: LoanAmortizationEngine.Payment?
        for payment in schedule where payment.total > 0 {
            if paid.contains(payment.index) {
                guard firstMissing == nil else { throw PostingError.inconsistentLedger }
                completed += 1
            } else if firstMissing == nil {
                firstMissing = payment
            }
        }
        guard let pending = firstMissing else { throw PostingError.allPaid }
        guard pending.total > 0, pending.total.isFinite else {
            throw PostingError.zeroCashPayment
        }
        guard Calendar.current.startOfDay(for: pending.date)
                <= Calendar.current.startOfDay(for: now)
        else { throw PostingError.notDue }
        return Preview(payment: pending, completedCount: completed,
                       totalCount: schedule.count)
    }

    /// User explicitly confirms they *already paid* this installment.
    /// Creates ONE original expense Transaction for total principal+interest;
    /// never creates another RecurringTransaction or actually transfers money.
    @discardableResult
    static func recordPaid(
        _ loan: LoanRule, now: Date, bookCurrency: String,
        expectedIndex: Int, exchangeRate: Double? = nil,
        expectedPayment: LoanAmortizationEngine.Payment? = nil,
        expectedScheduleCount: Int? = nil, expectedOriginalCurrency: String? = nil,
        saveImmediately: Bool = true, in context: ModelContext
    ) throws -> Recorded {
        try MacRecoveryJournal.assertWritable(in:context)
        let preview = try nextPayment(loan, now: now, bookCurrency: bookCurrency,
                                      in: context)
        guard preview.payment.index == expectedIndex else {
            throw PostingError.alreadyPosted
        }
        let payment = preview.payment
        guard expectedOriginalCurrency == nil || expectedOriginalCurrency == loan.currency else { throw PostingError.inconsistentLedger }
        if let expected = expectedPayment {
            guard payment.date == expected.date, payment.principal == expected.principal,
                  payment.interest == expected.interest, payment.total == expected.total,
                  expectedScheduleCount == nil || expectedScheduleCount == preview.totalCount
            else { throw PostingError.inconsistentLedger }
        }
        let snapshot = try MacCurrency.snapshot(amount: payment.total,
            original: loan.currency, base: bookCurrency, rate: exchangeRate)
        // Original LoanAnalytics recognizes legacy labels "Principal:" and
        // "Interest:"; preserve them for future cash/debt reconciliation.
        let note = receiptNote(loan, payment: payment)
        let transaction = Transaction(
            amount: snapshot.baseAmount, currency: bookCurrency, type: .expense,
            category: loan.category, note: note, date: payment.date,
            originalAmount: payment.total, originalCurrency: loan.currency,
            exchangeRateToBase: snapshot.rate, baseAmount: snapshot.baseAmount,
            baseCurrencyCode: bookCurrency
        )
        context.insert(transaction)
        do { if saveImmediately { try context.save() } }
        catch { context.rollback(); throw error }
        return Recorded(installment: payment.index, principal: payment.principal,
                        interest: payment.interest, total: payment.total)
    }
}
