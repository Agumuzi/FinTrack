import Foundation

nonisolated enum MacCSVSnapshotEncoder {
    static func encode(_ p: MacNativeBackup.Payload, section: String?) throws -> String {
        let transactions=p.transaction,recurringRules=p.recurringTransaction,deposits=p.depositRecord,loans=p.loanRule
        let goals=p.goal,profiles=p.financialProfile,categories=p.category,accounts=p.account
        let iso=ISO8601DateFormatter()
        // Receipt and calendar identities use Int64 epoch seconds (toward zero).
        // Match that convention for pre-1970 fractional dates as well.
        func isoDateString(from date: Date?) -> String {date.map{iso.string(from:Date(timeIntervalSince1970:$0.timeIntervalSince1970.rounded(.towardZero)))} ?? ""}
        func escapeCSV(_ value:String) -> String {"\""+value.replacingOccurrences(of:"\"",with:"\"\"")+"\""}
        func sectionHeader(_ title:String) -> String {"\"Section\",\""+title+"\""}
        var sections: [String] = []

        sections.append(sectionHeader("Transactions"))
        sections.append("ID,OwnerUID,Date,Type,Category,Currency,Amount,Note,OriginalAmount,OriginalCurrency,ExchangeRateToBase,BaseAmount,BaseCurrency,CreatedAt,UpdatedAt,DeletedAt,LastModifiedDeviceID,SyncVersion")
        sections.append(contentsOf: transactions.map { transaction in
            let id = escapeCSV(transaction.id.uuidString)
            let ownerUID = escapeCSV(transaction.ownerUID ?? "")
            let date = isoDateString(from: transaction.date)
            let type = escapeCSV(transaction.type)
            let category = escapeCSV(transaction.category)
            let currency = escapeCSV(transaction.baseCurrencyCode)
            let amount = String(transaction.baseAmount)
            let note = escapeCSV(transaction.note ?? "")
            let originalAmount = String(transaction.originalAmount)
            let originalCurrency = escapeCSV(transaction.originalCurrency)
            let exchangeRate = String(transaction.exchangeRateToBase)
            let baseAmount = String(transaction.baseAmount)
            let baseCurrency = escapeCSV(transaction.baseCurrencyCode)
            let createdAt = isoDateString(from: transaction.createdAt)
            let updatedAt = isoDateString(from: transaction.updatedAt)
            let deletedAt = isoDateString(from: transaction.deletedAt)
            let lastModifiedDeviceID = escapeCSV(transaction.lastModifiedDeviceID)
            let syncVersion = String(transaction.syncVersion)
            return "\(id),\(ownerUID),\(date),\(type),\(category),\(currency),\(amount),\(note),\(originalAmount),\(originalCurrency),\(exchangeRate),\(baseAmount),\(baseCurrency),\(createdAt),\(updatedAt),\(deletedAt),\(lastModifiedDeviceID),\(syncVersion)"
        })

        sections.append("")
        sections.append(sectionHeader("Recurring Transactions"))
        sections.append("ID,OwnerUID,Title,Type,Category,Currency,Amount,OriginalAmount,OriginalCurrency,ExchangeRateToBase,BaseAmount,BaseCurrency,IntervalValue,IntervalUnit,NextExecutionDate,LastExecutionDate,EndDate,IsActive,NotificationsEnabled,ReminderDaysBefore,ReminderHour,ReminderMinute,Note,ProjectIdentifier,CreatedAt,UpdatedAt,DeletedAt,LastModifiedDeviceID,SyncVersion")
        sections.append(contentsOf: recurringRules.map { rule in
            let id = escapeCSV(rule.id.uuidString)
            let ownerUID = escapeCSV(rule.ownerUID ?? "")
            let title = escapeCSV(rule.title)
            let type = escapeCSV(rule.type)
            let category = escapeCSV(rule.category)
            let currency = escapeCSV(rule.currency)
            let amount = String(rule.amount)
            let originalAmount = String(rule.originalAmount)
            let originalCurrency = escapeCSV(rule.originalCurrency)
            let exchangeRate = String(rule.exchangeRateToBase)
            let baseAmount = String(rule.baseAmount)
            let baseCurrency = escapeCSV(rule.baseCurrencyCode)
            let intervalValue = String(rule.intervalValue)
            let intervalUnit = escapeCSV(rule.intervalUnit)
            let nextDate = isoDateString(from: rule.nextExecutionDate)
            let lastDate = isoDateString(from: rule.lastExecutionDate)
            let endDate = isoDateString(from: rule.endDate)
            let isActive = String(rule.isActive)
            let notificationsEnabled = String(rule.notificationsEnabled)
            let reminderDaysBefore = String(rule.reminderDaysBefore)
            let reminderHour = String(rule.reminderHour)
            let reminderMinute = String(rule.reminderMinute)
            let note = escapeCSV(rule.note ?? "")
            let projectIdentifier = escapeCSV(rule.projectIdentifier ?? "")
            let createdAt = isoDateString(from: rule.createdAt)
            let updatedAt = isoDateString(from: rule.updatedAt)
            let deletedAt = isoDateString(from: rule.deletedAt)
            let lastModifiedDeviceID = escapeCSV(rule.lastModifiedDeviceID)
            let syncVersion = String(rule.syncVersion)

            return "\(id),\(ownerUID),\(title),\(type),\(category),\(currency),\(amount),\(originalAmount),\(originalCurrency),\(exchangeRate),\(baseAmount),\(baseCurrency),\(intervalValue),\(intervalUnit),\(nextDate),\(lastDate),\(endDate),\(isActive),\(notificationsEnabled),\(reminderDaysBefore),\(reminderHour),\(reminderMinute),\(note),\(projectIdentifier),\(createdAt),\(updatedAt),\(deletedAt),\(lastModifiedDeviceID),\(syncVersion)"
        })

        sections.append("")
        sections.append(sectionHeader("Deposits"))
        sections.append("ID,OwnerUID,BankName,Principal,OriginalPrincipal,OriginalCurrency,BasePrincipal,BaseCurrency,PrincipalExchangeRateToBase,AnnualInterestRate,InterestSettlementMode,ExpectedInterest,BaseExpectedInterest,InterestExchangeRateToBase,IsInterestManuallyEdited,Currency,StartDate,MaturityDate,IsActive,HasCreditedInterest,LastInterestPayoutDate,NextInterestPayoutDate,NotificationsEnabled,ReminderDaysBefore,ReminderHour,ReminderMinute,Note,MaturityInterestHandling,SourceDepositID,RolloverBasePrincipalAmount,RolloverBaseInterestAmount,CreatedAt,UpdatedAt,DeletedAt,LastModifiedDeviceID,SyncVersion")
        sections.append(contentsOf: deposits.map { deposit in
            let id = escapeCSV(deposit.id.uuidString)
            let ownerUID = escapeCSV(deposit.ownerUID ?? "")
            let bankName = escapeCSV(deposit.bankName)
            let principal = String(deposit.principal)
            let originalPrincipal = String(deposit.originalPrincipal)
            let originalCurrency = escapeCSV(deposit.originalCurrency)
            let basePrincipal = String(deposit.basePrincipal)
            let baseCurrency = escapeCSV(deposit.baseCurrencyCode)
            let principalRate = String(deposit.principalExchangeRateToBase)
            let annualRate = String(deposit.annualInterestRate)
            let settlementMode = escapeCSV(deposit.interestSettlementMode)
            let expectedInterest = String(deposit.expectedInterest)
            let baseExpectedInterest = String(deposit.baseExpectedInterest)
            let interestRate = String(deposit.interestExchangeRateToBase)
            let isInterestManuallyEdited = String(deposit.isInterestManuallyEdited)
            let currency = escapeCSV(deposit.currency)
            let startDate = isoDateString(from: deposit.startDate)
            let maturityDate = isoDateString(from: deposit.maturityDate)
            let isActive = String(deposit.isActive)
            let hasCreditedInterest = String(deposit.hasCreditedInterest)
            let lastPayoutDate = isoDateString(from: deposit.lastInterestPayoutDate)
            let nextPayoutDate = isoDateString(from: deposit.nextInterestPayoutDate)
            let notificationsEnabled = String(deposit.notificationsEnabled)
            let reminderDaysBefore = String(deposit.reminderDaysBefore)
            let reminderHour = String(deposit.reminderHour)
            let reminderMinute = String(deposit.reminderMinute)
            let note = escapeCSV(deposit.note ?? "")
            let maturityInterestHandling = escapeCSV(deposit.maturityInterestHandling ?? "")
            let sourceDepositID = escapeCSV(deposit.sourceDepositID?.uuidString ?? "")
            let rolloverBasePrincipalAmount = String((deposit.rolloverBasePrincipalAmount ?? 0))
            let rolloverBaseInterestAmount = String((deposit.rolloverBaseInterestAmount ?? 0))
            let createdAt = isoDateString(from: deposit.createdAt)
            let updatedAt = isoDateString(from: deposit.updatedAt)
            let deletedAt = isoDateString(from: deposit.deletedAt)
            let lastModifiedDeviceID = escapeCSV(deposit.lastModifiedDeviceID)
            let syncVersion = String(deposit.syncVersion)

            return "\(id),\(ownerUID),\(bankName),\(principal),\(originalPrincipal),\(originalCurrency),\(basePrincipal),\(baseCurrency),\(principalRate),\(annualRate),\(settlementMode),\(expectedInterest),\(baseExpectedInterest),\(interestRate),\(isInterestManuallyEdited),\(currency),\(startDate),\(maturityDate),\(isActive),\(hasCreditedInterest),\(lastPayoutDate),\(nextPayoutDate),\(notificationsEnabled),\(reminderDaysBefore),\(reminderHour),\(reminderMinute),\(note),\(maturityInterestHandling),\(sourceDepositID),\(rolloverBasePrincipalAmount),\(rolloverBaseInterestAmount),\(createdAt),\(updatedAt),\(deletedAt),\(lastModifiedDeviceID),\(syncVersion)"
        })

        sections.append("")
        sections.append(sectionHeader("Loans"))
        sections.append("ID,OwnerUID,Title,Currency,Principal,BasePrincipal,BaseCurrency,ExchangeRateToBase,AnnualRate,TermMonths,Method,TotalAmount,DownPaymentAmount,DownPaymentPercent,StartDate,Category,Note,CreatedAt,UpdatedAt,DeletedAt,LastModifiedDeviceID,SyncVersion")
        sections.append(contentsOf: loans.map { loan in
            let id = escapeCSV(loan.id.uuidString)
            let ownerUID = escapeCSV(loan.ownerUID ?? "")
            let title = escapeCSV(loan.title)
            let currency = escapeCSV(loan.currency)
            let principal = String(loan.principal)
            let basePrincipal = String(loan.basePrincipal)
            let baseCurrency = escapeCSV(loan.baseCurrencyCode)
            let exchangeRate = String(loan.exchangeRateToBase)
            let annualRate = String(loan.annualRate)
            let termMonths = String(loan.termMonths)
            let method = escapeCSV(loan.methodRawValue)
            let totalAmount = String(loan.totalAmount)
            let downPaymentAmount = String(loan.downPaymentAmount)
            let downPaymentPercent = String(loan.downPaymentPercent)
            let startDate = isoDateString(from: loan.startDate)
            let category = escapeCSV(loan.category)
            let note = escapeCSV(loan.note)
            let createdAt = isoDateString(from: loan.createdAt)
            let updatedAt = isoDateString(from: loan.updatedAt)
            let deletedAt = isoDateString(from: loan.deletedAt)
            let lastModifiedDeviceID = escapeCSV(loan.lastModifiedDeviceID)
            let syncVersion = String(loan.syncVersion)

            return "\(id),\(ownerUID),\(title),\(currency),\(principal),\(basePrincipal),\(baseCurrency),\(exchangeRate),\(annualRate),\(termMonths),\(method),\(totalAmount),\(downPaymentAmount),\(downPaymentPercent),\(startDate),\(category),\(note),\(createdAt),\(updatedAt),\(deletedAt),\(lastModifiedDeviceID),\(syncVersion)"
        })

        sections.append("")
        sections.append(sectionHeader("Goals"))
        sections.append("ID,OwnerUID,Title,TargetAmount,StartDate,Deadline,TargetDatePrecision,TargetDateValue,IncludesCurrentAssets,CreationNetWorth,IsAccomplished,IsPaused,CreatedAt,UpdatedAt,DeletedAt,LastModifiedDeviceID,SyncVersion")
        sections.append(contentsOf: goals.map { goal in
            let id = escapeCSV(goal.id.uuidString)
            let ownerUID = escapeCSV(goal.ownerUID ?? "")
            let title = escapeCSV(goal.title)
            let targetAmount = String(goal.targetAmount)
            let startDate = isoDateString(from: goal.startDate)
            let deadline = isoDateString(from: goal.deadline)
            let includesAssets = String(goal.includesCurrentAssets)
            let creationNetWorth = String(goal.creationNetWorth)
            let isAccomplished = String(goal.isAccomplished)
            let isPaused = String(goal.isPaused)
            let createdAt = isoDateString(from: goal.createdAt)
            let updatedAt = isoDateString(from: goal.updatedAt)
            let deletedAt = isoDateString(from: goal.deletedAt)
            let lastModifiedDeviceID = escapeCSV(goal.lastModifiedDeviceID)
            let syncVersion = String(goal.syncVersion)

            return "\(id),\(ownerUID),\(title),\(targetAmount),\(startDate),\(deadline),\(escapeCSV(goal.targetDatePrecisionRaw ?? "")),\(escapeCSV(goal.targetDateValueRaw ?? "")),\(includesAssets),\(creationNetWorth),\(isAccomplished),\(isPaused),\(createdAt),\(updatedAt),\(deletedAt),\(lastModifiedDeviceID),\(syncVersion)"
        })

        sections.append("")
        sections.append(sectionHeader("Financial Profile"))
        sections.append("ID,OwnerUID,InitialAssets,InitialDebt,CreatedAt,UpdatedAt,DeletedAt,LastModifiedDeviceID,SyncVersion")
        sections.append(contentsOf: profiles.map { profile in
            let id = escapeCSV(profile.id.uuidString)
            let ownerUID = escapeCSV(profile.ownerUID ?? "")
            let initialAssets = String(profile.initialAssets)
            let initialDebt = String(profile.initialDebt)
            let createdAt = isoDateString(from: profile.createdAt)
            let updatedAt = isoDateString(from: profile.updatedAt)
            let deletedAt = isoDateString(from: profile.deletedAt)
            let lastModifiedDeviceID = escapeCSV(profile.lastModifiedDeviceID)
            let syncVersion = String(profile.syncVersion)
            return "\(id),\(ownerUID),\(initialAssets),\(initialDebt),\(createdAt),\(updatedAt),\(deletedAt),\(lastModifiedDeviceID),\(syncVersion)"
        })

        sections.append("")
        sections.append(sectionHeader("Categories"))
        sections.append("ID,OwnerUID,Name,Type,CreatedAt,UpdatedAt,DeletedAt,LastModifiedDeviceID,SyncVersion")
        sections.append(contentsOf: categories.map { category in
            let id = escapeCSV(category.id.uuidString)
            let ownerUID = escapeCSV(category.ownerUID ?? "")
            let name = escapeCSV(category.name)
            let type = escapeCSV(category.type)
            let createdAt = isoDateString(from: category.createdAt)
            let updatedAt = isoDateString(from: category.updatedAt)
            let deletedAt = isoDateString(from: category.deletedAt)
            let lastModifiedDeviceID = escapeCSV(category.lastModifiedDeviceID)
            let syncVersion = String(category.syncVersion)
            return "\(id),\(ownerUID),\(name),\(type),\(createdAt),\(updatedAt),\(deletedAt),\(lastModifiedDeviceID),\(syncVersion)"
        })

        sections.append("")
        sections.append(sectionHeader("Accounts"))
        sections.append("Name,Type,Balance,Currency,CreatedAt")
        sections.append(contentsOf: accounts.map { account in
            let name = escapeCSV(account.name)
            let type = escapeCSV(account.type)
            let balance = String(account.balance)
            let currency = escapeCSV(account.currency)
            let createdAt = isoDateString(from: account.createdAt)
            return "\(name),\(type),\(balance),\(currency),\(createdAt)"
        })

        if let section {
            guard let index=sections.firstIndex(of:sectionHeader(section)) else {throw MacSettingsFailure.invalid("导出类型缺失")}
            let end=sections[(index+1)...].firstIndex(where:{$0.hasPrefix("\"Section\",\"")}) ?? sections.endIndex
            var rows=Array(sections[(index+1)..<end])
            while rows.last == "" {rows.removeLast()}
            return "\u{FEFF}"+rows.joined(separator:"\r\n")+"\r\n"
        }
        return sections.joined(separator:"\n")
    }
}
