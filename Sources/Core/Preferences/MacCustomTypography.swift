import Foundation
import CoreFoundation

/// Presentation-only point sizes. Layout spacing and stored financial values do not scale.
enum MacCustomTypography {
    static let bodyKey = "v143_body_font_size"
    static let captionKey = "v143_caption_font_size"
    static let bodyRange = 10...32
    static let captionRange = 8...28
    static func value(_ key: String, fallback: Int, range: ClosedRange<Int>) -> CGFloat {
        guard let number = MacPreferences.defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return CGFloat(fallback) }
        return CGFloat(min(range.upperBound, max(range.lowerBound, number.intValue)))
    }
    static func set(body: Int, caption: Int) {
        let d = MacPreferences.defaults
        d.set(min(bodyRange.upperBound, max(bodyRange.lowerBound, body)), forKey: bodyKey)
        d.set(min(captionRange.upperBound, max(captionRange.lowerBound, caption)), forKey: captionKey)
        d.set(MacFontSizeTier.custom.rawValue, forKey: MacFontSizeTier.preferenceKey)
    }
    static func adjust(_ direction: Int) {
        set(body: Int(MacUI.fontTier.bodySize) + direction, caption: Int(MacUI.fontTier.captionSize) + direction)
    }
    static func reset() {
        MacPreferences.defaults.removeObject(forKey: bodyKey); MacPreferences.defaults.removeObject(forKey: captionKey)
        MacPreferences.defaults.set(MacFontSizeTier.standard.rawValue, forKey: MacFontSizeTier.preferenceKey)
    }
}
