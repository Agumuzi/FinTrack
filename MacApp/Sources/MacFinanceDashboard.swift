import SwiftUI
import SwiftData

/// Functional native Mac forms backed by the ORIGINAL financial @Models.
/// Existing histories use an explicit review boundary before automated posting.
struct MacFinanceDashboard: View {
    @Environment(\.modelContext) private var context
    @AppStorage("base_currency") private var preferredCurrency = "USD"
    @Query(sort: \DepositRecord.createdAt, order: .reverse) private var deposits: [DepositRecord]
    @Query(sort: \LoanRule.createdAt, order: .reverse) private var loans: [LoanRule]
    @Query(sort: \RecurringTransaction.createdAt, order: .reverse) private var recurring: [RecurringTransaction]
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Query private var transactions: [Transaction]
    @Query(sort: \FinancialProfile.createdAt) private var profiles: [FinancialProfile]

    typealias Panel = MacFinancePanel
    @State private var panel: Panel
    init(initialPanel: Panel = .deposits) {
        _panel = State(initialValue: initialPanel)
    }
    @State private var showingEditor = false
    @State private var editingRecord: MacFinanceRecord?
    @State private var retiringRecord: MacFinanceRecord?
    @State private var reviewingRecord: MacFinanceRecord?
    @State private var scheduleLoan: LoanRule?
    @State private var scheduleRecurring: RecurringTransaction?
    @State private var scheduleDeposit: DepositRecord?
    @State private var depositForConfirmation: DepositRecord?
    private struct LoanConfirmation: Identifiable {
        let loan: LoanRule
        let preview: MacLoanRepayment.Preview
        let bookCurrency: String
        let originalCurrency: String
        var id: UUID { loan.id }
    }
    @State private var loanConfirmation: LoanConfirmation?
    @State private var loanPaymentRate = ""
    @State private var loadingLoanRate = false
    @State private var legacyLoanReport: MacLegacyLoanAudit.Report?
    private var usesIsolatedTestLedger: Bool {
        let e = ProcessInfo.processInfo.environment
        return e["FINTRACK_V13_TEST_STORE_PATH"]?.contains("/FinTrack-V13-") == true
    }
    @State private var actionError: String?
    @State private var actionMessage: String?
    private var addTitle: LocalizedStringKey {
        switch panel {
        case .deposits: "New deposit"
        case .loans: "New loan"
        case .recurring: "New recurring rule"
        case .goals: "New goal"
        }
    }

    private var currency: String? {
        var currencies = Set(transactions.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        currencies.formUnion(deposits.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        currencies.formUnion(loans.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        currencies.formUnion(recurring.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        if currencies.count > 1 { return nil }
        return currencies.first ?? preferredCurrency
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            HStack {
                Text("Finance")
                    .appFont(.pageTitle, weight: .semibold)
                    .accessibilityIdentifier("financePageTitle")
                Spacer()
                Button(addTitle) {
                    showingEditor = true
                }
                .accessibilityIdentifier("financeAdd")
                .disabled(currency == nil)
            }

            Text("Confirm deposit interest and loan payments here. Review imported histories before posting; optional automatic posting is available in Settings.")
                .appFont(.caption, weight: .regular)
                .foregroundStyle(.secondary)
            if panel == .loans && usesIsolatedTestLedger {
                Button("Insert fictitious due loan (CI only)") { createLoanFixture() }
                    .accessibilityIdentifier("insertDueLoanFixture")
                Button("Insert fictitious old loan (CI only)") { createLegacyLoanFixture() }
                    .accessibilityIdentifier("insertLegacyLoanFixture")
                if ProcessInfo.processInfo.environment["FINTRACK_V16_RECEIPT_AUDIT_TEST"] == "1" {
                    Button("Damage fictitious loan receipt (test only)") { damageLoanReceiptFixture() }
                        .accessibilityIdentifier("damageLoanReceiptFixture")
                }
            }
            if panel == .deposits && usesIsolatedTestLedger {
                Button("Insert fictitious matured deposit (CI only)") {
                    createDueFixture()
                }
                .accessibilityIdentifier("insertDueDepositFixture")
            }

            Picker("Finance section", selection: $panel) {
                ForEach(Panel.allCases) { item in
                    Text(LocalizedStringKey(item.rawValue)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("financeSection")

            if let currency {
                Text("Ledger currency: \(currency)")
                    .foregroundStyle(.secondary)
            } else {
                Text("Different base currencies — review them in Settings before adding records.")
                    .foregroundStyle(.red)
            }

            if let actionError {
                Text(actionError).foregroundStyle(.red)
                    .accessibilityIdentifier("financeActionError")
            }
            if let actionMessage {
                Text(actionMessage)
                    .accessibilityIdentifier("financeActionMessage")
            }
            Group {
                switch panel {
                case .deposits: depositList
                case .loans: loanList
                case .recurring: recurringList
                case .goals: goalList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .appPadding(24)
        .navigationTitle("Finance")
        .sheet(isPresented: $showingEditor) {
            if let currency {
                MacFinanceEditor(panel: panel, currency: currency) {
                    actionError = nil
                    actionMessage = MacLocalization.value("Finance record saved")
                }
            }
        }
        .sheet(item: $editingRecord) { record in
            if let currency {
                MacFinanceEditor(panel: record.panel, currency: currency, existing: record) {
                    actionError = nil; actionMessage = "Saved changes"
                }
            }
        }
        .sheet(item: $reviewingRecord) { MacFinanceReviewView(record: $0) }
        .sheet(item: $scheduleLoan) { MacLoanScheduleView(loan: $0) }
        .sheet(item: $scheduleRecurring) { MacRecurringScheduleView(rule: $0) }
        .sheet(item: $scheduleDeposit) { MacDepositScheduleView(deposit: $0) }
        .task(id: notificationSignature) { try? await MacNotifications.schedule(in: context) }
        .sheet(item: $retiringRecord) { record in
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
                Text("Remove finance record?").appFont(.dialogTitle, weight: .semibold)
                Text("Posted transactions remain in the ledger. This record and its scheduled rules will no longer run.")
                HStack {
                    Spacer()
                    Button("Cancel") { retiringRecord = nil }
                    Button("Remove", role: .destructive) {
                        do { try MacFinanceEditing.retire(record, in: context); retiringRecord = nil }
                        catch { actionError = MacLocalization.error(error) }
                    }.accessibilityIdentifier("confirmRemoveFinance")
                }
            }.appPadding(24).appDialog(width: 500)
        }
        .sheet(item: $legacyLoanReport) { report in
            VStack(alignment: .leading, spacing: MacUI.space(12)) {
                Text("Legacy loan · read-only audit")
                    .appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("legacyLoanAuditTitle")
                Text(report.loanTitle).appFont(.section, weight: .semibold)
                Text(report.summary)
                    .accessibilityIdentifier("legacyLoanAuditSummary")
                Text("Potential historic expense matches: \(report.possibleCashExpenseCount); verified paid installments: 0.")
                    .accessibilityIdentifier("legacyLoanAuditUnverified")
                Text("Original iOS generated receipts do not contain a stable loan UUID or installment ID. Similar dates, amounts and notes are NOT proof of payment. Nothing here changes your ledger.")
                    .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                List(report.installments) { row in
                    HStack {
                        Text("Period \(row.index) · \(row.scheduledAmount.formatted(.number.precision(.fractionLength(2)))) \(report.currency)")
                        Spacer()
                        Text("Rules \(row.linkedRuleCount) · candidates \(row.possibleCashExpenseCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: MacUI.space(180))
                HStack {
                    Spacer()
                    Button("Close read-only report") { legacyLoanReport = nil }
                        .accessibilityIdentifier("closeLegacyLoanAudit")
                }
            }
            .appPadding(24).appPanel(width: 700, height: 440)
        }
        .sheet(item: $loanConfirmation) { item in
            let loan = item.loan
            let pending = item.preview
            VStack(alignment: .leading, spacing: MacUI.space(14)) {
                Text("Record paid loan installment?")
                    .appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("confirmLoanPaymentTitle")
                Text("Installment \(pending.payment.index)/\(pending.totalCount) · Total: \(pending.payment.total.formatted(.number.precision(.fractionLength(2)))) \(loan.currency)")
                    .accessibilityIdentifier("loanExpectedPayment")
                Text("Principal: \(pending.payment.principal.formatted(.number.precision(.fractionLength(2)))) · Interest: \(pending.payment.interest.formatted(.number.precision(.fractionLength(2))))")
                if loan.currency != item.bookCurrency {
                    Text("Book currency: \(item.bookCurrency)")
                    TextField("Payment exchange rate to book currency", text: $loanPaymentRate)
                        .accessibilityIdentifier("loanPaymentExchangeRate")
                    Button("Get rate for payment date") {
                        loadingLoanRate = true
                        Task { @MainActor in
                            defer { loadingLoanRate = false }
                            do {
                                let rate = try await MacExchangeRates.shared.quote(from: loan.currency, to: item.bookCurrency, on: pending.payment.date)
                                if loanConfirmation?.id == item.id { loanPaymentRate = String(rate) }
                            } catch { actionError = MacLocalization.error(error) }
                        }
                    }.disabled(loadingLoanRate)
                }
                Text("Only confirm if you actually paid this amount. This records a ledger expense; it does not transfer funds or run the old loan recurring rules.")
                    .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { loanConfirmation = nil }
                    Button("Confirm paid installment") {
                        postLoanPayment(loan, preview: pending, bookCurrency: item.bookCurrency, originalCurrency: item.originalCurrency)
                        loanConfirmation = nil
                    }
                    .accessibilityIdentifier("confirmLoanPayment")
                    .disabled(loadingLoanRate || (loan.currency != item.bookCurrency && loanPaymentRate.isEmpty))
                }
            }
            .appPadding(24).appDialog(width: 510)
        }
        .sheet(item: $depositForConfirmation) { deposit in
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
                Text("Post bank interest?")
                    .appFont(.dialogTitle, weight: .semibold)
                    .accessibilityIdentifier("confirmDepositInterestTitle")
                Text("Only accrued interest from this deposit will be posted as income; principal stays in the deposit. No automatic rollover or withdrawal.")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { depositForConfirmation = nil }
                    Button("Confirm interest receipt") {
                        postDepositInterest(deposit)
                        depositForConfirmation = nil
                    }
                    .accessibilityIdentifier("confirmDepositInterest")
                }
            }
            .appPadding(24)
            .appDialog(width: 500)
        }
    }

    private var depositList: some View {
        List {
            ForEach(deposits.filter { $0.deletedAt == nil }, id: \.id) { deposit in
                VStack(alignment: .leading, spacing: MacUI.space(4)) {
                    Text(deposit.bankName).appFont(.section, weight: .semibold)
                    recordActions(.deposit(deposit))
                    Button("View schedule") { scheduleDeposit = deposit }
                    Text("Principal \(deposit.originalPrincipal.formatted()) \(deposit.originalCurrency) · \(deposit.typedInterestSettlementMode.rawValue)")
                    Text("Expected interest: \(deposit.expectedInterest.formatted(.number.precision(.fractionLength(2)))) \(deposit.originalCurrency)")
                        .accessibilityIdentifier("depositExpectedInterest")
                    HStack {
                        Text("Matures \(deposit.maturityDate.formatted(date: .abbreviated, time: .omitted))")
                            .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        Spacer()
                        if deposit.hasCreditedInterest {
                            Text("Interest settled").foregroundStyle(.secondary)
                                .accessibilityIdentifier("depositInterestSettled")
                        } else if MacDepositSettlement.isManaged(deposit) {
                            Button("Post due interest") { depositForConfirmation = deposit }
                                .accessibilityIdentifier("postDepositInterest-\(deposit.id.uuidString)")
                                .disabled(currency == nil || !MacDepositSettlement.isEligible(deposit))
                        } else {
                            Text("Legacy interest: manual reconciliation required")
                                .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        }
                    }
                }.appPadding(.vertical, 3)
            }
        }
        .overlay {
            if deposits.filter({ $0.deletedAt == nil }).isEmpty {
                ContentUnavailableView("No deposits", systemImage: "building.columns")
            }
        }
        .accessibilityIdentifier("financeDepositList")
    }

    private var loanList: some View {
        List {
            ForEach(loans.filter { $0.deletedAt == nil }, id: \.id) { loan in
                VStack(alignment: .leading, spacing: MacUI.space(4)) {
                    Text(loan.title).appFont(.section, weight: .semibold)
                    recordActions(.loan(loan))
                    Button("View schedule") { scheduleLoan = loan }
                        .accessibilityIdentifier("viewLoanSchedule-\(loan.id.uuidString)")
                    Text("Principal: \(loan.principal.formatted()) \(loan.currency) · \(loan.method.rawValue)")
                    let schedule = loan.amortizationSchedule
                    Text("Payments: \(schedule.count) · total interest: \(LoanAmortizationEngine.totalInterest(schedule: schedule).formatted(.number.precision(.fractionLength(2)))) \(loan.currency)")
                        .accessibilityIdentifier("loanScheduleSummary")
                    HStack {
                        Text("Projected schedule; real payments require confirmation")
                            .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        Spacer()
                        if MacLoanRepayment.isManaged(loan) {
                            Button("Record paid installment") { prepareLoanPayment(loan) }
                                .accessibilityIdentifier("recordLoanPayment-\(loan.id.uuidString)")
                                .disabled(currency == nil)
                        } else {
                            Button("Inspect legacy links") { inspectLegacyLoan(loan) }
                                .accessibilityIdentifier("inspectLegacyLoan-\(loan.id.uuidString)")
                        }
                    }
                }.appPadding(.vertical, 3)
            }
        }
        .overlay {
            if loans.filter({ $0.deletedAt == nil }).isEmpty {
                ContentUnavailableView("No loans", systemImage: "calendar.badge.clock")
            }
        }
    }

    private var recurringList: some View {
        List {
            ForEach(recurring.filter { $0.deletedAt == nil }, id: \.id) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: MacUI.space(4)) {
                        Text(rule.title).appFont(.section, weight: .semibold)
                        recordActions(.recurring(rule))
                        Button("View schedule") { scheduleRecurring = rule }
                        Text("\(rule.type) \(rule.originalAmount.formatted()) \(rule.originalCurrency) · every \(rule.intervalValue) \(rule.intervalUnit)")
                        Text("Next: \(rule.nextExecutionDate.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Post due") { post(rule) }
                        .accessibilityIdentifier("postRecurring-\(rule.id.uuidString)")
                        .disabled(currency == nil || !rule.isActive
                                  || !MacFinanceRecords.isManagedRecurring(rule)
                                  || rule.nextExecutionDate > Date())
                }
            }
        }
        .overlay {
            if recurring.filter({ $0.deletedAt == nil }).isEmpty {
                ContentUnavailableView("No recurring rules", systemImage: "repeat")
            }
        }
    }

    private var notificationSignature: String {
        deposits.map { "\($0.id):\($0.updatedAt.timeIntervalSince1970):\($0.isActive):\($0.hasCreditedInterest)" }.joined()
        + recurring.map { "\($0.id):\($0.updatedAt.timeIntervalSince1970):\($0.nextExecutionDate.timeIntervalSince1970):\($0.isActive)" }.joined()
    }

    private var goalList: some View {
        List {
            ForEach(goals.filter { $0.deletedAt == nil }, id: \.id) { goal in
                VStack(alignment: .leading, spacing: MacUI.space(4)) {
                    Text(goal.title).appFont(.section, weight: .semibold)
                    recordActions(.goal(goal))
                    Text("Target: \(goal.targetAmount.formatted())")
                        .accessibilityIdentifier("goalTargetValue")
                    if let currency {
                        let profile = profiles.first { $0.deletedAt == nil }
                        let value = MacFinancialSettings.snapshot(profile: profile, transactions: transactions, loans: loans,
                            deposits: deposits, currency: currency, asOf: Date())
                        let baseline = Goal.baselineNetWorth(from: profile)
                        ProgressView(value: goal.clampedProgressValue(currentNetWorth: value.netWorth, baselineNetWorth: baseline))
                        Text("\(goal.displayPercent(currentNetWorth: value.netWorth, baselineNetWorth: baseline))%")
                    }
                }.appPadding(.vertical, 3)
            }
        }
        .overlay {
            if goals.filter({ $0.deletedAt == nil }).isEmpty {
                ContentUnavailableView("No goals", systemImage: "target")
            }
        }
    }

    private func inspectLegacyLoan(_ loan: LoanRule) {
        do {
            legacyLoanReport = try MacLegacyLoanAudit.inspect(loan, in: context)
            actionError = nil
        } catch { actionError = MacLocalization.error(error) }
    }

    private func createLegacyLoanFixture() {
        guard usesIsolatedTestLedger, let currency else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let due = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))
        else { return }
        do {
            let loan = LoanRule(
                title: "CI-Old-iOS-Loan", principal: 1200,
                annualRate: 12, termMonths: 3, method: .equalPrincipal,
                currency: currency, startDate: due, category: "Loan")
            context.insert(loan)
            let rule = RecurringTransaction(
                title: "Legacy payment", amount: 412,
                currency: currency, type: .expense, category: "Loan",
                projectIdentifier: "loan_generated:\(loan.id.uuidString):1",
                intervalValue: 1, intervalUnit: .month, nextExecutionDate: due)
            context.insert(rule) // intentionally orphaned, as in old damaged links
            try context.save()
            actionMessage = nil
            actionError = nil
        } catch {
            context.rollback()
            actionError = MacLocalization.error(error)
        }
    }

    private func prepareLoanPayment(_ loan: LoanRule) {
        guard let currency else { return }
        do {
            let preview = try MacLoanRepayment.nextPayment(
                loan, now: Date(), bookCurrency: currency, in: context)
            loanPaymentRate = loan.currency == currency ? "1" : ""
            loanConfirmation = LoanConfirmation(loan: loan, preview: preview, bookCurrency: currency, originalCurrency: loan.currency)
            actionError = nil
        } catch {
            actionMessage = nil
            actionError = MacLocalization.error(error)
        }
    }

    private func postLoanPayment(_ loan: LoanRule, preview: MacLoanRepayment.Preview, bookCurrency: String, originalCurrency: String) {
        do {
            let paid = try MacLoanRepayment.recordPaid(
                loan, now: Date(), bookCurrency: bookCurrency,
                expectedIndex: preview.payment.index,
                exchangeRate: loan.currency == bookCurrency ? 1 : try MacCurrency.rate(loanPaymentRate),
                expectedPayment: preview.payment, expectedScheduleCount: preview.totalCount, expectedOriginalCurrency: originalCurrency, in: context)
            actionError = nil
            actionMessage = "Recorded installment \(paid.installment): \(paid.total.formatted(.number.precision(.fractionLength(2)))) \(loan.currency)"
        } catch {
            actionMessage = nil
            actionError = MacLocalization.error(error)
        }
    }

    private func recordActions(_ record: MacFinanceRecord) -> some View {
        HStack {
            Button("Edit") { editingRecord = record }
                .accessibilityIdentifier("editFinance-\(record.id.uuidString)")
            Button("Remove", role: .destructive) { retiringRecord = record }
                .accessibilityIdentifier("removeFinance-\(record.id.uuidString)")
            if record.panel != .goals {
                Button("Review stored schedule") { reviewingRecord = record }
                    .accessibilityIdentifier("reviewFinance-\(record.id.uuidString)")
            }
        }.appFont(.caption, weight: .regular).buttonStyle(.borderless)
    }

    private func createLoanFixture() {
        guard usesIsolatedTestLedger, let currency else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))
        else { return }
        do {
            _ = try MacFinanceRecords.addLoan(
                title: "CI-Loan-Payment", principalText: "1200",
                annualRate: 12, months: 12, method: .equalPrincipal,
                firstPayment: start, currency: currency, in: context)
            actionError = nil
        } catch { actionError = MacLocalization.error(error) }
    }

    /// Explicit test flag plus an isolated SQLite path are required. This
    /// fixture can never be invoked from a normal personal ledger window.
    private func damageLoanReceiptFixture() {
        guard usesIsolatedTestLedger,
              ProcessInfo.processInfo.environment["FINTRACK_V16_RECEIPT_AUDIT_TEST"] == "1"
        else { return }
        do {
            guard let receipt = try context.fetch(FetchDescriptor<Transaction>()).first(where: {
                ($0.note ?? "").contains("[FTLoan:")
            }) else { return }
            receipt.originalAmount = 1
            receipt.baseAmount = 1
            try context.save()
            actionMessage = nil
            actionError = nil
        } catch {
            context.rollback()
            actionError = MacLocalization.error(error)
        }
    }

    private func postDepositInterest(_ deposit: DepositRecord) {
        guard let currency else { return }
        Task { @MainActor in
            do {
                let result = try await MacAutomaticPosting.post(deposit, now: Date(), book: currency, in: context)
                actionError = nil
                actionMessage = "Interest receipts: \(result.receipts) · \(result.totalInterest.formatted(.number.precision(.fractionLength(2)))) \(deposit.originalCurrency)"
            } catch { actionMessage = nil; actionError = MacLocalization.error(error) }
        }
    }

    /// Only runs in the isolated CI test process. Never available in a
    /// personal ledger; never uses real bank records or production data.
    private func createDueFixture() {
        guard usesIsolatedTestLedger, let currency else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = cal.date(from: DateComponents(year: 2025, month: 1, day: 1)),
              let end = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))
        else { return }
        do {
            _ = try MacFinanceRecords.addDeposit(
                bank: "CI-Matured-Interest", principalText: "10000",
                annualRate: 10, start: start, maturity: end,
                mode: .maturity, currency: currency, in: context)
            actionError = nil
        } catch { actionError = MacLocalization.error(error) }
    }

    private func post(_ rule: RecurringTransaction) {
        guard let currency else { return }
        Task { @MainActor in
            do {
                let count = try await MacAutomaticPosting.post(rule, now: Date(), book: currency, in: context)
                actionError = nil; actionMessage = "Posted \(count) unique recurring occurrence(s)"
            } catch { actionError = MacLocalization.error(error) }
        }
    }
}
