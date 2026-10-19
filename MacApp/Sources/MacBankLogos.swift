import AppKit
import SwiftUI
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Appearance assets are independent from financial models, and never fetched online.
enum MacBankLogos {
    static func key(_ bank: String) -> String {
        let name = bank.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        return SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func directory() -> URL {
        // All automated previews/tests use a disposable asset directory.
        if MacPreferences.isTesting {
            let e = ProcessInfo.processInfo.environment
            if let path = e["FINTRACK_V13_TEST_STORE_PATH"], MacTestStore.isIsolated(path) {
                return URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("BankLogos")
            }
            return FileManager.default.temporaryDirectory.appendingPathComponent("FinTrack-Test-BankLogos-\(ProcessInfo.processInfo.processIdentifier)")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FinTrackMac/BankLogos")
    }
    static func customURL(_ bank: String) -> URL { directory().appendingPathComponent(key(bank) + ".png") }
    static func image(_ bank: String) -> NSImage? {
        if let image = NSImage(contentsOf: customURL(bank)) { return image }
        guard let name = bundledName(bank), let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "BankLogos")
            ?? Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
    static func bundledName(_ bank: String) -> String? {
        let name = bank.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch name {
        case "alfa bank", "alfa-bank", "альфа-банк", "альфа банк": return "alfa"
        case "t-bank", "t bank", "т-банк", "т банк", "tbank": return "tbank"
        case "sberbank", "sber", "сбер", "сбербанк": return "sber"
        case "vtb", "втб": return "vtb"
        case "gazprombank", "газпромбанк": return "gazprom"
        default: return nil
        }
    }
    static let storedPixelSize = MacImageAssets.storedPixelSize
    struct CropInput: Identifiable {
        let id = UUID()
        let bank: String
        let image: CGImage
    }
    enum Failure: LocalizedError {
        case invalid, missingBank
        var errorDescription: String? {
            switch self {
            case .invalid: "请选择有效的 PNG、JPEG 或 HEIC 图片（文件不超过 100 MB）。"
            case .missingBank: "请先输入银行名称，再选择对应的图标。"
            }
        }
    }
    // Compatibility facade: bank identity/storage stay here; decoding/cropping live once.
    static func previewImage(_ url: URL) throws -> CGImage { try MacImageAssets.previewImage(url) }
    static func cropRect(_ image: CGImage, zoom: Double, offset: CGPoint) -> CGRect { MacImageAssets.cropRect(image, zoom: zoom, offset: offset) }
    static func croppedPNG(_ image: CGImage, zoom: Double = 1, offset: CGPoint = .zero) throws -> Data { try MacImageAssets.croppedPNG(image, zoom: zoom, offset: offset) }
    static func normalizedPNG(_ url: URL) throws -> Data { try MacImageAssets.normalizedPNG(url) }
    static func install(_ url: URL, bank: String) throws { try save(normalizedPNG(url), bank: bank) }
    static func save(_ data: Data, bank: String) throws {
        try FileManager.default.createDirectory(at: directory(), withIntermediateDirectories: true)
        try data.write(to: customURL(bank), options: .atomic)
    }
    @MainActor
    static func select(for bank: String) throws -> CropInput? {
        guard !bank.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.missingBank }
        guard let input = try MacImageAssets.select(title: "选择银行图标", cropTitle: "裁切银行图标", label: bank) else { return nil }
        return CropInput(bank: bank, image: input.image)
    }
    static func reset(_ bank: String) throws {
        let url = customURL(bank)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

struct MacBankIcon: View {
    let bank: String
    var size: CGFloat = 38
    var revision: Int = 0
    var body: some View {
        Group {
            if let image = MacBankLogos.image(bank) {
                Image(nsImage: image).resizable().scaledToFit().appPadding(5)
            } else {
                Image(systemName: "building.columns").appIconFont(size * 0.48, weight: .regular, design: .default).foregroundStyle(.secondary)
            }
        }.frame(width: MacUI.space(size), height: MacUI.space(size))
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.gray.opacity(0.15)))
            .accessibilityHidden(true)
            .id("\(bank)-\(revision)")
    }
}
