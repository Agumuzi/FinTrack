import Foundation
import SwiftData

/// Read-only inspection of ORIGINAL iOS loan-generated recurring definitions.
///
/// IMPORTANT: the original RecurringTransactionManager generated Transaction
/// notes from localized text without a stable loan UUID/installment marker.
/// No arbitrary historic payment can be established as settled based on amount,
/// date or text alone; "possible" matches are strictly advisory and NEVER
/// update the original models or current ledger.
@MainActor
enum MacLegacyLoanAudit {
    struct Installment: Identifiable {
        let index: Int
        let dueDate: Date
        let scheduledAmount: Double
        let linkedRuleCount: Int
        let deletedRuleCount: Int
        let possibleCashExpenseCount: Int
        var id: Int { index }
    }

    struct Report: Identifiable {
        let id: UUID
        let loanTitle: String
        let currency: String
        let scheduledCount: Int
        let linkedRuleCount: Int
        let relationshipCount: Int
        let orphanRuleCount: Int
        let missingPeriodCount: Int
        let duplicatePeriodCount: Int
        let malformedRuleCount: Int
        let possibleCashExpenseCount: Int
        let installments: [Installment]

        // No legacy generated transaction can be *proved* paid by this audit.
        let verifiedPaidCount: Int = 0
        var requiresReconciliation: Bool { true }
        var summary: String {
            "Linked rules: \(linkedRuleCount) · Orphan rules: \(orphanRuleCount) · Missing periods: \(missingPeriodCount) · Duplicate periods: \(duplicatePeriodCount) · Unrecognized IDs: \(malformedRuleCount)"
        }
    }

    /// Does not call context.save, insert/delete, or change any @Model state.
    static func inspect(_ loan: LoanRule, in context: ModelContext) throws -> Report {
        let rules = try context.fetch(FetchDescriptor<RecurringTransaction>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        return evaluate(loan, rules: rules, transactions: transactions)
    }

    static func evaluate(
        _ loan: LoanRule, rules: [RecurringTransaction],
        transactions: [Transaction], calendar: Calendar = .current
    ) -> Report {
        let prefix = "loan_generated:\(loan.id.uuidString):"
        let matched = rules.filter {
            ($0.projectIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                .hasPrefix(prefix)
        }
        // Inspect even deleted or inactive rules; they may already have
        // triggered a historical expense. Do NOT use isActive as proof of paid.
        let linkedIDs = Set(loan.generatedRules.map(\.id))
        let orphan = matched.filter { !linkedIDs.contains($0.id) }.count
        let schedule = loan.amortizationSchedule
        var bucket: [Int: [RecurringTransaction]] = [:]
        var malformed = 0
        for rule in matched {
            let suffix = String(
                (rule.projectIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    .dropFirst(prefix.count)
            )
            guard let index = Int(suffix),
                  String(index) == suffix, (1...schedule.count).contains(index)
            else {
                malformed += 1
                continue
            }
            bucket[index, default: []].append(rule)
        }

        // This heuristic is NOT a payout reconciliation. Original language
        // settings may also format "Principal/Interest" differently; false
        // positives and false negatives are both possible.
        var lines: [Installment] = []
        var missing = 0
        var duplicates = 0
        var totalPossible = 0
        for installment in schedule {
            let linked = bucket[installment.index] ?? []
            if linked.isEmpty { missing += 1 }
            if linked.count > 1 { duplicates += 1 }
            let possible = transactions.filter { entry in
                entry.typedType == .expense &&
                entry.deletedAt == nil &&
                entry.originalCurrency == loan.currency &&
                abs(entry.originalAmount - installment.total) <= 0.011 &&
                calendar.isDate(entry.date, inSameDayAs: installment.date) &&
                LoanAnalytics.isLoanPaymentTransaction(entry)
            }.count
            totalPossible += possible
            lines.append(Installment(
                index: installment.index, dueDate: installment.date,
                scheduledAmount: installment.total,
                linkedRuleCount: linked.count,
                deletedRuleCount: linked.filter { $0.deletedAt != nil }.count,
                possibleCashExpenseCount: possible
            ))
        }
        return Report(
            id: loan.id, loanTitle: loan.title, currency: loan.currency,
            scheduledCount: schedule.count, linkedRuleCount: matched.count,
            relationshipCount: loan.generatedRules.count,
            orphanRuleCount: orphan, missingPeriodCount: missing,
            duplicatePeriodCount: duplicates,
            malformedRuleCount: malformed,
            possibleCashExpenseCount: totalPossible,
            installments: lines
        )
    }
}
