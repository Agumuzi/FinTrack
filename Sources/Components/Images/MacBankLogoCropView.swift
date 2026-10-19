import SwiftUI

/// Keeps existing bank entry points while sharing the same crop UI and image rules.
struct MacBankLogoCropView: View {
    let input: MacBankLogos.CropInput
    let onSaved: () -> Void
    var body: some View {
        MacImageCropView(input: .init(title: "裁切银行图标", label: input.bank, image: input.image)) { data in
            try MacBankLogos.save(data, bank: input.bank)
            onSaved()
        }
    }
}
