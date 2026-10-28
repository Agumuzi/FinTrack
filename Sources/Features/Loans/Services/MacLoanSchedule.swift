import Foundation
import SwiftData

/// Pins the exact contract dates without changing the SwiftData schema. The
/// opaque metadata travels with native/CSV backups; UI notes hide it.
@MainActor
enum MacLoanSchedule {
    static let prefix = "[FTLoan:Schedule:"
    private struct Dates: Codable { let version: Int; let start: Date; let count: Int; let dates: [Date] }
    static func metadata(_ note: String) -> String? {
        guard let start = note.range(of: prefix), let end = note[start.upperBound...].firstIndex(of: "]") else { return nil }
        return String(note[start.lowerBound...end])
    }
    static func dates(_ loan: LoanRule) -> [Date]? {
        guard let text = metadata(loan.note), let bytes = Data(base64Encoded: String(text.dropFirst(prefix.count).dropLast())),
              let saved = try? JSONDecoder().decode(Dates.self, from: bytes), saved.version == 1,
              saved.count == loan.termMonths, saved.dates.count == loan.termMonths,
              saved.dates.allSatisfy({$0.timeIntervalSince1970.isFinite && abs($0.timeIntervalSince1970)<253402300800}),
              saved.start.timeIntervalSince1970.isFinite,abs(saved.start.timeIntervalSince1970)<253402300800,
              loan.startDate.timeIntervalSince1970.isFinite,abs(loan.startDate.timeIntervalSince1970)<253402300800,
              Int64(saved.start.timeIntervalSince1970) == Int64(loan.startDate.timeIntervalSince1970),
              saved.dates.first.map({Int64($0.timeIntervalSince1970)}) == Int64(loan.startDate.timeIntervalSince1970),
              zip(saved.dates, saved.dates.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        return saved.dates
    }
    static func valid(_ loan: LoanRule) -> Bool {loan.startDate.timeIntervalSince1970.isFinite && abs(loan.startDate.timeIntervalSince1970)<253402300800 && (!loan.note.contains(prefix) || dates(loan) != nil)}
    static func pin(_ loan: LoanRule) throws {
        let schedule = LoanAmortizationEngine.legacySchedule(principal: loan.principal, annualRate: loan.annualRate,
            termMonths: loan.termMonths, method: loan.method, firstPaymentDate: loan.startDate)
        guard schedule.count == loan.termMonths, zip(schedule, schedule.dropFirst()).allSatisfy({ $0.date < $1.date }) else {
            throw MacSettingsFailure.invalid("贷款计划日期无效，请核对首期日期和期数。")
        }
        let bytes = try JSONEncoder().encode(Dates(version: 1, start: loan.startDate, count: loan.termMonths, dates: schedule.map(\.date)))
        let clean = loan.note.replacingOccurrences(of: #"\[FTLoan(?::Schedule|Schedule):[^\]]*\]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        loan.note = clean + "\n" + prefix + bytes.base64EncodedString() + "]"
    }
    static func pinExisting(in context: ModelContext) throws {
        for loan in try context.fetch(FetchDescriptor<LoanRule>()) where MacLoanRepayment.isManaged(loan) && !loan.note.contains(prefix) {
            do { try pin(loan) }
            catch { loan.note += "\n" + prefix + "invalid]" }
        }
        if context.hasChanges { try context.save() }
    }
}
