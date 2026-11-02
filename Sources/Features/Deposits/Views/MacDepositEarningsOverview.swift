import SwiftUI

struct MacDepositEarningsOverview: View {
    @ObservedObject private var localization = LocalizationController.shared
    let deposits: [DepositRecord]
    let transactions: [Transaction]
    let now: Date
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    @State private var snapshot = MacDepositEarnings.Snapshot.empty
    private var cardHeight: CGFloat { MacUI.space(132) }
    private var cardWidth: CGFloat? { availableWidth >= MacUI.space(690) ? nil : max(220, min(300, availableWidth * 0.85)) }
    var body: some View {
        let revision = MacDepositEarnings.Revision(deposits: deposits, transactions: transactions, now: now)
        VStack(alignment: .leading, spacing: MacUI.space(8)) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("deposit.earnings.overview")).appFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "info.circle").foregroundStyle(.secondary).appHelp(L10n.text("deposit.earnings.basis"))
            }
            if availableWidth >= MacUI.space(690) {
                HStack(alignment: .top, spacing: MacUI.space(12)) { cards }
            } else {
                // Keep the existing list and detail pane usable at high zoom.
                // Only the overview scrolls horizontally on a narrow window.
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: MacUI.space(12)) { cards }
                }.accessibilityIdentifier("depositEarningsHorizontalScroll")
            }
            if snapshot.excludedDeposits > 0 {
                Label(L10n.format("deposit.earnings.review", Int64(snapshot.excludedDeposits)), systemImage: "exclamationmark.triangle")
                    .appFont(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }.appPadding(.horizontal, 18).appPadding(.vertical, 8)
            .background(MacOverviewStyle.canvas).accessibilityElement(children: .contain).accessibilityIdentifier("depositEarningsOverview")
            .task(id: revision) { refresh() }
    }
    @ViewBuilder private var cards: some View {
        card(L10n.text("deposit.earnings.outstanding"), id: "depositEarningsOutstanding", help: "deposit.earnings.outstanding.help") {
            if snapshot.outstanding.isEmpty { empty("deposit.earnings.none") }
            ForEach(snapshot.outstanding) { row in amount(row.outstanding, currency: row.currency, prominent: true) }
        }
        card(L10n.format("deposit.earnings.year", String(snapshot.year == 0 ? Calendar.current.component(.year, from: now) : snapshot.year)), id: "depositEarningsCurrent", help: "deposit.earnings.current.help") {
            if snapshot.current.isEmpty { empty("deposit.earnings.none") }
            ForEach(snapshot.current) { row in
                VStack(alignment: .leading, spacing: MacUI.space(5)) {
                    amount(row.total, currency: row.currency, prominent: true)
                    detail("deposit.earnings.received", amount: row.received, currency: row.currency)
                    detail("deposit.earnings.unreceived", amount: row.outstanding, currency: row.currency)
                }.appPadding(.bottom, 6)
            }
        }
        card(L10n.text("deposit.earnings.future"), id: "depositEarningsFuture", help: "deposit.earnings.future.help") {
            if snapshot.future.isEmpty { empty("deposit.earnings.future.empty") }
            ForEach(snapshot.future) { year in
                VStack(alignment: .leading, spacing: MacUI.space(5)) {
                    Text(L10n.format("deposit.earnings.year.label", String(year.year))).appFont(.caption, weight: .semibold)
                    ForEach(year.currencies) { row in amount(row.outstanding, currency: row.currency, prominent: false) }
                }.appPadding(.bottom, 6)
            }
        }
    }
    private func card<Content: View>(_ title: String, id: String, help: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(6)) {
            Text(title).appFont(.caption, weight: .semibold).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.space(8), content: content).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.appPadding(14).frame(maxWidth: .infinity, alignment: .topLeading).frame(width: cardWidth, height: cardHeight)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.035)))
            .appHelp(L10n.text(help)).accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
    private func amount(_ value: Decimal, currency: String, prominent: Bool) -> some View {
        Text(MacDisplayPreferences.money(value) + " " + currency)
            .appFont(.body, weight: prominent ? .semibold : .medium).monospacedDigit()
            .foregroundStyle(prominent ? MacUI.accent : .primary).fixedSize(horizontal: false, vertical: true)
    }
    private func detail(_ key: String, amount: Decimal, currency: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacUI.space(6)) {
            Text(L10n.text(key)).foregroundStyle(.secondary)
            Text(MacDisplayPreferences.money(amount) + " " + currency).monospacedDigit()
        }.appFont(.caption).fixedSize(horizontal: false, vertical: true)
    }
    private func empty(_ key: String) -> some View { Text(L10n.text(key)).appFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    private func refresh() {
        snapshot = MacDepositEarnings.snapshot(deposits: deposits, transactions: transactions, now: now)
    }
}
