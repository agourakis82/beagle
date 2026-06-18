//
//  ToolDepthSlider.swift
//  BeagleCockpit
//
import SwiftUI
import BeagleCore

struct ToolDepthSlider: View {
    let labelMin: String
    let labelMax: String
    @Binding var value: Double   // 1.0 – 5.0, step 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(value: $value, in: 1...5, step: 1)
                .tint(BeagleTheme.truthObserved)
            HStack {
                Text(labelMin)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                Text(labelMax)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }
}
