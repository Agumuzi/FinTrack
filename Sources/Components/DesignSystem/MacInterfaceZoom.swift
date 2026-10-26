import SwiftUI
import CoreFoundation

/// UI zoom and text sizes are separate preferences. All dimensions passed to a
/// zoom boundary remain logical points; the containing native window stays physical.
enum MacInterfaceZoom {
    static let key = "v144_interface_zoom"
    static let range = 50...150
    static var percent: Int {
        guard let number = MacPreferences.defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return 100 }
        return normalized(number.intValue)
    }
    static var factor: CGFloat { CGFloat(percent) / 100 }
    static func normalized(_ value: Int) -> Int { min(150,max(50,value)) / 10 * 10 }
    static func set(_ value: Int) { MacPreferences.defaults.set(normalized(value), forKey: key) }
    static func adjust(_ direction: Int) { set(percent + direction * 10) }
    static func reset() { set(100) }
}

struct MacZoomLayout: Layout {
    var factor: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let logical = ProposedViewSize(width: proposal.width.map { $0 / factor }, height: proposal.height.map { $0 / factor })
        let size = child.sizeThatFits(logical)
        return CGSize(width: size.width * factor, height: size.height * factor)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: bounds.width / factor, height: bounds.height / factor))
    }
}
private struct MacInterfaceZoomModifier: ViewModifier {
    @AppStorage(MacInterfaceZoom.key, store: MacPreferences.defaults) private var percent = 100
    func body(content: Content) -> some View {
        let _ = percent
        let factor = MacInterfaceZoom.factor
        MacZoomLayout(factor: factor) { content.scaleEffect(factor, anchor: .topLeading) }
            .transaction { $0.animation = nil }
    }
}
extension View {
    /// Apply once per native presentation boundary (window, sheet, or popover).
    func interfaceZoom() -> some View { modifier(MacInterfaceZoomModifier()) }
}
