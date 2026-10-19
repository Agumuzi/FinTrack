import AppKit

/// Pure presentation of monitoring snapshots. No task, timer or fetch exists here.
enum MacMenuBarLabel {
    static func text(configuration: MacAppEntryConfiguration, monitor: MacFXMonitor) -> String {
        guard configuration.information != .icon else { return "FinTrack" }
        guard let pair = configuration.displayPair, monitor.configuration.watchedPairs.contains(pair),
              MacFXCatalog.codes.contains(pair.base), MacFXCatalog.codes.contains(pair.quote) else { return "汇率未选择" }
        let prefix = "\(monitor.configuration.displayUnits) \(pair.base)→\(pair.quote) "
        guard let quote = monitor.quote(pair) else { return prefix + "—" }
        let value = quote.unitRate * Double(monitor.configuration.displayUnits)
        let marker = monitor.isCached(pair) ? "~" : ""
        let preferred = prefix + marker + MacFXMath.formatted(value, digits: monitor.configuration.rateDigits, compact: true)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let budget: CGFloat = configuration.information == .iconAndRate ? 172 : 196
        if (preferred as NSString).size(withAttributes: [.font:font]).width <= budget { return preferred }
        return prefix + marker + (value.isFinite ? String(format: "%.4g", value) : "超出范围")
    }
    static func image(_ style: MacMenuIconStyle) -> NSImage {
        if style == .application { return FinTrackMacApp.menuIcon }
        let image = NSImage(systemSymbolName: style == .arrows ? "arrow.left.arrow.right" : "book.closed", accessibilityDescription: "FinTrack") ?? FinTrackMacApp.menuIcon
        image.isTemplate = true; image.size = NSSize(width: 18, height: 18); return image
    }
}
