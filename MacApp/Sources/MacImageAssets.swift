import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// One image pipeline for bank logos, profile pictures, API sources and future imports.
enum MacImageAssets {
    static let storedPixelSize = 256
    struct CropInput: Identifiable {
        let id = UUID()
        var title: String
        var label: String
        var image: CGImage
        var circularPreview = false
    }
    enum Failure: LocalizedError {
        case invalid
        var errorDescription: String? { "请选择有效的 PNG、JPEG 或 HEIC 图片（文件不超过 100 MB）。" }
    }
    /// Decode a bounded preview directly from the file. Never retain original bytes.
    static func previewImage(_ url: URL) throws -> CGImage {
        let allowed = ["png", "jpg", "jpeg", "heic"]
        guard allowed.contains(url.pathExtension.lowercased()),
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= 100 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source), [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier].contains(type as String),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw Failure.invalid }
        return cgImage
    }
    /// Offset is a fraction of the square preview width, independent of UI size.
    static func cropRect(_ image: CGImage, zoom: Double, offset: CGPoint) -> CGRect {
        let scale = min(4, max(1, zoom.isFinite ? zoom : 1))
        let side = Double(min(image.width, image.height)) / scale
        let x = (Double(image.width) - side) / 2 - (offset.x.isFinite ? offset.x : 0) * side
        let y = (Double(image.height) - side) / 2 - (offset.y.isFinite ? offset.y : 0) * side
        return CGRect(x: min(Double(image.width) - side, max(0, x)),
                      y: min(Double(image.height) - side, max(0, y)), width: side, height: side)
    }
    static func croppedPNG(_ image: CGImage, zoom: Double = 1, offset: CGPoint = .zero) throws -> Data {
        guard let cropped = image.cropping(to: cropRect(image, zoom: zoom, offset: offset).integral),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let canvas = CGContext(data: nil, width: storedPixelSize, height: storedPixelSize,
                bitsPerComponent: 8, bytesPerRow: storedPixelSize * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.invalid }
        canvas.interpolationQuality = .high
        canvas.draw(cropped, in: CGRect(x: 0, y: 0, width: storedPixelSize, height: storedPixelSize))
        guard let final = canvas.makeImage(), let png = NSBitmapImageRep(cgImage: final).representation(using: .png, properties: [:]), png.count <= 512 * 1024 else { throw Failure.invalid }
        return png
    }
    static func normalizedPNG(_ url: URL) throws -> Data { try croppedPNG(previewImage(url)) }
    static func validatePreparedPNG(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 512 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1, let type = CGImageSourceGetType(source), type as String == UTType.png.identifier,
              let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              values[kCGImagePropertyPixelWidth] as? Int == storedPixelSize,
              values[kCGImagePropertyPixelHeight] as? Int == storedPixelSize,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else { throw Failure.invalid }
    }
    @MainActor
    static func select(title: String, cropTitle: String, label: String = "", circularPreview: Bool = false) throws -> CropInput? {
        let panel = NSOpenPanel(); panel.title = title; panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if MacPreferences.isTesting, let path = ProcessInfo.processInfo.environment["FINTRACK_TEST_LOGO_FOLDER"],
           MacTestStore.isIsolated(URL(fileURLWithPath: path).appendingPathComponent("book.sqlite").path) {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        return CropInput(title: cropTitle, label: label, image: try previewImage(url), circularPreview: circularPreview)
    }
}

/// The UI owns a draft binding; cancelling either picker or crop leaves it untouched.
struct MacImageImportControl: View {
    @Binding var data: Data
    var title = "更换图片"
    var cropTitle = "裁切图片"
    var label = ""
    var circularPreview = false
    var identifier = "importImage"
    @State private var input: MacImageAssets.CropInput?
    @State private var preparedData: Data?
    @State private var error: String?
    var body: some View {
        HStack(spacing: MacUI.space(8)) {
            Button(title) {
                do { input = try MacImageAssets.select(title: "选择图片", cropTitle: cropTitle, label: label, circularPreview: circularPreview) }
                catch { self.error = error.localizedDescription }
            }.accessibilityIdentifier(identifier)
            if !data.isEmpty { Button("移除") { data = Data() }.accessibilityIdentifier(identifier + "Remove") }
        }
        .sheet(item: $input, onDismiss: {
            input = nil
            if let preparedData { data = preparedData; self.preparedData = nil }
        }) { selected in MacImageCropView(input: selected) { preparedData = $0 } }
        .alert("无法导入图片", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
}
