import Foundation
import SwiftData
import CryptoKit
import AppKit

// Explicit value snapshots preserve every stored field, including tombstones and exact loan relationships.

struct MacBackupAccount: Codable {
    var name: String
    var type: String
    var balance: Double
    var currency: String
    var createdAt: Date
    init(_ row: Account) {
        name = row.name
        type = row.type
        balance = row.balance
        currency = row.currency
        createdAt = row.createdAt
    }
    func make() -> Account {
        let row = Account(name: name, type: type, balance: balance, currency: currency, createdAt: createdAt)
        row.name = name
        row.type = type
        row.balance = balance
        row.currency = currency
        row.createdAt = createdAt
        return row
    }
}

struct MacBackupTransaction: Codable {
    var id: UUID
    var ownerUID: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int
    var originalAmount: Double
    var originalCurrency: String
    var baseAmount: Double
    var baseCurrencyCode: String
    var exchangeRateToBase: Double
    var type: String
    var category: String
    var note: String?
    var date: Date
    init(_ row: Transaction) {
        id = row.id
        ownerUID = row.ownerUID
        createdAt = row.createdAt
        updatedAt = row.updatedAt
        deletedAt = row.deletedAt
        lastModifiedDeviceID = row.lastModifiedDeviceID
        syncVersion = row.syncVersion
        originalAmount = row.originalAmount
        originalCurrency = row.originalCurrency
        baseAmount = row.baseAmount
        baseCurrencyCode = row.baseCurrencyCode
        exchangeRateToBase = row.exchangeRateToBase
        type = row.type
        category = row.category
        note = row.note
        date = row.date
    }
    func make() -> Transaction {
        let row = Transaction(amount: baseAmount, currency: baseCurrencyCode, type: type, category: category)
        row.id = id
        row.ownerUID = ownerUID
        row.createdAt = createdAt
        row.updatedAt = updatedAt
        row.deletedAt = deletedAt
        row.lastModifiedDeviceID = lastModifiedDeviceID
        row.syncVersion = syncVersion
        row.originalAmount = originalAmount
        row.originalCurrency = originalCurrency
        row.baseAmount = baseAmount
        row.baseCurrencyCode = baseCurrencyCode
        row.exchangeRateToBase = exchangeRateToBase
        row.type = type
        row.category = category
        row.note = note
        row.date = date
        return row
    }
}

struct MacBackupCategory: Codable {
    var id: UUID
    var ownerUID: String?
    var name: String
    var type: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int
    init(_ row: Category) {
        id = row.id
        ownerUID = row.ownerUID
        name = row.name
        type = row.type
        createdAt = row.createdAt
        updatedAt = row.updatedAt
        deletedAt = row.deletedAt
        lastModifiedDeviceID = row.lastModifiedDeviceID
        syncVersion = row.syncVersion
    }
    func make() -> Category {
        let row = Category(name: name, type: type)
        row.id = id
        row.ownerUID = ownerUID
        row.name = name
        row.type = type
        row.createdAt = createdAt
        row.updatedAt = updatedAt
        row.deletedAt = deletedAt
        row.lastModifiedDeviceID = lastModifiedDeviceID
        row.syncVersion = syncVersion
        return row
    }
}

struct MacBackupGoal: Codable {
    var id: UUID
    var ownerUID: String?
    var title: String
    var targetAmount: Double
    var startDate: Date
    var deadline: Date?
    var includesCurrentAssets: Bool
    var creationNetWorth: Double
    var isAccomplished: Bool
    var isPaused: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int
    init(_ row: Goal) {
        id = row.id
        ownerUID = row.ownerUID
        title = row.title
        targetAmount = row.targetAmount
        startDate = row.startDate
        deadline = row.deadline
        includesCurrentAssets = row.includesCurrentAssets
        creationNetWorth = row.creationNetWorth
        isAccomplished = row.isAccomplished
        isPaused = row.isPaused
        createdAt = row.createdAt
        updatedAt = row.updatedAt
        deletedAt = row.deletedAt
        lastModifiedDeviceID = row.lastModifiedDeviceID
        syncVersion = row.syncVersion
    }
    func make() -> Goal {
        let row = Goal(title: title, targetAmount: targetAmount)
        row.id = id
        row.ownerUID = ownerUID
        row.title = title
        row.targetAmount = targetAmount
        row.startDate = startDate
        row.deadline = deadline
        row.includesCurrentAssets = includesCurrentAssets
        row.creationNetWorth = creationNetWorth
        row.isAccomplished = isAccomplished
        row.isPaused = isPaused
        row.createdAt = createdAt
        row.updatedAt = updatedAt
        row.deletedAt = deletedAt
        row.lastModifiedDeviceID = lastModifiedDeviceID
        row.syncVersion = syncVersion
        return row
    }
}

struct MacBackupFinancialProfile: Codable {
    var id: UUID
    var ownerUID: String?
    var initialAssets: Double
    var initialDebt: Double
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int
    init(_ row: FinancialProfile) {
        id = row.id
        ownerUID = row.ownerUID
        initialAssets = row.initialAssets
        initialDebt = row.initialDebt
        createdAt = row.createdAt
        updatedAt = row.updatedAt
        deletedAt = row.deletedAt
        lastModifiedDeviceID = row.lastModifiedDeviceID
        syncVersion = row.syncVersion
    }
    func make() -> FinancialProfile {
        let row = FinancialProfile()
        row.id = id
        row.ownerUID = ownerUID
        row.initialAssets = initialAssets
        row.initialDebt = initialDebt
        row.createdAt = createdAt
        row.updatedAt = updatedAt
        row.deletedAt = deletedAt
        row.lastModifiedDeviceID = lastModifiedDeviceID
        row.syncVersion = syncVersion
        return row
    }
}

struct MacBackupRecurringTransaction: Codable {
    var id: UUID
    var ownerUID: String?
    var originalAmount: Double
    var originalCurrency: String
    var baseAmount: Double
    var baseCurrencyCode: String
    var exchangeRateToBase: Double
    var title: String
    var amount: Double
    var currency: String
    var type: String
    var category: String
    var note: String?
    var projectIdentifier: String?
    var intervalValue: Int
    var intervalUnit: String
    var nextExecutionDate: Date
    var lastExecutionDate: Date?
    var endDate: Date?
    var isActive: Bool
    var notificationsEnabled: Bool
    var reminderDaysBefore: Int
    var reminderHour: Int
    var reminderMinute: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int
    init(_ row: RecurringTransaction) {
        id = row.id
        ownerUID = row.ownerUID
        originalAmount = row.originalAmount
        originalCurrency = row.originalCurrency
        baseAmount = row.baseAmount
        baseCurrencyCode = row.baseCurrencyCode
        exchangeRateToBase = row.exchangeRateToBase
        title = row.title
        amount = row.amount
        currency = row.currency
        type = row.type
        category = row.category
        note = row.note
        projectIdentifier = row.projectIdentifier
        intervalValue = row.intervalValue
        intervalUnit = row.intervalUnit
        nextExecutionDate = row.nextExecutionDate
        lastExecutionDate = row.lastExecutionDate
        endDate = row.endDate
        isActive = row.isActive
        notificationsEnabled = row.notificationsEnabled
        reminderDaysBefore = row.reminderDaysBefore
        reminderHour = row.reminderHour
        reminderMinute = row.reminderMinute
        createdAt = row.createdAt
        updatedAt = row.updatedAt
        deletedAt = row.deletedAt
        lastModifiedDeviceID = row.lastModifiedDeviceID
        syncVersion = row.syncVersion
    }
    func make() -> RecurringTransaction {
        let row = RecurringTransaction(title: title, amount: amount, currency: currency, type: type, category: category, intervalValue: intervalValue, intervalUnit: intervalUnit, nextExecutionDate: nextExecutionDate)
        row.id = id
        row.ownerUID = ownerUID
        row.originalAmount = originalAmount
        row.originalCurrency = originalCurrency
        row.baseAmount = baseAmount
        row.baseCurrencyCode = baseCurrencyCode
        row.exchangeRateToBase = exchangeRateToBase
        row.title = title
        row.amount = amount
        row.currency = currency
        row.type = type
        row.category = category
        row.note = note
        row.projectIdentifier = projectIdentifier
        row.intervalValue = intervalValue
        row.intervalUnit = intervalUnit
        row.nextExecutionDate = nextExecutionDate
        row.lastExecutionDate = lastExecutionDate
        row.endDate = endDate
        row.isActive = isActive
        row.notificationsEnabled = notificationsEnabled
        row.reminderDaysBefore = reminderDaysBefore
        row.reminderHour = reminderHour
        row.reminderMinute = reminderMinute
        row.createdAt = createdAt
        row.updatedAt = updatedAt
        row.deletedAt = deletedAt
        row.lastModifiedDeviceID = lastModifiedDeviceID
        row.syncVersion = syncVersion
        return row
    }
}

struct MacBackupDepositRecord: Codable {
    var id: UUID
    var ownerUID: String?
    var bankName: String
    var principal: Double
    var originalPrincipal: Double
    var originalCurrency: String
    var basePrincipal: Double
    var baseCurrencyCode: String
    var principalExchangeRateToBase: Double
    var annualInterestRate: Double
    var interestSettlementMode: String
    var expectedInterest: Double
    var baseExpectedInterest: Double
    var interestExchangeRateToBase: Double
    var isInterestManuallyEdited: Bool
    var currency: String
    var startDate: Date
    var maturityDate: Date
    var isActive: Bool
    var hasCreditedInterest: Bool
    var lastInterestPayoutDate: Date?
    var nextInterestPayoutDate: Date?
    var notificationsEnabled: Bool
    var reminderDaysBefore: Int
    var reminderHour: Int
    var reminderMinute: Int
    var note: String?
    var maturityInterestHandling: String?
    var sourceDepositID: UUID?
    var rolloverBasePrincipalAmount: Double?
    var rolloverBaseInterestAmount: Double?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int
    init(_ row: DepositRecord) {
        id = row.id
        ownerUID = row.ownerUID
        bankName = row.bankName
        principal = row.principal
        originalPrincipal = row.originalPrincipal
        originalCurrency = row.originalCurrency
        basePrincipal = row.basePrincipal
        baseCurrencyCode = row.baseCurrencyCode
        principalExchangeRateToBase = row.principalExchangeRateToBase
        annualInterestRate = row.annualInterestRate
        interestSettlementMode = row.interestSettlementMode
        expectedInterest = row.expectedInterest
        baseExpectedInterest = row.baseExpectedInterest
        interestExchangeRateToBase = row.interestExchangeRateToBase
        isInterestManuallyEdited = row.isInterestManuallyEdited
        currency = row.currency
        startDate = row.startDate
        maturityDate = row.maturityDate
        isActive = row.isActive
        hasCreditedInterest = row.hasCreditedInterest
        lastInterestPayoutDate = row.lastInterestPayoutDate
        nextInterestPayoutDate = row.nextInterestPayoutDate
        notificationsEnabled = row.notificationsEnabled
        reminderDaysBefore = row.reminderDaysBefore
        reminderHour = row.reminderHour
        reminderMinute = row.reminderMinute
        note = row.note
        maturityInterestHandling = row.maturityInterestHandling
        sourceDepositID = row.sourceDepositID
        rolloverBasePrincipalAmount = row.rolloverBasePrincipalAmount
        rolloverBaseInterestAmount = row.rolloverBaseInterestAmount
        createdAt = row.createdAt
        updatedAt = row.updatedAt
        deletedAt = row.deletedAt
        lastModifiedDeviceID = row.lastModifiedDeviceID
        syncVersion = row.syncVersion
    }
    func make() -> DepositRecord {
        let row = DepositRecord(bankName: bankName, principal: principal, annualInterestRate: annualInterestRate, expectedInterest: expectedInterest, currency: currency, startDate: startDate, maturityDate: maturityDate)
        row.id = id
        row.ownerUID = ownerUID
        row.bankName = bankName
        row.principal = principal
        row.originalPrincipal = originalPrincipal
        row.originalCurrency = originalCurrency
        row.basePrincipal = basePrincipal
        row.baseCurrencyCode = baseCurrencyCode
        row.principalExchangeRateToBase = principalExchangeRateToBase
        row.annualInterestRate = annualInterestRate
        row.interestSettlementMode = interestSettlementMode
        row.expectedInterest = expectedInterest
        row.baseExpectedInterest = baseExpectedInterest
        row.interestExchangeRateToBase = interestExchangeRateToBase
        row.isInterestManuallyEdited = isInterestManuallyEdited
        row.currency = currency
        row.startDate = startDate
        row.maturityDate = maturityDate
        row.isActive = isActive
        row.hasCreditedInterest = hasCreditedInterest
        row.lastInterestPayoutDate = lastInterestPayoutDate
        row.nextInterestPayoutDate = nextInterestPayoutDate
        row.notificationsEnabled = notificationsEnabled
        row.reminderDaysBefore = reminderDaysBefore
        row.reminderHour = reminderHour
        row.reminderMinute = reminderMinute
        row.note = note
        row.maturityInterestHandling = maturityInterestHandling
        row.sourceDepositID = sourceDepositID
        row.rolloverBasePrincipalAmount = rolloverBasePrincipalAmount
        row.rolloverBaseInterestAmount = rolloverBaseInterestAmount
        row.createdAt = createdAt
        row.updatedAt = updatedAt
        row.deletedAt = deletedAt
        row.lastModifiedDeviceID = lastModifiedDeviceID
        row.syncVersion = syncVersion
        return row
    }
}

struct MacBackupLoanRule: Codable {
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
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int
    var generatedRuleIDs: [UUID]
    init(_ row: LoanRule) {
        id = row.id
        ownerUID = row.ownerUID
        title = row.title
        totalAmount = row.totalAmount
        downPaymentAmount = row.downPaymentAmount
        downPaymentPercent = row.downPaymentPercent
        principal = row.principal
        basePrincipal = row.basePrincipal
        baseCurrencyCode = row.baseCurrencyCode
        exchangeRateToBase = row.exchangeRateToBase
        annualRate = row.annualRate
        termMonths = row.termMonths
        methodRawValue = row.methodRawValue
        currency = row.currency
        startDate = row.startDate
        category = row.category
        note = row.note
        createdAt = row.createdAt
        updatedAt = row.updatedAt
        deletedAt = row.deletedAt
        lastModifiedDeviceID = row.lastModifiedDeviceID
        syncVersion = row.syncVersion
        generatedRuleIDs = row.generatedRules.map(\.id)
    }
    func make() -> LoanRule {
        let row = LoanRule(title: title, principal: principal, annualRate: annualRate, termMonths: termMonths, methodRawValue: methodRawValue, currency: currency, startDate: startDate, category: category)
        row.id = id
        row.ownerUID = ownerUID
        row.title = title
        row.totalAmount = totalAmount
        row.downPaymentAmount = downPaymentAmount
        row.downPaymentPercent = downPaymentPercent
        row.principal = principal
        row.basePrincipal = basePrincipal
        row.baseCurrencyCode = baseCurrencyCode
        row.exchangeRateToBase = exchangeRateToBase
        row.annualRate = annualRate
        row.termMonths = termMonths
        row.methodRawValue = methodRawValue
        row.currency = currency
        row.startDate = startDate
        row.category = category
        row.note = note
        row.createdAt = createdAt
        row.updatedAt = updatedAt
        row.deletedAt = deletedAt
        row.lastModifiedDeviceID = lastModifiedDeviceID
        row.syncVersion = syncVersion
        return row
    }
}


@MainActor
enum MacNativeBackup {
    struct UpdateTrustConfiguration: Codable, Equatable {
        var url: String
        var publicKey: String

        func validate() throws {
            guard MacUpdateService.validatedURL(url) != nil,
                  Data(base64Encoded: publicKey)?.count == 32 else {
                throw MacSettingsFailure.invalid("备份中的更新源地址或 Ed25519 公钥无效，未应用更新源配置")
            }
        }

        var isValid: Bool { (try? validate()) != nil }
        var keyFingerprint: String? {
            guard let key = Data(base64Encoded: publicKey) else { return nil }
            return MacNativeBackup.digest(key)
        }
    }

    struct BackupHistoryMetadata: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var date: Date
        var size: Int
        var sha256: String

        init(record: MacBackupRecord) {
            id = record.id; name = record.name; date = record.date; size = record.size; sha256 = record.sha256
        }

        var localRecord: MacBackupRecord {
            MacBackupRecord(id: id, name: name, path: "", date: date, size: size, sha256: sha256)
        }

        var isValid: Bool {
            !name.isEmpty && name.count <= 255 && name == URL(fileURLWithPath: name).lastPathComponent &&
            !name.contains("\\") && size >= 0 && size <= 100 * 1024 * 1024 &&
            sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
        }
    }

    struct Payload: Codable {
        var createdAt: Date
        var applicationVersion: String
        var settings: Data
        var bankLogos: [String: Data]

        var account: [MacBackupAccount]
        var transaction: [MacBackupTransaction]
        var category: [MacBackupCategory]
        var goal: [MacBackupGoal]
        var financialProfile: [MacBackupFinancialProfile]
        var recurringTransaction: [MacBackupRecurringTransaction]
        var depositRecord: [MacBackupDepositRecord]
        var loanRule: [MacBackupLoanRule]
        var updateTrust: UpdateTrustConfiguration? = nil
        var backupHistory: [BackupHistoryMetadata]? = nil

        var recordCount: Int { account.count + transaction.count + category.count + goal.count + financialProfile.count + recurringTransaction.count + depositRecord.count + loanRule.count }
    }
    private struct Envelope: Codable {
        var format = "FinTrack.NativeBackup"
        var version = 1
        var sha256: String
        var payload: Data
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func create(in context: ModelContext) throws -> Data {
        guard !context.hasChanges else { throw MacSettingsFailure.invalid("请先保存或取消正在编辑的内容") }
        var logos: [String: Data] = [:]
        for url in (try? FileManager.default.contentsOfDirectory(at: MacBankLogos.directory(), includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "png" {
            let data = try Data(contentsOf: url)
            if data.count <= 512 * 1024 { logos[url.lastPathComponent] = data }
        }
        let updateURL = MacPreferences.defaults.string(forKey: "v2_update_url") ?? ""
        let updateKey = MacPreferences.defaults.string(forKey: "v2_update_public_key") ?? ""
        let updateTrust = updateURL.isEmpty && updateKey.isEmpty ? nil : UpdateTrustConfiguration(url: updateURL, publicKey: updateKey)
        let backupHistory = MacSettingsStore.load("v2_backup_history", fallback: [MacBackupRecord]())
            .prefix(100).map(BackupHistoryMetadata.init(record:))
        let payload = Payload(createdAt: Date(), applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            settings: try MacSettingsStore.snapshot(), bankLogos: logos,

            account: try context.fetch(FetchDescriptor<Account>()).map(MacBackupAccount.init),
            transaction: try context.fetch(FetchDescriptor<Transaction>()).map(MacBackupTransaction.init),
            category: try context.fetch(FetchDescriptor<Category>()).map(MacBackupCategory.init),
            goal: try context.fetch(FetchDescriptor<Goal>()).map(MacBackupGoal.init),
            financialProfile: try context.fetch(FetchDescriptor<FinancialProfile>()).map(MacBackupFinancialProfile.init),
            recurringTransaction: try context.fetch(FetchDescriptor<RecurringTransaction>()).map(MacBackupRecurringTransaction.init),
            depositRecord: try context.fetch(FetchDescriptor<DepositRecord>()).map(MacBackupDepositRecord.init),
            loanRule: try context.fetch(FetchDescriptor<LoanRule>()).map(MacBackupLoanRule.init),
            updateTrust: updateTrust, backupHistory: backupHistory)

        let bytes = try JSONEncoder().encode(payload)
        return try JSONEncoder().encode(Envelope(sha256: digest(bytes), payload: bytes))
    }
    static func preview(_ data: Data) throws -> Payload {
        guard data.count <= 100 * 1024 * 1024 else { throw MacSettingsFailure.invalid("备份文件超过 100 MB") }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.format == "FinTrack.NativeBackup", envelope.version == 1, digest(envelope.payload) == envelope.sha256
        else { throw MacSettingsFailure.invalid("备份格式、版本或完整性检查未通过") }
        let p = try JSONDecoder().decode(Payload.self, from: envelope.payload)
        _ = try MacSettingsStore.validateSettings(p.settings)
        guard p.recordCount <= 1_000_000 else { throw MacSettingsFailure.invalid("备份记录数量超出限制") }
        if let updateTrust = p.updateTrust {
            guard updateTrust.url.utf8.count <= 2048, updateTrust.publicKey.utf8.count <= 512 else {
                throw MacSettingsFailure.invalid("备份中的更新源配置过长")
            }
        }
        if let backupHistory = p.backupHistory {
            guard backupHistory.count <= 100, Set(backupHistory.map(\.id)).count == backupHistory.count,
                  backupHistory.allSatisfy(\.isValid) else { throw MacSettingsFailure.invalid("备份历史元数据无效") }
        }

        guard Set(p.transaction.map(\.id)).count == p.transaction.count else { throw MacSettingsFailure.invalid("Transaction 编号重复") }
        guard Set(p.category.map(\.id)).count == p.category.count else { throw MacSettingsFailure.invalid("Category 编号重复") }
        guard Set(p.goal.map(\.id)).count == p.goal.count else { throw MacSettingsFailure.invalid("Goal 编号重复") }
        guard Set(p.financialProfile.map(\.id)).count == p.financialProfile.count else { throw MacSettingsFailure.invalid("FinancialProfile 编号重复") }
        guard Set(p.recurringTransaction.map(\.id)).count == p.recurringTransaction.count else { throw MacSettingsFailure.invalid("RecurringTransaction 编号重复") }
        guard Set(p.depositRecord.map(\.id)).count == p.depositRecord.count else { throw MacSettingsFailure.invalid("DepositRecord 编号重复") }
        guard Set(p.loanRule.map(\.id)).count == p.loanRule.count else { throw MacSettingsFailure.invalid("LoanRule 编号重复") }

        let rules = Set(p.recurringTransaction.map(\.id))
        for loan in p.loanRule {
            guard Set(loan.generatedRuleIDs).count == loan.generatedRuleIDs.count, Set(loan.generatedRuleIDs).isSubset(of: rules)
            else { throw MacSettingsFailure.invalid("贷款与周期规则关联不完整") }
        }
        for (name, bytes) in p.bankLogos {
            guard name.range(of: #"^[a-f0-9]{64}\.png$"#, options: .regularExpression) != nil, bytes.count <= 512 * 1024,
                  NSImage(data: bytes) != nil else { throw MacSettingsFailure.invalid("银行图标无效") }
        }
        return p
    }
    /// One database save replaces all entities. A failing save rolls the entire replacement back.
    /// Assets are staged and reversible; settings are applied only after the database commit.
    static func restore(_ data: Data, in context: ModelContext, restoreUpdateTrust: Bool = false,
                        save: ((ModelContext) throws -> Void)? = nil) throws {
        guard !MacAutomaticPosting.isRunning else { throw MacSettingsFailure.invalid("自动入账正在处理中，请完成后再恢复账本") }
        let p = try preview(data), settings = try MacSettingsStore.validateSettings(p.settings)
        let updateTrustToRestore: UpdateTrustConfiguration?
        if restoreUpdateTrust {
            guard let updateTrust = p.updateTrust else { throw MacSettingsFailure.invalid("此备份不包含更新源信任配置") }
            try updateTrust.validate()
            updateTrustToRestore = updateTrust
        } else { updateTrustToRestore = nil }
        let localHistory = MacSettingsStore.load("v2_backup_history", fallback: [MacBackupRecord]())
        let restoredHistoryData: Data?
        if let backupHistory = p.backupHistory {
            var merged = localHistory.prefix(100).map { record -> MacBackupRecord in
                guard !record.path.isEmpty, FileManager.default.fileExists(atPath: record.path) else {
                    return MacBackupRecord(id: record.id, name: record.name, path: "", date: record.date, size: record.size, sha256: record.sha256)
                }
                return record
            }
            var seen = Set(merged.map(\.id))
            for item in backupHistory where seen.insert(item.id).inserted { merged.append(item.localRecord) }
            restoredHistoryData = try JSONEncoder().encode(Array(merged.prefix(100)))
        } else { restoredHistoryData = nil }
        guard !context.hasChanges else { throw MacSettingsFailure.invalid("请先保存或取消正在编辑的内容") }
        let fm = FileManager.default, target = MacBankLogos.directory()
        let staging = target.deletingLastPathComponent().appendingPathComponent("Restore-" + UUID().uuidString)
        let previous = target.deletingLastPathComponent().appendingPathComponent("Previous-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        for (name, bytes) in p.bankLogos { try bytes.write(to: staging.appendingPathComponent(name), options: .atomic) }
        let hadAssets = fm.fileExists(atPath: target.path)
        if hadAssets { try fm.moveItem(at: target, to: previous) }
        do { try fm.moveItem(at: staging, to: target) }
        catch { if hadAssets { try? fm.moveItem(at: previous, to: target) }; throw error }
        let autosave = context.autosaveEnabled; context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {

            for row in try context.fetch(FetchDescriptor<LoanRule>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<RecurringTransaction>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<Transaction>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<DepositRecord>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<Goal>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<Category>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<FinancialProfile>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<Account>()) { context.delete(row) }
            let account = p.account.map { $0.make() }
            for row in account { context.insert(row) }
            let transaction = p.transaction.map { $0.make() }
            for row in transaction { context.insert(row) }
            let category = p.category.map { $0.make() }
            for row in category { context.insert(row) }
            let goal = p.goal.map { $0.make() }
            for row in goal { context.insert(row) }
            let financialProfile = p.financialProfile.map { $0.make() }
            for row in financialProfile { context.insert(row) }
            let recurringTransaction = p.recurringTransaction.map { $0.make() }
            for row in recurringTransaction { context.insert(row) }
            let depositRecord = p.depositRecord.map { $0.make() }
            for row in depositRecord { context.insert(row) }
            let loanRule = p.loanRule.map { $0.make() }
            for row in loanRule { context.insert(row) }

            let lookup = Dictionary(uniqueKeysWithValues: recurringTransaction.map { ($0.id, $0) })
            for (index, row) in loanRule.enumerated() { row.generatedRules = p.loanRule[index].generatedRuleIDs.compactMap { lookup[$0] } }
            if let save { try save(context) } else { try context.save() }
        } catch {
            context.rollback()
            try? fm.removeItem(at: target)
            if hadAssets { try? fm.moveItem(at: previous, to: target) }
            throw error
        }
        try? fm.removeItem(at: previous)
        MacSettingsStore.restoreSettings(settings)
        if let updateTrustToRestore {
            MacPreferences.defaults.set(updateTrustToRestore.url, forKey: "v2_update_url")
            MacPreferences.defaults.set(updateTrustToRestore.publicKey, forKey: "v2_update_public_key")
            MacUpdateService.shared.reset()
        }
        if let restoredHistoryData { MacPreferences.defaults.set(restoredHistoryData, forKey: "v2_backup_history") }
        MacNotifications.clear()
        NotificationCenter.default.post(name: MacSettingsStore.restoreCompleted, object: nil)
    }
}
