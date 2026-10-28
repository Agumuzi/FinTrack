import SwiftUI
import AppKit

/// One geometry and presentation for every currency dropdown in the shipping app.
enum MacCurrencyMenuStyle {
    static let width: CGFloat = 164
    static let height: CGFloat = 44
    static var fieldWidth:CGFloat {width+max(0,MacUI.fontTier.bodySize-16)*5}
    static var fieldHeight:CGFloat {MacInterfaceFonts.controlHeight(height)}
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
        let logicalSize = MacIconMenu.fittedRect(NSSize(width:cropped.width,height:cropped.height),in:NSRect(x:0,y:0,width:24,height:17)).size
        let image = NSImage(cgImage:cropped,size:logicalSize)
        cached[code] = image; return image
    }
}

struct MacIconMenuOption {
    var title: String
    var value: String?
    var symbol: String? = nil
    var image: NSImage? = nil
}

/// Native keyboard/menu tracking and one visual style for icon-and-name dropdowns.
struct MacIconMenu: View {
    @AppStorage(MacInterfaceFonts.preferenceKey, store: MacPreferences.defaults) private var interfaceFont = ""
    @Binding var selection: String
    var options: [MacIconMenuOption]
    var identifier: String
    var accessibilityTitle: String
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var bodyPoints = 16
    var width: CGFloat = MacCurrencyMenuStyle.width
    var compact = false
    var fillsAvailableWidth = false
    var body: some View {
        PopupRepresentable(selection:$selection,options:options,width:width + max(0, MacUI.fontTier.bodySize - 16) * 5,accessibilityTitle:accessibilityTitle,identifier:identifier,compact:compact)
            .frame(width: fillsAvailableWidth ? nil : (compact ? 30 : width + max(0, MacUI.fontTier.bodySize - 16) * 5),height:MacInterfaceFonts.controlHeight(MacCurrencyMenuStyle.height))
            .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
    }
    static func fittedRect(_ size: NSSize, in slot: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return slot }
        let scale = min(slot.width / size.width, slot.height / size.height)
        let fitted = NSSize(width:size.width * scale,height:size.height * scale)
        return NSRect(x:slot.midX-fitted.width/2,y:slot.midY-fitted.height/2,width:fitted.width,height:fitted.height)
    }
    private struct PopupRepresentable: NSViewRepresentable {
        @Binding var selection: String
        var options: [MacIconMenuOption]
        var width: CGFloat
        var accessibilityTitle: String
        var identifier: String
        var compact: Bool
        @Environment(\.isEnabled) private var enabled
        @AppStorage(MacInterfaceFonts.preferenceKey, store: MacPreferences.defaults) private var interfaceFont = ""
        @AppStorage("v2_font_tier",store:MacPreferences.defaults) private var tier = "standard"
        @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var bodyPoints = 16
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
            var compact = false
            override var alignmentRectInsets:NSEdgeInsets { .init(top:0,left:0,bottom:0,right:0) }
            override func draw(_ dirtyRect:NSRect) {
                if compact {
                    NSImage(systemSymbolName:"chevron.down",accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[.secondaryLabelColor]))?.draw(in:NSRect(x:(bounds.width-12)/2,y:(bounds.height-12)/2,width:12,height:12))
                    return
                }
                let border = NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:9,yRadius:9)
                NSColor.controlBackgroundColor.setFill(); border.fill()
                NSColor.gray.withAlphaComponent(0.25).setStroke(); border.lineWidth = 1; border.stroke()
                let flagRect = NSRect(x:12,y:(bounds.height-17)/2,width:24,height:17)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect:flagRect,xRadius:3,yRadius:3).addClip()
                if let image = selectedItem?.image {
                    let glyph = image.isTemplate
                        ? image.withSymbolConfiguration(.init(paletteColors:[isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor])) ?? image
                        : image
                    glyph.draw(in: MacIconMenu.fittedRect(glyph.size, in: flagRect))
                }
                NSGraphicsContext.restoreGraphicsState()
                let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
                let attributes:[NSAttributedString.Key:Any] = [.paragraphStyle:paragraph,.font:font ?? NSFont.systemFont(ofSize:16,weight:.semibold),.foregroundColor:isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor]
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
            (popup as? Popup)?.compact = compact
            let signature = options.map { $0.title + "\0" + ($0.value ?? "__heading__") + "\0" + ($0.symbol ?? "") + "\0" + ($0.image?.name() ?? "") }
            if context.coordinator.optionSignature != signature || popup.menu == nil {
                let menu = NSMenu(); menu.minimumWidth = width; menu.autoenablesItems = false
                for option in options {
                    let item = NSMenuItem(title:option.title,action:nil,keyEquivalent:"")
                    item.isEnabled = option.value != nil
                    if let source = option.image ?? option.symbol.flatMap({ NSImage(systemSymbolName:$0,accessibilityDescription:nil) }),
                       let image = source.copy() as? NSImage {
                        image.size = MacIconMenu.fittedRect(image.size, in:NSRect(x:0,y:0,width:24,height:17)).size
                        item.image = image
                    }
                    menu.addItem(item)
                }
                popup.menu = menu; context.coordinator.optionSignature = signature
            }
            if let index = options.firstIndex(where: { $0.value == selection }) { popup.selectItem(at:index) } else { popup.select(nil) }
            let size = MacUI.fontSize(.body,tier:MacFontSizeTier(rawValue:tier) ?? .standard)
            let font = MacInterfaceFonts.font(size:size,weight:.semibold), menuFont = MacInterfaceFonts.font(size:size,weight:.regular)
            if popup.font != font { popup.font = font }
            let scaledMenuFont = MacInterfaceFonts.font(size:size * MacInterfaceZoom.factor,weight:.regular)
            if popup.menu?.font != scaledMenuFont { popup.menu?.font = scaledMenuFont }
            popup.isEnabled = enabled; popup.setAccessibilityIdentifier(identifier)
            popup.setAccessibilityLabel(accessibilityTitle); popup.setAccessibilityValue(options.first { $0.value == selection }?.title ?? selection)
            popup.target = context.coordinator; popup.action = #selector(Coordinator.selected(_:)); popup.needsDisplay = true
            context.coordinator.choose = { index in if options.indices.contains(index), let value = options[index].value { selection = value } }
        }
    }
}


struct MacCurrencyMenu: View {
    @Binding var selection: String
    var codes: [String]
    var identifier: String
    var prefixOptions: [(String,String)] = []
    var suffixOptions: [(String,String)] = []
    var body: some View {
        var seen:Set<String> = []
        let extra = !selection.isEmpty && !(prefixOptions + suffixOptions).contains { $0.1 == selection } ? [selection] : []
        let values = (codes + extra).filter { !$0.isEmpty && seen.insert($0).inserted }
        let options = prefixOptions.map { MacIconMenuOption(title:$0.0,value:$0.1,symbol:"globe") }
            + values.map { MacIconMenuOption(title:$0,value:$0,image:MacCurrencyGlyph.image(String($0.split(separator:"/").first ?? ""))) }
            + suffixOptions.map { MacIconMenuOption(title:$0.0,value:$0.1,symbol:"globe") }
        return MacIconMenu(selection:$selection,options:options,identifier:identifier,accessibilityTitle:"货币")
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
                        .frame(width:max(76,MacUI.fontTier.bodySize * 3),height:MacInterfaceFonts.controlHeight(32))
                        .focused($focused).accessibilityLabel("其他货币代码").accessibilityIdentifier(textIdentifier)
                    Button { custom = false } label: { Image(systemName:"chevron.down").frame(width:24,height:32) }
                        .fixedSize()
                        .buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel("返回货币选择").accessibilityIdentifier(identifier + "Back")
                }.padding(.horizontal,12).frame(height:MacCurrencyMenuStyle.fieldHeight).modifier(MacEntryFieldBorder())
            } else {
                MacCurrencyMenu(selection:Binding(get:{currency},set:{ value in
                    if value == "__other__" { custom = true } else { currency = value }
                }),codes:Array(Set(codes + [currency])).sorted(),identifier:identifier,suffixOptions:[("其他…","__other__")])
            }
        }.frame(width:MacCurrencyMenuStyle.fieldWidth,height:MacCurrencyMenuStyle.fieldHeight)
            .onChange(of:custom) { _, value in if value { DispatchQueue.main.async { focused = true } } }
    }
}
