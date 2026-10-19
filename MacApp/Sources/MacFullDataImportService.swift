// Platform port of the original FullDataImportService field mapping.
// Changes: caller-owned atomic save and fractional ISO timestamps.
// MacCSV validates every required financial field before this mapping runs.
import Foundation
import SwiftData

struct MacFullDataImportService {
    enum SectionKey {
        static let transactions = "transactions"
        static let recurringTransactions = "recurringtransactions"
        static let deposits = "deposits"
        static let loans = "loans"
        static let goals = "goals"
        static let financialProfile = "financialprofile"
        static let categories = "categories"
        static let accounts = "accounts"
    }

    func buildPreview(
        sourceFileName: String,
        sections: [String: CSVImportSectionTable]
    ) -> FullDataImportPreview? {
        guard isFullBackup(sections) else { return nil }

        return FullDataImportPreview(
            sourceFileName: sourceFileName,
            transactionCount: sections[SectionKey.transactions]?.rows.count ?? 0,
            recurringRuleCount: sections[SectionKey.recurringTransactions]?.rows.count ?? 0,
            depositCount: sections[SectionKey.deposits]?.rows.count ?? 0,
            loanCount: sections[SectionKey.loans]?.rows.count ?? 0,
            goalCount: sections[SectionKey.goals]?.rows.count ?? 0,
            profileCount: sections[SectionKey.financialProfile]?.rows.count ?? 0,
            categoryCount: sections[SectionKey.categories]?.rows.count ?? 0,
            accountCount: sections[SectionKey.accounts]?.rows.count ?? 0
        )
    }

    func importBackup(
        sections: [String: CSVImportSectionTable],
        into modelContext: ModelContext
    ) throws -> FullDataImportCommitResult {
        let existingTransactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        let existingRecurringRules = try modelContext.fetch(FetchDescriptor<RecurringTransaction>())
        let existingDeposits = try modelContext.fetch(FetchDescriptor<DepositRecord>())
        let existingLoans = try modelContext.fetch(FetchDescriptor<LoanRule>())
        let existingGoals = try modelContext.fetch(FetchDescriptor<Goal>())
        let existingProfiles = try modelContext.fetch(FetchDescriptor<FinancialProfile>())
        let existingCategories = try modelContext.fetch(FetchDescriptor<Category>())
        let existingAccounts = try modelContext.fetch(FetchDescriptor<Account>())

        var importedTransactions = 0
        var importedRecurringRules = 0
        var importedDeposits = 0
        var importedLoans = 0
        var importedGoals = 0
        var importedProfiles = 0
        var importedCategories = 0
        var importedAccounts = 0

        if let table = sections[SectionKey.categories] {
            for row in table.rows where shouldImportCategory(row.values, existingCategories: existingCategories) {
                modelContext.insert(
                    Category(
                        id: uuid("ID", from: row.values) ?? UUID(),
                        ownerUID: optionalString("OwnerUID", from: row.values),
                        name: string("Name", from: row.values),
                        type: string("Type", from: row.values),
                        createdAt: date("CreatedAt", from: row.values) ?? Date(),
                        updatedAt: date("UpdatedAt", from: row.values) ?? date("CreatedAt", from: row.values) ?? Date(),
                        deletedAt: date("DeletedAt", from: row.values),
                        lastModifiedDeviceID: optionalString("LastModifiedDeviceID", from: row.values) ?? SyncMetadataDefaults.currentDeviceID,
                        syncVersion: int("SyncVersion", from: row.values) ?? 1
                    )
                )
                importedCategories += 1
            }
        }

        if let table = sections[SectionKey.financialProfile] {
            for row in table.rows where shouldImportProfile(row.values, existingProfiles: existingProfiles) {
                modelContext.insert(
                    FinancialProfile(
                        id: uuid("ID", from: row.values) ?? UUID(),
                        ownerUID: optionalString("OwnerUID", from: row.values),
                        initialAssets: double("InitialAssets", from: row.values) ?? 0,
                        initialDebt: double("InitialDebt", from: row.values) ?? 0,
                        createdAt: date("CreatedAt", from: row.values) ?? Date(),
                        updatedAt: date("UpdatedAt", from: row.values) ?? date("CreatedAt", from: row.values) ?? Date(),
                        deletedAt: date("DeletedAt", from: row.values),
                        lastModifiedDeviceID: optionalString("LastModifiedDeviceID", from: row.values) ?? SyncMetadataDefaults.currentDeviceID,
                        syncVersion: int("SyncVersion", from: row.values) ?? 1
                    )
                )
                importedProfiles += 1
            }
        }

        if let table = sections[SectionKey.accounts] {
            for row in table.rows where shouldImportAccount(row.values, existingAccounts: existingAccounts) {
                modelContext.insert(
                    Account(
                        name: string("Name", from: row.values),
                        type: string("Type", from: row.values),
                        balance: double("Balance", from: row.values) ?? 0,
                        currency: string("Currency", from: row.values),
                        createdAt: date("CreatedAt", from: row.values) ?? Date()
                    )
                )
                importedAccounts += 1
            }
        }

        if let table = sections[SectionKey.goals] {
            for row in table.rows where shouldImportGoal(row.values, existingGoals: existingGoals) {
                modelContext.insert(
                    Goal(
                        id: uuid("ID", from: row.values) ?? UUID(),
                        ownerUID: optionalString("OwnerUID", from: row.values),
                        title: string("Title", from: row.values),
                        targetAmount: double("TargetAmount", from: row.values) ?? 0,
                        startDate: date("StartDate", from: row.values) ?? Date(),
                        targetDate: date("Deadline", from: row.values),
                        includesCurrentAssets: bool("IncludesCurrentAssets", from: row.values) ?? true,
                        creationNetWorth: double("CreationNetWorth", from: row.values) ?? 0,
                        isAccomplished: bool("IsAccomplished", from: row.values) ?? false,
                        isPaused: bool("IsPaused", from: row.values) ?? false,
                        createdAt: date("CreatedAt", from: row.values) ?? Date(),
                        updatedAt: date("UpdatedAt", from: row.values) ?? date("CreatedAt", from: row.values) ?? Date(),
                        deletedAt: date("DeletedAt", from: row.values),
                        lastModifiedDeviceID: optionalString("LastModifiedDeviceID", from: row.values) ?? SyncMetadataDefaults.currentDeviceID,
                        syncVersion: int("SyncVersion", from: row.values) ?? 1
                    )
                )
                importedGoals += 1
            }
        }

        if let table = sections[SectionKey.transactions] {
            for row in table.rows where shouldImportTransaction(row.values, existingTransactions: existingTransactions) {
                modelContext.insert(
                    Transaction(
                        id: uuid("ID", from: row.values) ?? UUID(),
                        ownerUID: optionalString("OwnerUID", from: row.values),
                        amount: double("Amount", from: row.values) ?? 0,
                        currency: string("Currency", from: row.values),
                        type: string("Type", from: row.values),
                        category: string("Category", from: row.values),
                        note: optionalString("Note", from: row.values),
                        date: date("Date", from: row.values) ?? Date(),
                        createdAt: date("CreatedAt", from: row.values) ?? Date(),
                        updatedAt: date("UpdatedAt", from: row.values) ?? date("CreatedAt", from: row.values) ?? Date(),
                        deletedAt: date("DeletedAt", from: row.values),
                        lastModifiedDeviceID: optionalString("LastModifiedDeviceID", from: row.values) ?? SyncMetadataDefaults.currentDeviceID,
                        syncVersion: int("SyncVersion", from: row.values) ?? 1,
                        originalAmount: double("OriginalAmount", from: row.values),
                        originalCurrency: optionalString("OriginalCurrency", from: row.values),
                        exchangeRateToBase: double("ExchangeRateToBase", from: row.values) ?? 1,
                        baseAmount: double("BaseAmount", from: row.values),
                        baseCurrencyCode: optionalString("BaseCurrency", from: row.values)
                    )
                )
                importedTransactions += 1
            }
        }

        if let table = sections[SectionKey.recurringTransactions] {
            for row in table.rows where shouldImportRecurringRule(row.values, existingRules: existingRecurringRules) {
                modelContext.insert(
                    RecurringTransaction(
                        id: uuid("ID", from: row.values) ?? UUID(),
                        ownerUID: optionalString("OwnerUID", from: row.values),
                        title: string("Title", from: row.values),
                        amount: double("Amount", from: row.values) ?? 0,
                        currency: string("Currency", from: row.values),
                        type: string("Type", from: row.values),
                        category: string("Category", from: row.values),
                        note: optionalString("Note", from: row.values),
                        projectIdentifier: optionalString("ProjectIdentifier", from: row.values),
                        intervalValue: int("IntervalValue", from: row.values) ?? 1,
                        intervalUnit: string("IntervalUnit", from: row.values),
                        nextExecutionDate: date("NextExecutionDate", from: row.values) ?? Date(),
                        lastExecutionDate: date("LastExecutionDate", from: row.values),
                        endDate: date("EndDate", from: row.values),
                        isActive: bool("IsActive", from: row.values) ?? true,
                        notificationsEnabled: bool("NotificationsEnabled", from: row.values) ?? false,
                        reminderDaysBefore: int("ReminderDaysBefore", from: row.values) ?? 0,
                        reminderHour: int("ReminderHour", from: row.values) ?? 9,
                        reminderMinute: int("ReminderMinute", from: row.values) ?? 0,
                        originalAmount: double("OriginalAmount", from: row.values),
                        originalCurrency: optionalString("OriginalCurrency", from: row.values),
                        exchangeRateToBase: double("ExchangeRateToBase", from: row.values) ?? 1,
                        baseAmount: double("BaseAmount", from: row.values),
                        baseCurrencyCode: optionalString("BaseCurrency", from: row.values),
                        createdAt: date("CreatedAt", from: row.values) ?? Date(),
                        updatedAt: date("UpdatedAt", from: row.values) ?? date("CreatedAt", from: row.values) ?? Date(),
                        deletedAt: date("DeletedAt", from: row.values),
                        lastModifiedDeviceID: optionalString("LastModifiedDeviceID", from: row.values) ?? SyncMetadataDefaults.currentDeviceID,
                        syncVersion: int("SyncVersion", from: row.values) ?? 1
                    )
                )
                importedRecurringRules += 1
            }
        }

        if let table = sections[SectionKey.deposits] {
            for row in table.rows where shouldImportDeposit(row.values, existingDeposits: existingDeposits) {
                modelContext.insert(
                    DepositRecord(
                        id: uuid("ID", from: row.values) ?? UUID(),
                        ownerUID: optionalString("OwnerUID", from: row.values),
                        bankName: string("BankName", from: row.values),
                        principal: double("Principal", from: row.values) ?? 0,
                        originalPrincipal: double("OriginalPrincipal", from: row.values),
                        originalCurrency: optionalString("OriginalCurrency", from: row.values),
                        basePrincipal: double("BasePrincipal", from: row.values),
                        baseCurrencyCode: optionalString("BaseCurrency", from: row.values),
                        principalExchangeRateToBase: double("PrincipalExchangeRateToBase", from: row.values) ?? 1,
                        annualInterestRate: double("AnnualInterestRate", from: row.values) ?? 0,
                        interestSettlementMode: string("InterestSettlementMode", from: row.values),
                        expectedInterest: double("ExpectedInterest", from: row.values) ?? 0,
                        baseExpectedInterest: double("BaseExpectedInterest", from: row.values),
                        interestExchangeRateToBase: double("InterestExchangeRateToBase", from: row.values) ?? 1,
                        isInterestManuallyEdited: bool("IsInterestManuallyEdited", from: row.values) ?? false,
                        currency: string("Currency", from: row.values),
                        startDate: date("StartDate", from: row.values) ?? Date(),
                        maturityDate: date("MaturityDate", from: row.values) ?? Date(),
                        isActive: bool("IsActive", from: row.values) ?? true,
                        hasCreditedInterest: bool("HasCreditedInterest", from: row.values) ?? false,
                        lastInterestPayoutDate: date("LastInterestPayoutDate", from: row.values),
                        nextInterestPayoutDate: date("NextInterestPayoutDate", from: row.values),
                        notificationsEnabled: bool("NotificationsEnabled", from: row.values) ?? false,
                        reminderDaysBefore: int("ReminderDaysBefore", from: row.values) ?? 0,
                        reminderHour: int("ReminderHour", from: row.values) ?? 9,
                        reminderMinute: int("ReminderMinute", from: row.values) ?? 0,
                        note: optionalString("Note", from: row.values),
                        maturityInterestHandling: optionalString("MaturityInterestHandling", from: row.values),
                        sourceDepositID: uuid("SourceDepositID", from: row.values),
                        rolloverBasePrincipalAmount: double("RolloverBasePrincipalAmount", from: row.values),
                        rolloverBaseInterestAmount: double("RolloverBaseInterestAmount", from: row.values),
                        createdAt: date("CreatedAt", from: row.values) ?? Date(),
                        updatedAt: date("UpdatedAt", from: row.values) ?? date("CreatedAt", from: row.values) ?? Date(),
                        deletedAt: date("DeletedAt", from: row.values),
                        lastModifiedDeviceID: optionalString("LastModifiedDeviceID", from: row.values) ?? SyncMetadataDefaults.currentDeviceID,
                        syncVersion: int("SyncVersion", from: row.values) ?? 1
                    )
                )
                importedDeposits += 1
            }
        }

        if let table = sections[SectionKey.loans] {
            for row in table.rows where shouldImportLoan(row.values, existingLoans: existingLoans) {
                modelContext.insert(
                    LoanRule(
                        id: uuid("ID", from: row.values) ?? UUID(),
                        ownerUID: optionalString("OwnerUID", from: row.values),
                        title: string("Title", from: row.values),
                        totalAmount: double("TotalAmount", from: row.values),
                        downPaymentAmount: double("DownPaymentAmount", from: row.values) ?? 0,
                        downPaymentPercent: double("DownPaymentPercent", from: row.values) ?? 0,
                        principal: double("Principal", from: row.values) ?? 0,
                        basePrincipal: double("BasePrincipal", from: row.values),
                        baseCurrencyCode: optionalString("BaseCurrency", from: row.values),
                        exchangeRateToBase: double("ExchangeRateToBase", from: row.values) ?? 1,
                        annualRate: double("AnnualRate", from: row.values) ?? 0,
                        termMonths: int("TermMonths", from: row.values) ?? 0,
                        methodRawValue: string("Method", from: row.values),
                        currency: string("Currency", from: row.values),
                        startDate: date("StartDate", from: row.values) ?? Date(),
                        category: string("Category", from: row.values),
                        note: string("Note", from: row.values),
                        createdAt: date("CreatedAt", from: row.values) ?? Date(),
                        updatedAt: date("UpdatedAt", from: row.values) ?? date("CreatedAt", from: row.values) ?? Date(),
                        deletedAt: date("DeletedAt", from: row.values),
                        lastModifiedDeviceID: optionalString("LastModifiedDeviceID", from: row.values) ?? SyncMetadataDefaults.currentDeviceID,
                        syncVersion: int("SyncVersion", from: row.values) ?? 1
                    )
                )
                importedLoans += 1
            }
        }

        // MacCSV commits records and rebuilt relationships together.

        return FullDataImportCommitResult(
            transactionCount: importedTransactions,
            recurringRuleCount: importedRecurringRules,
            depositCount: importedDeposits,
            loanCount: importedLoans,
            goalCount: importedGoals,
            profileCount: importedProfiles,
            categoryCount: importedCategories,
            accountCount: importedAccounts
        )
    }

    func isFullBackup(_ sections: [String: CSVImportSectionTable]) -> Bool {
        guard sections[SectionKey.transactions] != nil else { return false }
        return sections.keys.contains(where: { $0 != SectionKey.transactions })
    }

    private func shouldImportCategory(_ values: [String: String], existingCategories: [Category]) -> Bool {
        if let importedID = uuid("ID", from: values) {
            return existingCategories.contains(where: { $0.id == importedID }) == false
        }
        let name = string("Name", from: values)
        let type = string("Type", from: values)
        return existingCategories.contains {
            $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.type.caseInsensitiveCompare(type) == .orderedSame
        } == false
    }

    private func shouldImportProfile(_ values: [String: String], existingProfiles: [FinancialProfile]) -> Bool {
        if let importedID = uuid("ID", from: values) {
            return existingProfiles.contains(where: { $0.id == importedID }) == false
        }
        let initialAssets = double("InitialAssets", from: values) ?? 0
        let initialDebt = double("InitialDebt", from: values) ?? 0
        let createdAt = date("CreatedAt", from: values)
        return existingProfiles.contains {
            $0.initialAssets == initialAssets
                && $0.initialDebt == initialDebt
                && sameDate($0.createdAt, createdAt)
        } == false
    }

    private func shouldImportAccount(_ values: [String: String], existingAccounts: [Account]) -> Bool {
        let name = string("Name", from: values)
        let type = string("Type", from: values)
        let currency = string("Currency", from: values)
        let balance = double("Balance", from: values) ?? 0
        let createdAt = date("CreatedAt", from: values)
        return existingAccounts.contains {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
                && $0.type.caseInsensitiveCompare(type) == .orderedSame
                && $0.currency.caseInsensitiveCompare(currency) == .orderedSame
                && $0.balance == balance
                && sameDate($0.createdAt, createdAt)
        } == false
    }

    private func shouldImportGoal(_ values: [String: String], existingGoals: [Goal]) -> Bool {
        if let importedID = uuid("ID", from: values) {
            return existingGoals.contains(where: { $0.id == importedID }) == false
        }
        let title = string("Title", from: values)
        let targetAmount = double("TargetAmount", from: values) ?? 0
        let startDate = date("StartDate", from: values)
        let deadline = date("Deadline", from: values)
        return existingGoals.contains {
            $0.title.caseInsensitiveCompare(title) == .orderedSame
                && $0.targetAmount == targetAmount
                && sameDate($0.startDate, startDate)
                && sameDate($0.deadline, deadline)
        } == false
    }

    private func shouldImportTransaction(_ values: [String: String], existingTransactions: [Transaction]) -> Bool {
        if let importedID = uuid("ID", from: values) {
            return existingTransactions.contains(where: { $0.id == importedID }) == false
        }
        let type = string("Type", from: values)
        let category = string("Category", from: values)
        let date = date("Date", from: values)
        let baseAmount = double("BaseAmount", from: values) ?? double("Amount", from: values) ?? 0
        let note = optionalString("Note", from: values) ?? ""
        return existingTransactions.contains {
            $0.type.caseInsensitiveCompare(type) == .orderedSame
                && $0.category.caseInsensitiveCompare(category) == .orderedSame
                && $0.baseAmount == baseAmount
                && sameDate($0.date, date)
                && ($0.note ?? "") == note
        } == false
    }

    private func shouldImportRecurringRule(_ values: [String: String], existingRules: [RecurringTransaction]) -> Bool {
        if let importedID = uuid("ID", from: values) {
            return existingRules.contains(where: { $0.id == importedID }) == false
        }
        let title = string("Title", from: values)
        let type = string("Type", from: values)
        let category = string("Category", from: values)
        let amount = double("Amount", from: values) ?? 0
        let nextExecutionDate = date("NextExecutionDate", from: values)
        return existingRules.contains {
            $0.title.caseInsensitiveCompare(title) == .orderedSame
                && $0.type.caseInsensitiveCompare(type) == .orderedSame
                && $0.category.caseInsensitiveCompare(category) == .orderedSame
                && $0.amount == amount
                && sameDate($0.nextExecutionDate, nextExecutionDate)
        } == false
    }

    private func shouldImportDeposit(_ values: [String: String], existingDeposits: [DepositRecord]) -> Bool {
        if let importedID = uuid("ID", from: values) {
            return existingDeposits.contains(where: { $0.id == importedID }) == false
        }
        let bankName = string("BankName", from: values)
        let principal = double("Principal", from: values) ?? 0
        let startDate = date("StartDate", from: values)
        let maturityDate = date("MaturityDate", from: values)
        return existingDeposits.contains {
            $0.bankName.caseInsensitiveCompare(bankName) == .orderedSame
                && $0.principal == principal
                && sameDate($0.startDate, startDate)
                && sameDate($0.maturityDate, maturityDate)
        } == false
    }

    private func shouldImportLoan(_ values: [String: String], existingLoans: [LoanRule]) -> Bool {
        if let importedID = uuid("ID", from: values) {
            return existingLoans.contains(where: { $0.id == importedID }) == false
        }
        let title = string("Title", from: values)
        let principal = double("Principal", from: values) ?? 0
        let startDate = date("StartDate", from: values)
        return existingLoans.contains {
            $0.title.caseInsensitiveCompare(title) == .orderedSame
                && $0.principal == principal
                && sameDate($0.startDate, startDate)
        } == false
    }

    private func string(_ key: String, from values: [String: String]) -> String {
        values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func optionalString(_ key: String, from values: [String: String]) -> String? {
        let trimmed = string(key, from: values)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func double(_ key: String, from values: [String: String]) -> Double? {
        guard let raw = optionalString(key, from: values) else { return nil }
        return Double(raw)
    }

    private func int(_ key: String, from values: [String: String]) -> Int? {
        guard let raw = optionalString(key, from: values) else { return nil }
        return Int(raw)
    }

    private func bool(_ key: String, from values: [String: String]) -> Bool? {
        guard let raw = optionalString(key, from: values)?.lowercased() else { return nil }
        switch raw {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }

    private func date(_ key: String, from values: [String: String]) -> Date? {
        guard let raw = optionalString(key, from: values) else { return nil }
        return try? MacCSV.parsedDate(raw, field: key)
    }

    private func uuid(_ key: String, from values: [String: String]) -> UUID? {
        guard let raw = optionalString(key, from: values) else { return nil }
        return UUID(uuidString: raw)
    }

    private func sameDate(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhsValue), .some(rhsValue)):
            return abs(lhsValue.timeIntervalSince(rhsValue)) < 0.5
        default:
            return false
        }
    }
}
