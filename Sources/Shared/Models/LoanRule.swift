import Foundation
import SwiftData

enum RepaymentMethod: String, CaseIterable, Codable, Identifiable {
    case equalPayment = "Equal Payment"
    case equalPrincipal = "Equal Principal"
    case interestOnly = "Interest Only"

    var id: String { rawValue }
}

@Model
final class LoanRule {
    var id: UUID
    var ownerUID: String?
    var title: String
    var totalAmount: Double
    var downPaymentAmount: Double
    var downPaymentPercent: Double
    var principal: Double
    var basePrincipal: Double
    var baseCurrencyCode: String
    var exchangeRateToBase: Double
    var annualRate: Double
    var termMonths: Int
    var methodRawValue: String
    var currency: String
    var startDate: Date
    var category: String
    var note: String
    @Relationship(deleteRule: .nullify) var generatedRules: [RecurringTransaction]
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int

    var method: RepaymentMethod {
        get { RepaymentMethod(rawValue: methodRawValue) ?? .equalPayment }
        set { methodRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ownerUID: String? = nil,
        title: String,
        totalAmount: Double? = nil,
        downPaymentAmount: Double = 0,
        downPaymentPercent: Double = 0,
        principal: Double,
        basePrincipal: Double? = nil,
        baseCurrencyCode: String? = nil,
        exchangeRateToBase: Double = 1.0,
        annualRate: Double,
        termMonths: Int,
        methodRawValue: String,
        currency: String,
        startDate: Date,
        category: String,
        note: String = "",
        generatedRules: [RecurringTransaction] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedDeviceID: String = SyncMetadataDefaults.currentDeviceID,
        syncVersion: Int = 1
    ) {
        self.id = id
        self.ownerUID = ownerUID
        self.title = title
        self.totalAmount = totalAmount ?? principal
        self.downPaymentAmount = downPaymentAmount
        self.downPaymentPercent = downPaymentPercent
        self.principal = principal
        self.basePrincipal = basePrincipal ?? principal
        self.baseCurrencyCode = baseCurrencyCode ?? currency
        self.exchangeRateToBase = exchangeRateToBase
        self.annualRate = annualRate
        self.termMonths = termMonths
        self.methodRawValue = methodRawValue
        self.currency = currency
        self.startDate = startDate
        self.category = category
        self.note = note
        self.generatedRules = generatedRules
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedDeviceID = lastModifiedDeviceID
        self.syncVersion = syncVersion
    }

    convenience init(
        id: UUID = UUID(),
        ownerUID: String? = nil,
        title: String,
        totalAmount: Double? = nil,
        downPaymentAmount: Double = 0,
        downPaymentPercent: Double = 0,
        principal: Double,
        basePrincipal: Double? = nil,
        baseCurrencyCode: String? = nil,
        exchangeRateToBase: Double = 1.0,
        annualRate: Double,
        termMonths: Int,
        method: RepaymentMethod,
        currency: String,
        startDate: Date,
        category: String,
        note: String = "",
        generatedRules: [RecurringTransaction] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedDeviceID: String = SyncMetadataDefaults.currentDeviceID,
        syncVersion: Int = 1
    ) {
        self.init(
            id: id,
            ownerUID: ownerUID,
            title: title,
            totalAmount: totalAmount,
            downPaymentAmount: downPaymentAmount,
            downPaymentPercent: downPaymentPercent,
            principal: principal,
            basePrincipal: basePrincipal,
            baseCurrencyCode: baseCurrencyCode,
            exchangeRateToBase: exchangeRateToBase,
            annualRate: annualRate,
            termMonths: termMonths,
            methodRawValue: method.rawValue,
            currency: currency,
            startDate: startDate,
            category: category,
            note: note,
            generatedRules: generatedRules,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModifiedDeviceID: lastModifiedDeviceID,
            syncVersion: syncVersion
        )
    }
}

struct LoanAmortizationEngine {
    struct Payment {
        let index: Int
        let date: Date
        let total: Double
        let principal: Double
        let interest: Double
        let remainingBalance: Double
    }

    /// Round cash principal cumulatively and settle the remaining cents in the
    /// final installment. Verified historical payments may retain the original
    /// components; only future cash payments absorb the rounding difference.
    static func reconciled(principal: Double, schedule: [Payment], historical: [Int: Payment] = [:]) -> [Payment] {
        guard principal.isFinite,principal>0 else{return []}
        var balance = FinancialPrecision.roundAmountForStorage(principal)
        return schedule.map { payment in
            let saved = historical[payment.index]
            let principalPart = saved?.principal ?? (payment.index == schedule.last?.index ? balance : min(balance, payment.principal))
            let interest = saved?.interest ?? payment.interest
            balance = FinancialPrecision.roundAmountForStorage(max(0, balance - principalPart))
            return Payment(index: payment.index, date: saved?.date ?? payment.date,
                           total: saved?.total ?? FinancialPrecision.roundAmountForStorage(principalPart + interest),
                           principal: principalPart, interest: interest,
                           remainingBalance: balance)
        }
    }

    static func schedule(principal: Double, annualRate: Double, termMonths: Int,
                         method: RepaymentMethod, firstPaymentDate: Date) -> [Payment] {
        reconciled(principal: principal, schedule: legacySchedule(principal: principal, annualRate: annualRate,
            termMonths: termMonths, method: method, firstPaymentDate: firstPaymentDate))
    }

    static func legacySchedule(
        principal: Double,
        annualRate: Double,
        termMonths: Int,
        method: RepaymentMethod,
        firstPaymentDate: Date
    ) -> [Payment] {
        guard principal.isFinite,principal>0,annualRate.isFinite,(1...600).contains(termMonths),firstPaymentDate.timeIntervalSince1970.isFinite,abs(firstPaymentDate.timeIntervalSince1970)<253402300800 else{return []}

        let calendar = Calendar.current
        let monthlyRate = max(annualRate, 0) / 100 / 12
        var balance = principal
        var payments: [Payment] = []

        let equalPaymentTotal: Double = {
            guard method == .equalPayment else { return 0 }
            guard monthlyRate > 0 else { return principal / Double(termMonths) }

            let factor = pow(1 + monthlyRate, Double(termMonths))
            return principal * monthlyRate * factor / (factor - 1)
        }()

        let equalPrincipalPart = principal / Double(termMonths)

        for index in 1...termMonths {
            let date = calendar.date(byAdding: .month, value: index - 1, to: firstPaymentDate) ?? firstPaymentDate
            let interestPart = balance * monthlyRate

            let principalPart: Double
            let totalPart: Double

            switch method {
            case .equalPayment:
                if index == termMonths {
                    principalPart = balance
                    totalPart = principalPart + interestPart
                } else {
                    let value = max(0, equalPaymentTotal - interestPart)
                    principalPart = min(value, balance)
                    totalPart = principalPart + interestPart
                }
            case .equalPrincipal:
                if index == termMonths {
                    principalPart = balance
                } else {
                    principalPart = min(equalPrincipalPart, balance)
                }
                totalPart = principalPart + interestPart
            case .interestOnly:
                if index == termMonths {
                    principalPart = balance
                    totalPart = principalPart + interestPart
                } else {
                    principalPart = 0
                    totalPart = interestPart
                }
            }

            balance = max(0, balance - principalPart)

            payments.append(
                Payment(
                    index: index,
                    date: date,
                    total: FinancialPrecision.roundAmountForStorage(totalPart),
                    principal: FinancialPrecision.roundAmountForStorage(principalPart),
                    interest: FinancialPrecision.roundAmountForStorage(interestPart),
                    remainingBalance: FinancialPrecision.roundAmountForStorage(balance)
                )
            )
        }

        return payments
    }

    static func totalInterest(schedule: [Payment]) -> Double {
        FinancialPrecision.roundAmountForStorage(schedule.reduce(0) { $0 + $1.interest })
    }

    static func totalRepayment(schedule: [Payment]) -> Double {
        FinancialPrecision.roundAmountForStorage(schedule.reduce(0) { $0 + $1.total })
    }
}

extension LoanRule {
    var usesForeignCurrency: Bool {
        currency != baseCurrencyCode
    }

    var legacyAmortizationSchedule: [LoanAmortizationEngine.Payment] {
        LoanAmortizationEngine.legacySchedule(principal: principal, annualRate: annualRate,
            termMonths: termMonths, method: method, firstPaymentDate: startDate)
    }

    var amortizationSchedule: [LoanAmortizationEngine.Payment] {
        LoanAmortizationEngine.schedule(
            principal: principal,
            annualRate: annualRate,
            termMonths: termMonths,
            method: method,
            firstPaymentDate: startDate
        )
    }

    func outstandingPrincipal(asOf date: Date = Date()) -> Double {
        let normalizedDate = date.addingTimeInterval(0)
        let schedule = amortizationSchedule

        guard let lastCompletedPayment = schedule.last(where: { $0.date <= normalizedDate }) else {
            return principal
        }

        return lastCompletedPayment.remainingBalance
    }

    func outstandingBasePrincipal(asOf date: Date = Date()) -> Double {
        FinancialPrecision.roundAmountForStorage(outstandingPrincipal(asOf: date) * exchangeRateToBase)
    }

    func nextPendingPayment(asOf date: Date = Date()) -> LoanAmortizationEngine.Payment? {
        amortizationSchedule.first(where: { $0.date > date })
    }

    func baseAmount(for payment: LoanAmortizationEngine.Payment) -> Double {
        FinancialPrecision.roundAmountForStorage(payment.total * exchangeRateToBase)
    }

    var isActiveLoan: Bool {
        outstandingPrincipal() > 0
    }
}

enum LoanAnalytics {
    struct LoanSummary {
        let firstPayment: Double
        let lastPayment: Double
        let totalInterest: Double
    }

    private struct LoanSummaryKey: Hashable {
        let id: UUID
        let principal: Double
        let annualRate: Double
        let termMonths: Int
        let method: RepaymentMethod
        let startDate: Date
    }

    private static var summaryCache: [LoanSummaryKey: LoanSummary] = [:]

    static func baseCurrencyLoans(
        from loans: [LoanRule],
        baseCurrency: String
    ) -> [LoanRule] {
        loans.filter { $0.baseCurrencyCode == baseCurrency }
    }

    static func totalOutstandingPrincipal(
        for loans: [LoanRule],
        asOf date: Date = Date()
    ) -> Double {
        loans.reduce(0) { partialResult, loan in
            partialResult + loan.outstandingBasePrincipal(asOf: date)
        }
    }

    static func nextPendingPayment(
        for loans: [LoanRule],
        asOf date: Date = Date()
    ) -> (loan: LoanRule, payment: LoanAmortizationEngine.Payment)? {
        loans.compactMap { loan in
            guard let payment = loan.nextPendingPayment(asOf: date) else { return nil }
            return (loan, payment)
        }
        .min { lhs, rhs in
            lhs.payment.date < rhs.payment.date
        }
    }

    static func summary(for loan: LoanRule) -> LoanSummary {
        let key = LoanSummaryKey(
            id: loan.id,
            principal: loan.principal,
            annualRate: loan.annualRate,
            termMonths: loan.termMonths,
            method: loan.method,
            startDate: loan.startDate
        )

        if let cached = summaryCache[key] {
            return cached
        }

        let schedule = LoanAmortizationEngine.schedule(
            principal: loan.principal,
            annualRate: loan.annualRate,
            termMonths: loan.termMonths,
            method: loan.method,
            firstPaymentDate: loan.startDate
        )
        let summary = LoanSummary(
            firstPayment: schedule.first?.total ?? 0,
            lastPayment: schedule.last?.total ?? 0,
            totalInterest: LoanAmortizationEngine.totalInterest(schedule: schedule)
        )
        summaryCache[key] = summary
        return summary
    }

    static func currentNetWorth(
        baselineNetWorth: Double,
        transactions: [Transaction],
        loans: [LoanRule],
        baseCurrency: String,
        asOf date: Date = Date()
    ) -> Double {
        let baseCurrencyTransactions = transactions.filter { $0.currency == baseCurrency }
        let income = baseCurrencyTransactions
            .filter { $0.typedType == .income }
            .reduce(0) { $0 + $1.amount }
        let expense = baseCurrencyTransactions
            .filter { $0.typedType == .expense }
            .reduce(0) { $0 + $1.amount }
        let loanBalance = totalOutstandingPrincipal(
            for: baseCurrencyLoans(from: loans, baseCurrency: baseCurrency),
            asOf: date
        )

        return baselineNetWorth + income - expense - loanBalance
    }

    static func isLoanPaymentTransaction(_ transaction: Transaction) -> Bool {
        isLoanPaymentNote(transaction.note)
    }

    static func isLoanPaymentNote(_ note: String?) -> Bool {
        guard let note else { return false }
        return note.contains("Principal:") && note.contains("Interest:")
    }
}
