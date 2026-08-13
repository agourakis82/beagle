//
//  FaixaDeEstado.swift
//  BeagleCockpit
//
//  Tempo · corpo · céu. A faixa que se puxa do topo do chat.
//
//  Decidida no contrato de UI em julho e nunca construída até agora. Portada da
//  composição do Figma (arquivo dgN7JrAPdQnvKzccdBrlW5, página "Faixa de estado").
//
//  NÃO é um painel. São três leituras, na ordem em que importam num plantão:
//  quando é, como está o corpo, como está lá fora. Se virar dashboard, errou.
//
//  Duas regras do contrato que o código precisa honrar:
//
//  1. "Estado revelado por gesto" — em repouso existe só um puxador discreto. A
//     faixa não ocupa a tela de quem está lendo; ela responde a quem procura.
//
//  2. "Recepção discreta e VERDADEIRA" — o valor do corpo carrega a cor da sua
//     procedência. Medido agora → truthObserved. Medido faz tempo → truthStale,
//     apagado mas PRESENTE. Nunca medido → travessão, não um número inventado.
//     Um número sem origem não se mostra num plantão.
//

import SwiftUI
import BeagleCore

public struct FaixaDeEstado: View {

    private let breath: PresenceBreath
    private let sky: SkyBand?

    @State private var revelada = false
    @Environment(\.accessibilityReduceTransparency) private var reduzTransparencia

    public init(breath: PresenceBreath = .neutral, sky: SkyBand? = nil) {
        self.breath = breath
        self.sky = sky
    }

    // MARK: - As três leituras

    /// Quão fresca é a medida do corpo. O mesmo teto que o PresenceBreath usa para
    /// decidir se ainda vale como respiração medida.
    private var procedenciaDoCorpo: TruthMode? {
        guard breath.bpm != nil else { return nil }
        guard let quando = breath.observedAt else { return .declared }
        return Date().timeIntervalSince(quando) <= PresenceBreath.defaultMaxAge
            ? .observed : .stale
    }

    private var valorDoCorpo: String {
        guard let bpm = breath.bpm else { return "—" }
        return "\(Int(bpm.rounded())) bpm"
    }

    private var valorDoCeu: String {
        switch sky {
        case .calm:   return "calmo"
        case .active: return "ativo"
        case .storm:  return "tempestade"
        case nil:     return "—"
        }
    }

    private var corDoCorpo: Color {
        guard let modo = procedenciaDoCorpo else { return BeagleTheme.textTertiary }
        return BeagleTheme.color(for: modo)
    }

    private var corDoCeu: Color {
        // O céu vem de sensor remoto — é observado quando existe, e nada quando não.
        sky == nil ? BeagleTheme.textTertiary : BeagleTheme.textSecondary
    }

    // MARK: - Corpo

    public var body: some View {
        VStack(spacing: BeagleSpacing.xxs) {
            if revelada {
                conteudo
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            puxador
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: revelada)
        .contentShape(Rectangle())   // o toque tem que pegar no espaco todo, nao so no traco
        .onTapGesture { revelada.toggle() }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { g in
                    // Puxar para baixo revela; empurrar para cima recolhe.
                    if g.translation.height > 24 { revelada = true }
                    else if g.translation.height < -24 { revelada = false }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Estado")
        .accessibilityValue(revelada ? leituraFalada : "recolhido")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(revelada ? "Toque para recolher" : "Toque para ver tempo, corpo e céu")
    }

    private var leituraFalada: String {
        var partes = [agora]
        if breath.bpm != nil {
            let idade = procedenciaDoCorpo == .stale ? ", medida antiga" : ""
            partes.append(valorDoCorpo + idade)
        }
        if sky != nil { partes.append("céu \(valorDoCeu)") }
        return partes.joined(separator: ", ")
    }

    /// O relógio só corre enquanto a faixa está aberta — nada de acordar a tela a
    /// cada minuto para atualizar um número que ninguém está vendo.
    private var agora: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    private var conteudo: some View {
        TimelineView(.everyMinute) { _ in
            HStack(spacing: 0) {
                segmento("TEMPO", agora, BeagleTheme.textPrimary, .leading)
                fio
                segmento("CORPO", valorDoCorpo, corDoCorpo, .center)
                fio
                segmento("CÉU", valorDoCeu, corDoCeu, .trailing)
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.sm)
            .background(fundo)
            .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.lg, style: .continuous))
            .padding(.horizontal, BeagleSpacing.md)
        }
    }

    /// A faixa flutua SOBRE o histórico — é a camada onde vidro é legítimo. Sob
    /// Reduzir Transparência cai para material sólido, senão o número some no campo
    /// de brasa que corre atrás.
    @ViewBuilder
    private var fundo: some View {
        if reduzTransparencia {
            RoundedRectangle(cornerRadius: BeagleRadius.lg, style: .continuous)
                .fill(.regularMaterial)
        } else {
            RoundedRectangle(cornerRadius: BeagleRadius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.lg, style: .continuous)
                        .strokeBorder(BeagleTheme.hairline, lineWidth: 1)
                )
        }
    }

    private func segmento(_ rotulo: String,
                          _ valor: String,
                          _ cor: Color,
                          _ alinhamento: HorizontalAlignment) -> some View {
        VStack(alignment: alinhamento, spacing: 3) {
            Text(rotulo)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(BeagleTheme.textTertiary)
            Text(valor)
                .font(BeagleFont.data.font)
                .foregroundStyle(cor)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity,
               alignment: alinhamento == .leading ? .leading
                        : alinhamento == .trailing ? .trailing : .center)
    }

    private var fio: some View {
        Rectangle()
            .fill(BeagleTheme.hairline)
            .frame(width: 1, height: 26)
    }

    /// Em repouso, isto é a faixa inteira: um traço. "A faixa é porta", não painel.
    private var puxador: some View {
        Capsule()
            .fill(BeagleTheme.textTertiary.opacity(revelada ? 0.5 : 0.30))
            .frame(width: 34, height: 4)
            .padding(.vertical, BeagleSpacing.xs)
    }
}

#Preview("Faixa — corpo medido agora") {
    VStack {
        FaixaDeEstado(breath: .measured(bpm: 58, at: Date()), sky: .calm)
        Spacer()
    }
    .background(Color.black)
}

#Preview("Faixa — corpo obsoleto e céu mudo") {
    VStack {
        FaixaDeEstado(breath: .measured(bpm: 58, at: Date().addingTimeInterval(-7200)), sky: nil)
        Spacer()
    }
    .background(Color.black)
}
