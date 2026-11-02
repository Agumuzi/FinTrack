import SwiftUI

/// Keeps existing bank entry points while sharing the same crop UI and image rules.
struct MacBankLogoCropView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    let input: MacBankLogos.CropInput
    let onSaved: () -> Void
    var body: some View {
        MacImageCropView(input: .init(title: L10n.text("mac.bankLogoCropView.MacImageCropView.b032aad2cc"), label: input.bank, image: input.image)) { data in
            try MacBankLogos.save(data, bank: input.bank)
            onSaved()
        }
    }
}
