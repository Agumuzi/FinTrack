import Foundation
import SwiftData
import SwiftUI

enum MacClearKind: String, CaseIterable, Identifiable {
    case records = "账目", deposits = "存款", loans = "贷款", recurring = "周期", goals = "财务目标"
    var id: String { rawValue }
}

enum MacSelectiveDataClear {
    struct Preview: Equatable {
        var records: Set<UUID> = [], deposits: Set<UUID> = [], loans: Set<UUID> = [], recurring: Set<UUID> = [], goals: Set<UUID> = []
        var total: Int { records.count + deposits.count + loans.count + recurring.count + goals.count }
        var summary: String { L10n.format("mac.selectiveDataClear.summary.dc760ada4e", Int64(records.count), Int64(deposits.count), Int64(loans.count), Int64(recurring.count), Int64(goals.count)) }
    }
    static func preview(_ kinds: Set<MacClearKind>, generated: Bool, in context: ModelContext) throws -> Preview {
        var result = Preview()
        let loans = try context.fetch(FetchDescriptor<LoanRule>())
        let loanRuleIDs = Set(loans.flatMap { $0.generatedRules.map(\.id) })
        if kinds.contains(.records) { result.records = Set(try context.fetch(FetchDescriptor<Transaction>()).filter { $0.deletedAt == nil && (generated || !MacTransactionCRUD.isProtectedGeneratedPosting($0)) }.map(\.id)) }
        if kinds.contains(.deposits) { result.deposits = Set(try context.fetch(FetchDescriptor<DepositRecord>()).filter { $0.deletedAt == nil }.map(\.id)) }
        if kinds.contains(.loans) { result.loans = Set(loans.filter { $0.deletedAt == nil }.map(\.id)) }
        result.recurring = Set(try context.fetch(FetchDescriptor<RecurringTransaction>()).filter { row in
            let owner = loans.first { $0.generatedRules.contains { $0.id == row.id } || (row.projectIdentifier ?? "").hasPrefix("loan_generated:\($0.id.uuidString):") }
            return row.deletedAt == nil && (owner.map { result.loans.contains($0.id) } ?? (kinds.contains(.recurring) && !loanRuleIDs.contains(row.id) && !(row.projectIdentifier ?? "").hasPrefix("loan_generated:")))
        }.map(\.id))
        if kinds.contains(.goals) { result.goals = Set(try context.fetch(FetchDescriptor<Goal>()).filter { $0.deletedAt == nil }.map(\.id)) }
        return result
    }
    static func apply(_ expected: Preview, kinds: Set<MacClearKind>, generated: Bool, in context: ModelContext,
                      save: ((ModelContext) throws -> Void)? = nil) throws {
        try MacRecoveryJournal.assertWritable(in: context)
        guard !MacAutomaticPosting.isRunning, !context.hasChanges else { throw MacSettingsFailure.invalid(L10n.text("mac.selectiveDataClear.apply.7effbf1ede")) }
        guard try preview(kinds, generated: generated, in: context) == expected else { throw MacSettingsFailure.invalid(L10n.text("mac.selectiveDataClear.apply.333048b646")) }
        let now = Date()
        do {
            // Keep identity tombstones and receipt markers, so a removed posting
            // cannot be silently recreated by a rewound or restored rule.
            for row in try context.fetch(FetchDescriptor<Transaction>()) where expected.records.contains(row.id) { row.deletedAt = now; row.updatedAt = now }
            for row in try context.fetch(FetchDescriptor<DepositRecord>()) where expected.deposits.contains(row.id) { row.deletedAt = now; row.isActive = false; row.updatedAt = now }
            for row in try context.fetch(FetchDescriptor<LoanRule>()) where expected.loans.contains(row.id) { row.deletedAt = now; row.updatedAt = now }
            for row in try context.fetch(FetchDescriptor<RecurringTransaction>()) where expected.recurring.contains(row.id) { row.deletedAt = now; row.isActive = false; row.updatedAt = now }
            for row in try context.fetch(FetchDescriptor<Goal>()) where expected.goals.contains(row.id) { row.deletedAt = now; row.updatedAt = now }
            if let save { try save(context) } else { try context.save() }
        } catch { context.rollback(); throw error }
    }
}

struct MacSelectiveDataClearView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var initialKind: MacClearKind = .records
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var preview: MacSelectiveDataClear.Preview?
    @State private var entries: [String] = []
    @State private var error: String?
    var body: some View {
        MacFormShell(width: 540) { Text(L10n.text("mac.selectiveDataClear.MacFormShell.bf27298df5") + L10n.builtIn(initialKind.rawValue)).appFont(.dialogTitle, weight: .semibold) } fields: {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("mac.selectiveDataClear.MacFormShell.35ed8102f8")).foregroundStyle(.secondary)
                if let preview {
                    Text(preview.summary).appFont(.body, weight: .semibold)
                    if preview.total == 0 { Text(L10n.text("mac.selectiveDataClear.MacFormShell.74ef13becc")).foregroundStyle(.secondary) }
                    else {
                        ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(Array(entries.enumerated()), id: \.offset) { _, title in Text(title).appFont(.caption).frame(maxWidth: .infinity, alignment: .leading) } } }.frame(height: min(230, CGFloat(max(1, entries.count)) * 28))
                        if entries.count == 20 { Text(L10n.text("mac.selectiveDataClear.MacFormShell.21f3feae82")).appFont(.caption).foregroundStyle(.secondary) }
                    }
                }
                Text(initialKind == .records ? L10n.text("mac.selectiveDataClear.MacFormShell.9eea26e083") : L10n.text("mac.selectiveDataClear.MacFormShell.c651fdd120")).appFont(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
        } footer: {
            HStack {
                Button(L10n.text("mac.selectiveDataClear.MacFormShell.2cd0f3be87")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer()
                Button(L10n.text("mac.selectiveDataClear.MacFormShell.7ba2d6728f"), role: .destructive) {
                    guard let preview else { return }
                    do { try MacSelectiveDataClear.apply(preview, kinds: [initialKind], generated: true, in: context); Task { try? await MacNotifications.schedule(in: context) }; dismiss() }
                    catch { self.error = MacLocalization.error(error); refresh() }
                }.disabled(preview == nil || preview?.total == 0)
            }
        }.onAppear { refresh() }
    }
    private func refresh() {
        do {
            preview = try MacSelectiveDataClear.preview([initialKind], generated: true, in: context)
            switch initialKind {
            case .records: entries = Array(try context.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])).filter { $0.deletedAt == nil }.prefix(20).map { MacDateDisplay.string($0.date) + " · " + MacOverviewStyle.category($0.category) + " · " + MacOverviewStyle.money($0.originalAmount) + " " + $0.originalCurrency })
            case .deposits: entries = Array(try context.fetch(FetchDescriptor<DepositRecord>()).filter { $0.deletedAt == nil }.prefix(20).map { $0.bankName + " · " + MacOverviewStyle.money($0.originalPrincipal) + " " + $0.originalCurrency })
            case .loans: entries = Array(try context.fetch(FetchDescriptor<LoanRule>()).filter { $0.deletedAt == nil }.prefix(20).map { $0.title + " · " + MacOverviewStyle.money($0.principal) + " " + $0.currency })
            case .recurring: entries = Array(try context.fetch(FetchDescriptor<RecurringTransaction>()).filter { preview?.recurring.contains($0.id) == true }.prefix(20).map { $0.title + " · " + MacOverviewStyle.money($0.originalAmount) + " " + $0.originalCurrency })
            case .goals: entries = Array(try context.fetch(FetchDescriptor<Goal>()).filter { $0.deletedAt == nil }.prefix(20).map { $0.title + " · " + MacOverviewStyle.money($0.targetAmount) })
            }
        } catch { self.error = MacLocalization.error(error); preview = nil }
    }
}
