import SwiftUI
import AppKit

struct MacFinanceListToolbar<Sort: Hashable>: View {
    @Binding var columns: Int
    @Binding var sort: Sort
    var options: [(String, Sort)]
    var prefix: String
    var body: some View {
        HStack(spacing: 8) {
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
            Spacer(minLength: 4)
            MacSettingsMenu(selection: $sort, options: options).frame(width: MacUI.space(165)).accessibilityIdentifier(prefix + "Sort")
        }.accessibilityElement(children: .contain).accessibilityIdentifier(prefix + "ListToolbar")
    }
}

struct MacFinanceListDivider: View {
    @Binding var width: Double
    var maximum: Double
    var commit: (Double) -> Void = { _ in }
    @State private var initial: Double?
    var body: some View {
        Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 5).contentShape(Rectangle())
            .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(coordinateSpace: .global).onChanged { value in
                if initial == nil { initial = min(maximum, max(300, width)) }
                width = min(max(300, (initial ?? width) + value.translation.width), max(300, maximum))
            }.onEnded { _ in commit(width); initial = nil }).accessibilityLabel("调整列表宽度")
    }
}
