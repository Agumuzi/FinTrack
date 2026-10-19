import SwiftUI
import AppKit

/// One geometry and presentation for every currency dropdown in the shipping app.
enum MacCurrencyMenuStyle {
    static let width: CGFloat = 164
    static let height: CGFloat = 44
}

enum MacCurrencyGlyph {
    private static var cached: [String:NSImage] = [:]
    static func image(_ raw: String) -> NSImage {
        let code = raw.uppercased()
        if let image = cached[code] { return image }
        let asset = ["USD":"us","RUB":"ru","CNY":"cn","EUR":"eu","GBP":"gb","JPY":"jp","CHF":"ch","HKD":"hk"][code]
        if let asset, let url = Bundle.main.url(forResource:"flag-" + asset,withExtension:"png",subdirectory:"Flags") ?? Bundle.main.url(forResource:"flag-" + asset,withExtension:"png"), let image = NSImage(contentsOf:url) { cached[code] = image; return image }
        let mark = MacSettingsVisual.currencyLabel(code).components(separatedBy:" ").first ?? "🌐"
        if mark == "🌐" { return NSImage(systemSymbolName:"globe",accessibilityDescription:nil) ?? NSImage(size:NSSize(width:24,height:16)) }
        // Emoji fonts contain line padding; crop transparent pixels so every flag
        // fills the same 24×17 slot as bundled flag images.
        let canvas = NSImage(size:NSSize(width:64,height:64))
        canvas.lockFocus()
        (mark as NSString).draw(at:NSPoint(x:8,y:8),withAttributes:[.font:NSFont.systemFont(ofSize:40)])
        canvas.unlockFocus()
        guard let cg = canvas.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return canvas }
        let bitmap = NSBitmapImageRep(cgImage:cg)
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0) > 0.01 {
                minX = min(minX,x); minY = min(minY,y); maxX = max(maxX,x); maxY = max(maxY,y)
            }
        }
        guard maxX >= minX, maxY >= minY, let cropped = cg.cropping(to:CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)) else { return canvas }
        let image = NSImage(cgImage:cropped,size:NSSize(width:24,height:17))
        cached[code] = image; return image
    }
}

struct MacCurrencyMenu: View {
    @Binding var selection: String
    var codes: [String]
    var identifier: String
    var prefixOptions: [(String,String)] = []
    var suffixOptions: [(String,String)] = []
    var body: some View {
        CurrencyPopup(selection:$selection,codes:codes,identifier:identifier,prefixOptions:prefixOptions,suffixOptions:suffixOptions)
            .frame(width:MacCurrencyMenuStyle.width,height:MacCurrencyMenuStyle.height)
    }
    private struct CurrencyPopup: NSViewRepresentable {
        @Binding var selection: String
        var codes: [String]
        var identifier: String
        var prefixOptions: [(String,String)]
        var suffixOptions: [(String,String)]
        @Environment(\.isEnabled) private var enabled
        @AppStorage("v2_font_tier",store:MacPreferences.defaults) private var tier = "standard"
        final class Coordinator: NSObject {
            var choose: ((Int) -> Void)?
            var optionSignature: [String] = []
            @objc func selected(_ sender:NSPopUpButton) {
                let index = sender.indexOfSelectedItem, commit = choose
                // Finish native menu tracking before SwiftUI updates the control.
                DispatchQueue.main.async { commit?(index) }
            }
        }
        final class Popup: NSPopUpButton {
            override var alignmentRectInsets:NSEdgeInsets { .init(top:0,left:0,bottom:0,right:0) }
            override func draw(_ dirtyRect:NSRect) {
                let border = NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:9,yRadius:9)
                NSColor.controlBackgroundColor.setFill(); border.fill()
                NSColor.gray.withAlphaComponent(0.25).setStroke(); border.lineWidth = 1; border.stroke()
                let flagRect = NSRect(x:12,y:(bounds.height-17)/2,width:24,height:17)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect:flagRect,xRadius:3,yRadius:3).addClip()
                selectedItem?.image?.draw(in:flagRect)
                NSGraphicsContext.restoreGraphicsState()
                let attributes:[NSAttributedString.Key:Any] = [.font:font ?? NSFont.systemFont(ofSize:16,weight:.semibold),.foregroundColor:isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor]
                let text = titleOfSelectedItem ?? "请选择"
                let size = (text as NSString).size(withAttributes:attributes)
                (text as NSString).draw(in:NSRect(x:44,y:(bounds.height-size.height)/2,width:bounds.width-76,height:size.height),withAttributes:attributes)
                NSImage(systemSymbolName:"chevron.down",accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[.secondaryLabelColor]))?.draw(in:NSRect(x:bounds.width-25,y:(bounds.height-12)/2,width:12,height:12))
                if window?.firstResponder === self {
                    NSColor.keyboardFocusIndicatorColor.setStroke()
                    let ring = NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2),xRadius:7,yRadius:7); ring.lineWidth = 2; ring.stroke()
                }
            }
        }
        func makeCoordinator() -> Coordinator { Coordinator() }
        func makeNSView(context:Context) -> NSPopUpButton {
            let popup = Popup(frame:.zero,pullsDown:false); popup.isBordered = false
            popup.setContentHuggingPriority(.defaultLow,for:.horizontal)
            popup.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
            return popup
        }
        func updateNSView(_ popup:NSPopUpButton,context:Context) {
            var seen:Set<String> = []
            let extra = !selection.isEmpty && !(prefixOptions + suffixOptions).contains { $0.1 == selection } ? [selection] : []
            let values = (codes + extra).filter { !$0.isEmpty && seen.insert($0).inserted }
            let options = prefixOptions + values.map { ($0,$0) } + suffixOptions
            let signature = options.map { $0.0 + "\0" + $0.1 }
            if context.coordinator.optionSignature != signature || popup.menu == nil {
                let menu = NSMenu(); menu.minimumWidth = MacCurrencyMenuStyle.width; menu.autoenablesItems = false
                for (title,value) in options {
                    let item = NSMenuItem(title:title,action:nil,keyEquivalent:"")
                    let image = values.contains(value) ? MacCurrencyGlyph.image(String(value.split(separator:"/").first ?? "")).copy() as? NSImage : NSImage(systemSymbolName:"globe",accessibilityDescription:nil)
                    image?.size = NSSize(width:24,height:17); item.image = image; menu.addItem(item)
                }
                popup.menu = menu; context.coordinator.optionSignature = signature
            }
            if let index = options.firstIndex(where: { $0.1 == selection }) { popup.selectItem(at:index) } else { popup.select(nil) }
            let size = MacUI.fontSize(.body,tier:MacFontSizeTier(rawValue:tier) ?? .standard)
            let font = NSFont.systemFont(ofSize:size,weight:.semibold), menuFont = NSFont.systemFont(ofSize:size,weight:.regular)
            if popup.font != font { popup.font = font }
            if popup.menu?.font != menuFont { popup.menu?.font = menuFont }
            popup.isEnabled = enabled; popup.setAccessibilityIdentifier(identifier)
            popup.setAccessibilityLabel("货币"); popup.setAccessibilityValue(options.first { $0.1 == selection }?.0 ?? selection)
            popup.target = context.coordinator; popup.action = #selector(Coordinator.selected(_:)); popup.needsDisplay = true
            context.coordinator.choose = { index in if options.indices.contains(index) { selection = options[index].1 } }
        }
    }
}

/// Custom entry is explicit; merely opening a dropdown never changes the code.
struct MacEditableCurrencyMenu: View {
    @Binding var currency: String
    @Binding var custom: Bool
    var codes: [String]
    var identifier: String
    var textIdentifier: String
    @FocusState private var focused: Bool
    var body: some View {
        Group {
            if custom {
                HStack(spacing:8) {
                    MacCurrencyFlag(code:currency.uppercased(),width:24)
                        .fixedSize().layoutPriority(1).accessibilityIdentifier(identifier + "Flag")
                    TextField("代码",text:$currency).textFieldStyle(.plain).appFont(.body,weight:.semibold)
                        .frame(width:76,height:32)
                        .focused($focused).accessibilityLabel("其他货币代码").accessibilityIdentifier(textIdentifier)
                    Button { custom = false } label: { Image(systemName:"chevron.down").frame(width:24,height:32) }
                        .fixedSize()
                        .buttonStyle(.plain).accessibilityLabel("返回货币选择").accessibilityIdentifier(identifier + "Back")
                }.padding(.horizontal,12).frame(height:MacCurrencyMenuStyle.height).modifier(MacEntryFieldBorder())
            } else {
                MacCurrencyMenu(selection:Binding(get:{currency},set:{ value in
                    if value == "__other__" { custom = true } else { currency = value }
                }),codes:Array(Set(codes + [currency])).sorted(),identifier:identifier,suffixOptions:[("其他…","__other__")])
            }
        }.frame(width:MacCurrencyMenuStyle.width,height:MacCurrencyMenuStyle.height)
            .onChange(of:custom) { _, value in if value { DispatchQueue.main.async { focused = true } } }
    }
}
