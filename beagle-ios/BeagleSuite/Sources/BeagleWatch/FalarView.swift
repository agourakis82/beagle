//
//  FalarView.swift
//  BeagleWatch — falar com ele sem tirar o telefone do bolso.
//
//  POR QUE NO RELÓGIO:
//
//  No telefone, o microfone do app disputa espaço com o microfone do TECLADO — e
//  perde. Ele tocava no do sistema, subia a Siri, e nada acontecia. Disputa que a
//  gente não vai ganhar, e nem devia tentar: o ditado da Apple é bom.
//
//  Aqui não há adversário. Não há teclado, não há glifo concorrente, e o relógio
//  já está no pulso dele durante o plantão. Levanta o braço, fala, lê. Num
//  corredor de hospital isso é mais discreto que sacar o telefone — e funciona
//  com as duas mãos ocupadas até o instante do toque.
//
//  E é DITADO DO SISTEMA de propósito: `TextField` no watchOS abre a folha de
//  entrada da Apple, com ditado offline e correção. Não reconstruí nada.
//
//  A TELA MOSTRA POUCO, e isso é desenho. Um relógio não é lugar de ler ensaio:
//  ele mostra a resposta dele e o suficiente para decidir se vale pegar o
//  telefone. A conversa inteira continua no companion.
//

import SwiftUI
import BeagleCore

@MainActor
struct FalarView: View {
    @State private var texto: String = ""
    @State private var resposta: String = ""
    @State private var pensando = false
    @State private var degradado = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if pensando {
                    esperando
                } else if !resposta.isEmpty {
                    respondido
                } else {
                    convite
                }

                // O campo É o botão. Tocar abre o ditado da Apple; não há
                // microfone nosso para competir com nada.
                TextField("falar", text: $texto)
                    .disabled(pensando)
                    .onSubmit { enviar() }
                    .accessibilityLabel("Falar com o Beagle")
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Beagle")
    }

    private var convite: some View {
        Text("Fala comigo.")
            .font(.system(.body, design: .serif))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private var esperando: some View {
        // Nunca uma tela vazia enquanto ele espera — a presença é o piso.
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("estou aqui")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var respondido: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(resposta)
                .font(.system(.body, design: .serif))
                .lineSpacing(2)
            if degradado {
                // Honestidade: ele merece saber que não foi a voz inteira.
                Text("resposta reduzida")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
    }

    private func enviar() {
        let dito = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dito.isEmpty, !pensando else { return }
        texto = ""
        resposta = ""
        degradado = false
        pensando = true
        Task {
            let r = await BeagleClient.shared.chat(prompt: dito)
            pensando = false
            let bruto = r.value?.response ?? ""
            // O MESMO PORTÃO do telefone. O relógio não passa pelo caminho do
            // cockpit em todo cenário, e esta é a última parada antes da tela —
            // string de erro não vira fala dele em lugar nenhum.
            if PisoLocal.ehFala(bruto) {
                resposta = bruto
                // "floor" é o chão do servidor: presença sem modelo por trás.
                // Ele merece saber que não foi a voz inteira.
                degradado = (r.value?.model == "floor" || r.value?.source == "floor")
            } else {
                resposta = PisoLocal.frase(PisoLocal.motivo(de: nil, temRede: true))
                degradado = true
            }
        }
    }
}
