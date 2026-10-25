import SwiftUI
import Charts

struct MacOverviewCategoryCard: View {
    var type: TransactionType
    var rows: [MacOverviewData.Bucket]
    var total: Double
    var currency: String
    var chartSize: CGFloat
    var open: (String) -> Void
    @State private var selected: String?
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var active: String? { hovered ?? selected }
    private var prefix: String { type == .income ? "overviewIncome" : "overviewExpense" }
    private var title: String { type == .income ? "收入分类" : "支出分类" }
    var body: some View {
        OverviewCard(help: "点击饼图区块定位分类，点击分类查看账目", height: 270) {
            VStack(alignment:.leading,spacing:12) {
                HStack { Text(title).appFont(.body,weight:.semibold).accessibilityIdentifier(prefix+"CategoryTitle"); Spacer(); Text("\(rows.count) 个类别").appFont(.caption).foregroundStyle(.secondary) }
                if rows.isEmpty { ContentUnavailableView(type == .income ? "该期间暂无收入" : "该期间暂无支出",systemImage:"chart.pie").frame(height:chartSize) }
                else {
                    HStack(alignment:.center,spacing:16) {
                        chart.padding(.top,26).padding(.bottom,10)
                        ScrollViewReader { reader in
                            ScrollView {
                                LazyVStack(spacing:4) {
                                    ForEach(rows) { row in
                                        Button { open(row.id) } label: {
                                            HStack(spacing:6) {
                                                Circle().fill(color(row)).frame(width:8,height:8)
                                                Text(MacOverviewStyle.category(row.id)).lineLimit(1).truncationMode(.tail)
                                                Text((total > 0 ? row.amount / total : 0).formatted(.percent.precision(.fractionLength(0)))).foregroundStyle(.secondary).fixedSize()
                                                Spacer(minLength:2)
                                                Text(MacOverviewStyle.money(row.amount) + " " + MacSettingsVisual.symbol(currency)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55).layoutPriority(1)
                                            }.appFont(.caption).padding(.horizontal,7).padding(.vertical,6)
                                                .background(active == row.id ? MacUI.accent.opacity(0.13) : .clear,in:RoundedRectangle(cornerRadius:7)).contentShape(Rectangle())
                                        }.buttonStyle(MacInteractiveButtonStyle()).id(row.id)
                                            .onHover { hovered = $0 ? row.id : nil }
                                            .accessibilityIdentifier(prefix+"Category-"+row.id)
                                            .accessibilityValue(selected == row.id ? "已选中" : "")
                                    }
                                }
                            }.frame(height:chartSize+26)
                            .onChange(of:selected) { _, id in
                                guard let id else { return }
                                withAnimation(reduceMotion ? nil : .easeOut(duration:0.18)) { reader.scrollTo(id,anchor:.center) }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of:rows.map { $0.id + ":" + String($0.amount) }) { _, _ in selected = nil; hovered = nil }
    }
    private func color(_ row: MacOverviewData.Bucket) -> Color { MacAccent.color(MacCategoryCatalog.style(name:row.id,type:type.rawValue).color) }
    private var chart: some View {
        Chart(rows) { row in
            SectorMark(angle:.value("金额",row.amount),innerRadius:.ratio(0.66),outerRadius:.ratio(active == row.id ? 1 : 0.9),angularInset:1.4)
                .foregroundStyle(color(row)).opacity(active == nil || active == row.id ? 1 : 0.7)
                .accessibilityLabel(MacOverviewStyle.category(row.id)).accessibilityValue(MacOverviewStyle.money(row.amount)+" "+currency)
        }.chartLegend(.hidden).frame(width:chartSize,height:chartSize)
            .chartBackground { _ in
                VStack(spacing:3) {
                    Text(MacOverviewStyle.money(total)).accessibilityIdentifier(prefix+"CategoryTotal").appFont(.section,weight:.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.45)
                    Text(currency).appFont(.caption).foregroundStyle(.secondary)
                }.frame(width:chartSize*0.60)
            }
            .chartOverlay { _ in
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase { case .active(let point): hovered = hit(point,size:geometry.size); case .ended: hovered = nil }
                        }
                        .onTapGesture { point in if let id = hit(point,size:geometry.size) { selected = id } }
                    if let hovered, let row = rows.first(where: { $0.id == hovered }) {
                        Text(MacOverviewStyle.category(row.id)+" · "+MacOverviewStyle.money(row.amount)+" "+MacSettingsVisual.symbol(currency)+" · "+(total > 0 ? row.amount/total : 0).formatted(.percent.precision(.fractionLength(1))))
                            .appFont(.caption).padding(5).background(.regularMaterial,in:RoundedRectangle(cornerRadius:6))
                            .fixedSize().position(x:geometry.size.width/2,y:-22).allowsHitTesting(false)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration:0.15),value:active)
            .accessibilityIdentifier(prefix+"Chart")
            .accessibilityRepresentation {
                VStack { ForEach(rows) { row in Button("\(MacOverviewStyle.category(row.id))，\(MacOverviewStyle.money(row.amount)) \(currency)") { selected = row.id }.accessibilityIdentifier(prefix+"Segment-"+row.id) } }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(prefix+"Chart")
    }
    private func hit(_ point: CGPoint, size: CGSize) -> String? {
        let x = point.x-size.width/2, y = point.y-size.height/2, radius = min(size.width,size.height)/2
        let distance = hypot(x,y)
        guard distance >= radius*0.60, distance <= radius+4, total > 0 else { return nil }
        var angle = atan2(y,x)+Double.pi/2
        if angle < 0 { angle += 2*Double.pi }
        let value = angle/(2*Double.pi)*total
        var sum = 0.0
        return rows.first { row in sum += row.amount; return value < sum }?.id
    }
}
