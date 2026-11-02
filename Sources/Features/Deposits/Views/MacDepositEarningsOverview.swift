import SwiftUI

struct MacDepositEarningsOverview: View {
    @ObservedObject private var localization = LocalizationController.shared
    let deposits: [DepositRecord]
    let transactions: [Transaction]
    let now: Date
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    @State private var snapshot = MacDepositEarnings.Snapshot.empty
    @State private var expanded = false
    private var cardHeight: CGFloat { MacUI.space(108) }
    private var cardWidth: CGFloat? { availableWidth >= MacUI.space(690) ? nil : max(220, min(300, availableWidth * 0.85)) }
    var body: some View {
        let revision = MacDepositEarnings.Revision(deposits: deposits, transactions: transactions, now: now)
        VStack(alignment: .leading, spacing: MacUI.space(8)) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("deposit.earnings.overview")).appFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { expanded.toggle() } label: {
                    HStack(spacing: MacUI.space(5)) {
                        Image(systemName: "chevron." + (expanded ? "up" : "down"))
                        Image(systemName: "info.circle")
                    }.foregroundStyle(.secondary).contentShape(Rectangle())
                }.buttonStyle(MacInteractiveButtonStyle())
                    .accessibilityLabel(L10n.text(expanded ? "deposit.earnings.collapse" : "deposit.earnings.expand"))
                    .accessibilityValue(L10n.text(expanded ? "deposit.earnings.expanded" : "deposit.earnings.collapsed"))
                    .accessibilityIdentifier("depositEarningsToggle").appHelp(L10n.text("deposit.earnings.basis"))
            }
            if expanded {
                if availableWidth >= MacUI.space(690) {
                    HStack(alignment: .top, spacing: MacUI.space(12)) { cards }
                } else {
                    // Keep the existing list and detail pane usable at high zoom.
                    // Only the overview scrolls horizontally on a narrow window.
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: MacUI.space(12)) { cards }
                    }.accessibilityIdentifier("depositEarningsHorizontalScroll")
                }
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
                HStack(spacing: MacUI.space(14)) {
                    VStack(alignment: .leading, spacing: MacUI.space(6)) {
                        detail("deposit.earnings.received", amount: row.received, currency: row.currency, received: true)
                        Divider()
                        detail("deposit.earnings.unreceived", amount: row.outstanding, currency: row.currency)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if availableWidth >= MacUI.space(1100) { receivedRing(row) }
                }.appPadding(.bottom, 6)

            }
        }
        card(L10n.text("deposit.earnings.future"), id: "depositEarningsFuture", help: "deposit.earnings.future.help") {
            if snapshot.future.isEmpty { empty("deposit.earnings.future.empty") }
            ForEach(snapshot.future) { year in
                VStack(alignment: .leading, spacing: MacUI.space(5)) {
                    ForEach(year.currencies) { row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.format("deposit.earnings.year.label", String(year.year))).appFont(.caption, weight: .semibold)
                            Spacer(minLength: 8)
                            amount(row.outstanding, currency: row.currency, prominent: false)
                        }
                    }
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
        }.appPadding(10).frame(maxWidth: .infinity, alignment: .topLeading).frame(width: cardWidth, height: cardHeight)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.035)))
            .appHelp(L10n.text(help)).accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
    private func amount(_ value: Decimal, currency: String, prominent: Bool, received: Bool = false) -> some View {
        (Text(MacDisplayPreferences.money(value)).foregroundColor(received ? .green : .primary)
         + Text(" " + MacSettingsVisual.symbol(currency)).foregroundColor(.primary))
            .appFont(prominent ? .dialogTitle : .body, weight: .semibold).monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(MacDisplayPreferences.money(value) + " " + currency)
    }
    private func detail(_ key: String, amount value: Decimal, currency: String, received: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacUI.space(8)) {
            Circle().fill(received ? Color.green : Color.secondary.opacity(0.45)).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(L10n.text(key)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            amount(value, currency: currency, prominent: false, received: received)
        }.appFont(.caption).fixedSize(horizontal: false, vertical: true)
    }
    private func receivedRing(_ row: MacDepositEarnings.CurrencyTotal) -> some View {
        let fraction = row.total > 0 ? min(1, max(0, NSDecimalNumber(decimal: row.received / row.total).doubleValue)) : 0
        return ZStack {
            Circle().stroke(.secondary.opacity(0.16), lineWidth: MacUI.space(7))
            Circle().trim(from: 0, to: fraction).stroke(.green, style: StrokeStyle(lineWidth: MacUI.space(7), lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: MacUI.space(3)) {
                Text(fraction, format: .percent.precision(.fractionLength(1))).appFont(.caption, weight: .semibold).monospacedDigit()
                Text(L10n.text("deposit.earnings.received")).appFont(.caption).foregroundStyle(.secondary)
            }
        }.frame(width: MacUI.space(56), height: MacUI.space(56)).appPadding(4)
    }
    private func empty(_ key: String) -> some View { Text(L10n.text(key)).appFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    private func refresh() {
        snapshot = MacDepositEarnings.snapshot(deposits: deposits, transactions: transactions, now: now)
    }
}
