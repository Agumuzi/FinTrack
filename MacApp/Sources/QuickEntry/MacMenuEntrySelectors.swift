import SwiftUI
import AppKit

/// A real native popup owns the entire painted field, including its icon and text.
struct MacEntrySelectionField<Content: View>: View {
    @Binding var selection: String
    var options: [(String, String)]
    var identifier: String
    var label: String
    var height: CGFloat = 44
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: height)
            .modifier(MacEntryFieldBorder()).allowsHitTesting(false).accessibilityHidden(true)
            .overlay {
                MacEntryNativePopup(selection: $selection, options: options, identifier: identifier, label: label)
                    .frame(maxWidth: .infinity).frame(height: height)
            }
    }
}

private struct MacEntryNativePopup: NSViewRepresentable {
    @Binding var selection: String
    var options: [(String, String)]
    var identifier: String
    var label: String
    @Environment(\.isEnabled) private var enabled
    @AppStorage("v2_font_tier",store:MacPreferences.defaults) private var tier = "standard"
    final class Coordinator: NSObject {
        var choose: ((Int) -> Void)?
        var optionSignature: [String] = []
        @objc func selected(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem, commit = choose
            DispatchQueue.main.async { commit?(index) }
        }
    }
    final class Popup: NSPopUpButton {
        override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
        override func draw(_ dirtyRect: NSRect) {
            if window?.firstResponder === self {
                NSColor.keyboardFocusIndicatorColor.setStroke()
                let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7)
                ring.lineWidth = 2; ring.stroke()
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = Popup(frame: .zero, pullsDown: false)
        popup.isBordered = false
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return popup
    }
    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        let signature = options.map { $0.0 + "\0" + $0.1 }
        if context.coordinator.optionSignature != signature {
            popup.removeAllItems()
            for option in options { popup.addItem(withTitle: option.0) }
            context.coordinator.optionSignature = signature
        }
        if let index = options.firstIndex(where: { $0.1 == selection }) { popup.selectItem(at: index) }
        let size = MacUI.fontSize(.body,tier:MacFontSizeTier(rawValue:tier) ?? .standard)
        let font = NSFont.systemFont(ofSize:size,weight:.medium), menuFont = NSFont.systemFont(ofSize:size,weight:.regular)
        if popup.font != font { popup.font = font }
        if popup.menu?.font != menuFont { popup.menu?.font = menuFont }
        popup.isEnabled = enabled
        popup.setAccessibilityIdentifier(identifier)
        popup.setAccessibilityLabel(label)
        popup.setAccessibilityValue(options.first { $0.1 == selection }?.0 ?? label)
        popup.target = context.coordinator; popup.action = #selector(Coordinator.selected(_:))
        context.coordinator.choose = { index in if options.indices.contains(index) { selection = options[index].1 } }
        popup.needsDisplay = true
    }
}
