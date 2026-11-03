import SwiftUI
import Charts

struct MacDepositEarningsOverview: View {
    @ObservedObject private var localization = LocalizationController.shared
    let deposits: [DepositRecord]
    let transactions: [Transaction]
    let now: Date
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    @State private var snapshot = MacDepositEarnings.Snapshot.empty
    @State private var expanded = false
    @State private var percentageCurrencies: Set<String> = []
    var body: some View {
        let revision = MacDepositEarnings.Revision(deposits: deposits, transactions: transactions, now: now)
        VStack(alignment: .leading, spacing: MacUI.space(8)) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("deposit.earnings.overview")).appFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { expanded.toggle() } label: {
                    Image(systemName: "chevron." + (expanded ? "up" : "down"))
                        .foregroundStyle(.secondary).frame(width: MacUI.space(28), height: MacUI.space(24)).contentShape(Rectangle())
                }.buttonStyle(MacInteractiveButtonStyle())
                    .accessibilityLabel(L10n.text(expanded ? "deposit.earnings.collapse" : "deposit.earnings.expand"))
                    .accessibilityValue(L10n.text(expanded ? "deposit.earnings.expanded" : "deposit.earnings.collapsed"))
                    .accessibilityIdentifier("depositEarningsToggle").appHelp(L10n.text("deposit.earnings.basis"))
            }
            if expanded {
                MacDepositEarningsCardRow(horizontal: availableWidth >= MacUI.space(690), spacing: MacUI.space(12)) { cards }
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
            ForEach(snapshot.outstanding) { row in
                let years = yearShares(row.currency)
                HStack(spacing: MacUI.space(12)) {
                    VStack(alignment: .leading, spacing: MacUI.space(8)) {
                        amount(row.outstanding, currency: row.currency, prominent: true)
                        if years.count > 1 {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: MacUI.space(percentageCurrencies.contains(row.currency) ? 95 : 58)))], alignment: .leading, spacing: MacUI.space(4)) {
                                ForEach(years) { share in
                                    HStack(spacing: 4) {
                                        Circle().fill(yearColor(share.year)).frame(width: 6, height: 6)
                                        Text(String(share.year) + (percentageCurrencies.contains(row.currency) ? " · " + MacDepositEarnings.percentage(share.amount, total: row.outstanding) : "")).appFont(.caption).foregroundStyle(.secondary)
                                            .appHelp(String(share.year) + " · " + MacDepositEarnings.percentage(share.amount, total: row.outstanding))
                                    }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if years.count > 1 && availableWidth >= MacUI.space(1100) {
                        Button {
                            if percentageCurrencies.contains(row.currency) { percentageCurrencies.remove(row.currency) }
                            else { percentageCurrencies.insert(row.currency) }
                        } label: {
                            Chart(years) { share in
                                SectorMark(angle: .value(L10n.text("deposit.earnings.outstanding"), NSDecimalNumber(decimal: share.amount).doubleValue), innerRadius: .ratio(0.5), angularInset: 1)
                                    .foregroundStyle(yearColor(share.year))
                                    .accessibilityLabel(String(share.year))
                                    .accessibilityValue(MacDepositEarnings.percentage(share.amount, total: row.outstanding))
                            }.chartLegend(.hidden).frame(width: MacUI.space(70), height: MacUI.space(70))
                        }.buttonStyle(.plain)
                            .appHelp(years.map { String($0.year) + " · " + MacDepositEarnings.percentage($0.amount, total: row.outstanding) }.joined(separator: "\n"))
                            .accessibilityLabel(L10n.text("deposit.earnings.percentages"))
                            .accessibilityIdentifier("depositYearPercentages-" + row.currency)
                    }
                }
            }
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
            VStack(alignment: .leading, spacing: MacUI.space(8), content: content).frame(maxWidth: .infinity, alignment: .leading)
        }.appPadding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.035)))
            .appHelp(L10n.text(help)).accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
    private func amount(_ value: Decimal, currency: String, prominent: Bool, received: Bool = false) -> some View {
        (Text(MacDisplayPreferences.money(value)).foregroundColor(received ? .green : .primary)
         + Text(" " + MacSettingsVisual.symbol(currency)).foregroundColor(.primary))
            .appFont(prominent ? .amount : .body, weight: .semibold).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.65).fixedSize(horizontal: false, vertical: true)
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
                Text(fraction, format: .percent.precision(.fractionLength(0))).appFont(.caption, weight: .semibold).monospacedDigit()
            }
        }.frame(width: MacUI.space(56), height: MacUI.space(56)).appPadding(4)
    }
    private struct YearShare: Identifiable {
        let year: Int
        let amount: Decimal
        var id: Int { year }
    }
    private func yearShares(_ currency: String) -> [YearShare] {
        snapshot.outstandingYears.compactMap { year in
            guard let row = year.currencies.first(where: { $0.currency == currency }), row.outstanding > 0 else { return nil }
            return YearShare(year: year.year, amount: row.outstanding)
        }
    }
    private func yearColor(_ year: Int) -> Color {
        let colors: [Color] = [.blue, .orange, .purple, .teal, .pink, .indigo]
        return colors[((year % colors.count) + colors.count) % colors.count]
    }
    private func empty(_ key: String) -> some View { Text(L10n.text(key)).appFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    private func refresh() {
        snapshot = MacDepositEarnings.snapshot(deposits: deposits, transactions: transactions, now: now)
    }
}

// Measure actual content before placing any card. All cards share the largest
// natural height; no fixed-height viewport can hide a row or create a scrollbar.
private struct MacDepositEarningsCardRow: Layout {
    var horizontal: Bool
    var spacing: CGFloat
    private func dimensions(_ width: CGFloat, subviews: Subviews) -> (width: CGFloat, height: CGFloat) {
        let count = max(1, subviews.count)
        let column = horizontal ? max(1, (width - spacing * CGFloat(count - 1)) / CGFloat(count)) : width
        let height = subviews.map { $0.sizeThatFits(.init(width: column, height: nil)).height }.max() ?? 0
        return (column, height)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        let measured = dimensions(width, subviews: subviews)
        return CGSize(width: width, height: horizontal ? measured.height : measured.height * CGFloat(subviews.count) + spacing * CGFloat(max(0, subviews.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measured = dimensions(bounds.width, subviews: subviews)
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + (horizontal ? CGFloat(index) * (measured.width + spacing) : 0), y: bounds.minY + (horizontal ? 0 : CGFloat(index) * (measured.height + spacing))), anchor: .topLeading, proposal: .init(width: measured.width, height: measured.height))
        }
    }
}
