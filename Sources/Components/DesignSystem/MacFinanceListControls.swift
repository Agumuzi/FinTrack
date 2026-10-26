import SwiftUI
import AppKit

struct MacFinanceListToolbar<Sort: Hashable>: View {
    @Binding var columns: Int
    @Binding var sort: Sort
    var options: [(String, Sort)]
    var prefix: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { columnChoices; Spacer(minLength: 4); sortMenu.fixedSize(horizontal: true, vertical: false) }
            VStack(alignment: .leading, spacing: 8) { columnChoices; sortMenu }
        }.accessibilityElement(children: .contain).accessibilityIdentifier(prefix + "ListToolbar")
    }
    private var columnChoices: some View {
        HStack(spacing: 2) {
            ForEach([1, 2], id: \.self) { count in
                Button { columns = count } label: {
                    Text(count == 1 ? "单列" : "双列").appFont(.caption, weight: .medium)
                        .padding(.horizontal, 8).frame(minHeight: 32)
                        .foregroundStyle(columns == count ? MacUI.accent : .secondary)
                        .background(columns == count ? MacUI.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
                }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier(prefix + "Columns-\(count)").accessibilityValue(columns == count ? "已选中" : "未选中")
            }
        }.padding(3).background(.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 9)).fixedSize()
    }
    private var sortMenu: some View {
        MacSettingsMenu(selection: $sort, options: options).frame(minWidth: max(165, MacUI.fontTier.bodySize * 8 + 32)).accessibilityIdentifier(prefix + "Sort")
    }

}

struct MacFinanceListDivider: View {
    @Binding var width: Double
    var maximum: Double
    var commit: (Double) -> Void = { _ in }
    @State private var initial: Double?
    private func fitted(_ value: Double) -> Double { min(max(300,value),max(300,maximum)) }
    var body: some View {
        Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 7).contentShape(Rectangle())
            .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
                if initial == nil { initial = fitted(width) }
                width = fitted((initial ?? width) + value.translation.width / MacInterfaceZoom.factor)
            }.onEnded { value in
                let final = fitted((initial ?? width) + value.translation.width / MacInterfaceZoom.factor)
                width = final; commit(final); initial = nil
            }).accessibilityLabel("调整列表宽度").accessibilityValue(String(Int(width)))
            .accessibilityAdjustableAction { direction in
                let value = fitted(width + (direction == .increment ? 20 : -20)); width = value; commit(value)
            }
    }
}

/// Preserve the chosen column count; zoom gives list cards space by borrowing
/// it from the detail pane. Narrow windows show the detail in a sheet.
enum MacFinanceSplitSizing {
    static func minimumListWidth(columns: Int, bodySize: CGFloat, titles: [String] = []) -> CGFloat {
        let font = MacInterfaceFonts.font(size: bodySize, weight: .semibold)
        let titleWidth = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let card = max(250 + max(0, bodySize - 16) * 9, titleWidth + 32 + 8 + 24)
        return CGFloat(columns == 2 ? 2 : 1) * card + (columns == 2 ? 10 : 0) + 38
    }
    static func detailMinimum(bodySize: CGFloat) -> CGFloat { max(260, 260 + (bodySize - 16) * 2) }
}
