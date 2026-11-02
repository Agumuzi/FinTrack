import SwiftUI
import AppKit

struct MacImageCropView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    let input: MacImageAssets.CropInput
    let onSave: (Data) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = 1.0
    @State private var offset = CGPoint.zero
    @State private var dragStart = CGPoint.zero
    @State private var error: String?
    private let side: CGFloat = 280
    private var imageWidth: CGFloat { CGFloat(input.image.width) / CGFloat(min(input.image.width, input.image.height)) * side * zoom }
    private var imageHeight: CGFloat { CGFloat(input.image.height) / CGFloat(min(input.image.width, input.image.height)) * side * zoom }
    private func bounded(_ proposed: CGPoint) -> CGPoint {
        CGPoint(x: min((imageWidth - side) / 2, max(-(imageWidth - side) / 2, proposed.x)),
                y: min((imageHeight - side) / 2, max(-(imageHeight - side) / 2, proposed.y)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(18)) {
            Text(input.title).appFont(.dialogTitle, weight: .semibold)
            if !input.label.isEmpty { Text(input.label).appFont(.section, weight: .semibold) }
            Text(L10n.text("mac.imageCropView.body.c22cbdb466")).appFont(.body, weight: .regular).foregroundStyle(.secondary)
            HStack {
                Spacer()
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Image(decorative: input.image, scale: 1)
                        .resizable().frame(width: imageWidth, height: imageHeight)
                        .offset(x: offset.x, y: offset.y)
                }.frame(width: side, height: side).clipped()
                    .overlay { if input.circularPreview { Circle().strokeBorder(MacOverviewStyle.accent, lineWidth: 2) } else { Rectangle().strokeBorder(MacOverviewStyle.accent, lineWidth: 2) } }
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { value in
                        offset = bounded(CGPoint(x: dragStart.x + value.translation.width, y: dragStart.y + value.translation.height))
                    }.onEnded { _ in dragStart = offset })
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel(L10n.text("mac.imageCropView.body.7abecabb9d")).accessibilityIdentifier("imageCropPreview")
                Spacer()
            }
            HStack(spacing: MacUI.space(12)) {
                Image(systemName: "minus.magnifyingglass")
                Slider(value: $zoom, in: 1...4).accessibilityLabel(L10n.text("mac.imageCropView.body.37dc6e6be5")).accessibilityIdentifier("imageCropZoom")
                Image(systemName: "plus.magnifyingglass")
                Text("\(Int(zoom * 100))%").monospacedDigit().frame(width: MacUI.space(48))
            }
            HStack {
                Button(L10n.text("mac.imageCropView.body.0ca833d845")) { zoom = 1; offset = .zero; dragStart = .zero }.accessibilityIdentifier("imageCropReset")
                Spacer(); Text(L10n.text("mac.imageCropView.body.dcbe95b2bc")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            }
            Text(L10n.text("mac.imageCropView.body.191bf7f3dd")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).appFont(.caption, weight: .regular) }
            HStack {
                Spacer(); Button(L10n.text("mac.imageCropView.body.2cd0f3be87")) { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("imageCropCancel")
                Button(L10n.text("mac.imageCropView.body.850de13a01")) {
                    do {
                        let data = try MacImageAssets.croppedPNG(input.image, zoom: zoom, offset: CGPoint(x: offset.x / side, y: offset.y / side))
                        try onSave(data); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).accessibilityIdentifier("imageCropSave")
            }
        }.appPadding(24).appDialog(width: 500)
            .onChange(of: zoom) { _, _ in offset = bounded(offset); dragStart = offset }
    }
}
