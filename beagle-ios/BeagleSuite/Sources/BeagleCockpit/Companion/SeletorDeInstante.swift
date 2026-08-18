//
//  SeletorDeInstante.swift
//  BeagleCockpit — Companion chat
//
//  A hora exata, quando as âncoras rápidas não bastam ("acordei às 5h20").
//
//  O seletor NÃO oferece dias arbitrários. O teto é ontem, e a razão é a mesma que limita as
//  âncoras rápidas a algumas horas: a Fase 2 confronta o relato com a fisiologia numa janela de
//  ±60 min, e a memória do INSTANTE de um estado não sobrevive a dias. Oferecer uma semana atrás
//  convidaria a uma precisão que ninguém tem, e o pipeline aceitaria — a guarda do lado do
//  servidor recusa instante declarado a mais de 7 dias da fala, mas recusar depois é pior do que
//  não convidar antes.
//

import SwiftUI
import BeagleCore

struct SeletorDeInstante: View {
    @Binding var hora: Date
    var aoConfirmar: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Ontem, mesma hora. Ver a nota de topo sobre por que não é mais que isso.
    private var minimo: Date { Date().addingTimeInterval(-36 * 3600) }
    private var maximo: Date { Date() }

    var body: some View {
        NavigationStack {
            VStack(spacing: BeagleSpacing.md) {
                DatePicker(
                    "Quando o estado aconteceu",
                    selection: $hora,
                    in: minimo...maximo,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()

                Text("Isto grava o instante do ESTADO, não o da mensagem.")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.companionInk.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BeagleSpacing.md)

                Spacer()
            }
            .padding(.top, BeagleSpacing.md)
            .navigationTitle("Quando foi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Usar") {
                        aoConfirmar(hora)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
