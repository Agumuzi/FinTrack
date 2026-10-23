import SwiftUI
import SwiftData

struct MacInAppReminders: View {
    let workspace: MacWorkspaceSession
    @Query private var recurring: [RecurringTransaction]
    @Query private var goals: [Goal]
    @Query private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query private var profiles: [FinancialProfile]
    @Query private var deposits: [DepositRecord]
    @Query private var loans: [LoanRule]
    @AppStorage("v2_remind_recurring") private var recurringEnabled = true
    @AppStorage("v2_remind_goals") private var goalsEnabled = true
    @AppStorage("v2_remind_budgets") private var budgetsEnabled = true
    @AppStorage("v2_budgets") private var budgetBytes = Data()
    @AppStorage("base_currency") private var preferredCurrency = "USD"
    private var items: [(String, MacWorkspaceSection, MacSettingsPage?)] {
        let now = Date(), calendar = Calendar.current
        var items: [(String, MacWorkspaceSection, MacSettingsPage?)] = []
        if recurringEnabled {
            let due = recurring.filter {
                guard $0.deletedAt == nil, $0.isActive, $0.notificationsEnabled,
                      !($0.projectIdentifier ?? "").hasPrefix("loan_generated:"),
                      $0.endDate == nil || $0.nextExecutionDate <= $0.endDate! else { return false }
                let reminder = calendar.date(byAdding: .day, value: -max(0, $0.reminderDaysBefore), to: $0.nextExecutionDate) ?? $0.nextExecutionDate
                return reminder <= now
            }
            if !due.isEmpty { items.append(("\(due.count) 项周期收支待处理", .recurring, nil)) }
        }
        let allCodes = Set(transactions.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode) + deposits.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode) + loans.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode) + recurring.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        guard allCodes.count <= 1, allCodes.isEmpty || allCodes.contains(preferredCurrency) else { return items }
        if goalsEnabled {
            let horizon = calendar.date(byAdding: .day, value: 30, to: now)!
            let candidates = goals.filter { $0.deletedAt == nil && !$0.isPaused && !$0.isAccomplished && ($0.targetTime.planningBoundary().map { $0 <= horizon } ?? false) }
            if !candidates.isEmpty {
                let net = MacFinancialSettings.snapshot(profile: profiles.first { $0.deletedAt == nil }, transactions: transactions.filter { $0.date < (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now) }, loans: loans, deposits: deposits, currency: preferredCurrency, asOf: now).netWorth
                let baseline = Goal.baselineNetWorth(from: profiles.first { $0.deletedAt == nil })
                let due = candidates.filter { !$0.isCompleted(currentNetWorth: net, baselineNetWorth: baseline) }
                if !due.isEmpty { items.append(("\(due.count) 个目标临近或超过期望时间", .settings, .goals)) }
            }
        }
        if budgetsEnabled {
            let budgets = (try? JSONDecoder().decode([MacBudget].self, from: budgetBytes)) ?? []
            let month = MacBudgetData.month(now)
            let candidates = budgets.filter { $0.enabled && $0.currency == preferredCurrency && $0.month == month && $0.amount > 0 }
            if !candidates.isEmpty {
                let spending = MacBudgetSpendingSnapshot(rows: transactions, categories: categories)
                let warning = candidates.filter { spending.spent($0) / $0.amount >= 0.8 }
                if !warning.isEmpty { items.append(("\(warning.count) 项预算已使用 80% 或以上", .settings, .budgets)) }
            }
        }
        return items
    }
    var body: some View {
        let items = self.items
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: MacUI.space(8)) {
                ForEach(items.indices, id: \.self) { index in
                    Button {
                        if let page = items[index].2 { MacPreferences.defaults.set(page.id, forKey: "v2_settings_page") }
                        workspace.section = items[index].1
                    } label: { HStack { Label(items[index].0, systemImage: "bell.badge"); Spacer(); Image(systemName: "chevron.right") }.appFont(.caption, weight: .regular, design: .default).contentShape(Rectangle()) }.buttonStyle(.plain)
                }
            }.appPadding(14).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("settingsInAppReminders")
        }
    }
}
