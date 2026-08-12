//
//  EmberField.swift
//  BeagleCockpit
//
//  O campo de brasa em que o bicho vive — a metade ambiente da presença.
//
//  Portado da composição do Figma (arquivo dgN7JrAPdQnvKzccdBrlW5, página "Presença").
//  A paleta foi lida dos PRÓPRIOS pôsteres dos laços, não do BeagleTheme: a presença
//  corre mais quente que a marca. Fogo #FF6A33, brasa #FF9A5A, profundo #8C2A18.
//
//  Três decisões que vieram de medição, não de gosto:
//
//  1. As luzes compõem em .screen, não .normal. Luz soma; tinta cobre. Três radiais
//     sobrepostas em screen leem como UM campo com um núcleo quente, em vez de três
//     discos empilhados.
//
//  2. A base é #07070B, não preto puro. Preto puro em OLED desliga o pixel, e o campo
//     perde a profundidade — não sobra nada para o brilho cair dentro.
//
//  3. Tem grão. Gradiente escuro em painel OLED faz banda visível, e banda é o que faz
//     uma tela parecer barata às quatro da manhã. O ruído é desenhado UMA VEZ numa
//     camada rasterizada (.drawingGroup) — não redesenha por quadro.
//
//  Sobre bateria: anima a 12fps, não 60. Nada aqui precisa de suavidade — é respiração,
//  não transição. Isto roda plantões inteiros.
//

import SwiftUI
import BeagleCore

public struct EmberField: View {

    /// Ritmo declarado da respiração. `.neutral` → cadência de repouso.
    private let breath: PresenceBreath
    /// 0…1 — quanto o campo se faz presente. O chat o rebaixa; a tela vazia o abre.
    private let intensity: Double

    public init(breath: PresenceBreath = .neutral, intensity: Double = 1.0) {
        self.breath = breath
        self.intensity = max(0, min(1, intensity))
    }

    private static let fire  = Color(red: 1.00, green: 0.42, blue: 0.20)
    private static let ember = Color(red: 1.00, green: 0.60, blue: 0.35)
    private static let deep  = Color(red: 0.55, green: 0.16, blue: 0.09)
    private static let floor = Color(red: 0.027, green: 0.027, blue: 0.043)

    /// Onde fica o coração do bicho no quadro — toda luz é ancorada nele.
    private static let heart = UnitPoint(x: 0.52, y: 0.34)

    /// Respirações por segundo. Quando há pulso medido, seguimos um quarto dele —
    /// respiração é mais lenta que batimento. Sem medida, o período neutro do
    /// PresenceBreath (6s), que é o mesmo que a aurora usa.
    private var breathHz: Double {
        guard let bpm = breath.bpm else { return 1.0 / PresenceBreath.neutralPeriod }
        return max(0.10, min(0.40, bpm / 4.0 / 60.0))
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let wave = (sin(t * breathHz * 2 * .pi) + 1) / 2
            let swell = 0.88 + 0.12 * wave

            ZStack {
                EmberField.floor

                light(EmberField.fire,  radius: 0.62 * swell, opacity: 0.55)
                light(EmberField.ember, radius: 0.45,         opacity: 0.20,
                      at: UnitPoint(x: 0.20, y: 0.18))
                light(EmberField.deep,  radius: 0.88,         opacity: 0.32)

                // O núcleo: apertado, aceso, o ponto de onde a luz nasce.
                light(EmberField.fire, radius: 0.17 * swell,
                      opacity: 0.72 * (0.85 + 0.15 * wave))

                vignette
                grain
            }
            .compositingGroup()   // sem isto o .screen vaza sobre o que estiver atrás
            .opacity(intensity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func light(_ color: Color,
                       radius: Double,
                       opacity: Double,
                       at point: UnitPoint = EmberField.heart) -> some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height) * radius
            RadialGradient(
                stops: [
                    .init(color: color.opacity(opacity),        location: 0.00),
                    .init(color: color.opacity(opacity * 0.30), location: 0.45),
                    .init(color: color.opacity(0.0),            location: 1.00),
                ],
                center: point, startRadius: 0, endRadius: r
            )
        }
        .blendMode(.screen)
    }

    /// Fecha as bordas e empurra o olho ao coração. Queda longa — queda curta desenha
    /// um anel visível, que é pior do que não ter vinheta.
    private var vignette: some View {
        RadialGradient(
            stops: [
                .init(color: .clear,                    location: 0.00),
                .init(color: .clear,                    location: 0.50),
                .init(color: Color.black.opacity(0.72), location: 1.00),
            ],
            center: EmberField.heart, startRadius: 0, endRadius: 620
        )
        .blendMode(.multiply)
    }

    /// Desenhado uma vez e rasterizado. Mata a banda que gradiente escuro mostra em OLED.
    private var grain: some View {
        Canvas { ctx, size in
            // Semente fixa — a textura não pode cintilar entre quadros.
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return Double(seed % 10_000) / 10_000
            }
            let count = Int(size.width * size.height / 90)
            for _ in 0..<count {
                let x = next() * size.width
                let y = next() * size.height
                let a = 0.020 + next() * 0.045
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1.1, height: 1.1)),
                    with: .color(.white.opacity(a))
                )
            }
        }
        .drawingGroup()
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

#Preview("Campo de brasa") {
    EmberField(breath: .neutral)
        .frame(width: 393, height: 852)
        .background(Color.black)
}
