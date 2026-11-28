#if os(macOS)
import SwiftUI

// O ÍCONE, desenhado em código.
//
// Por que em código e não num arquivo binário: um ícone em PNG é opaco ao repo — ninguém sabe por
// que ele é assim, ninguém consegue mudar uma cor sem abrir um editor, e ele apodrece. Este
// desenho é rasterizado pelo mesmo `ImageRenderer` que já retrata a Frota e a Sessão, então o
// ícone é revisável pelo mesmo caminho que as telas.
//
// O MOTIVO é o tear (loom), que é o nome do supervisor: fios de urdume verticais, e UM deles
// aceso. É o que o app faz — onze fios correndo, e a sua atenção em um. Não é uma engrenagem nem
// um foguete; é a coisa específica que esta ferramenta é.
//
// Regras que o desenho segue, e que valem para ícone de macOS:
//   - forma dentro de uma margem generosa: o sistema recorta e arredonda por fora;
//   - contraste que sobrevive a 16pt, onde ele vive de verdade (Dock, ⌘Tab, barra de título);
//   - UMA cor de destaque, o âmbar da casa, e nada mais competindo por atenção.
struct AppIconArt: View {
    /// 🚨 MEDIDO no contato-folha: a 16 e 24pt os ONZE fios viram um borrão listrado — a trama
    /// deixa de ler como tecido e passa a ler como código de barras sujo. Um `.icns` tem arte POR
    /// TAMANHO justamente para isso, e é o que os ícones do sistema fazem: o pequeno é um desenho
    /// mais simples, não o grande reduzido.
    ///
    /// `pequeno` corta para 5 fios com traço mais grosso. O que sobrevive é o que importa: a cruz
    /// âmbar e o nó. Aumentar o número de fios abaixo de 32pt é gastar pixel em ruído.
    var pequeno = false

    private var fios: Int { pequeno ? 5 : 11 }
    /// Qual está aceso — sempre o do meio, porque o centro é onde o olho cai a 16pt.
    private var aceso: Int { fios / 2 }

    private static let fundoAlto = Color(red: 0.075, green: 0.090, blue: 0.135)
    private static let fundoBaixo = Color(red: 0.031, green: 0.039, blue: 0.063)
    private static let ambar = Color(red: 1.00, green: 0.76, blue: 0.34)
    private static let fio = Color(white: 1.0, opacity: 0.20)

    var body: some View {
        GeometryReader { geo in
            let lado = min(geo.size.width, geo.size.height)
            // Margem de 16%: o macOS arredonda e sombreia por fora, e desenho colado na borda
            // fica cortado no Dock.
            let margem = lado * 0.16
            let area = lado - margem * 2
            let passo = area / CGFloat(fios - 1)
            // Traço mais grosso no pequeno: com 5 fios sobra espaço, e traço fino de 1px
            // desaparece na escala do Dock.
            let espessura = max(1, lado * (pequeno ? 0.055 : 0.022))

            ZStack {
                LinearGradient(colors: [Self.fundoAlto, Self.fundoBaixo],
                               startPoint: .top, endPoint: .bottom)

                // Os fios de urdume. Alturas ligeiramente diferentes: um tear tem tensão
                // desigual, e a irregularidade é o que faz ler como tecido em vez de código de
                // barras. Determinística — nada de random, que mudaria o ícone a cada build.
                ForEach(0..<fios, id: \.self) { i in
                    let x = margem + CGFloat(i) * passo
                    let sobra = pequeno ? area * 0.08 : area * (0.06 + 0.05 * abs(sin(Double(i) * 1.7)))
                    let éOAceso = i == aceso
                    RoundedRectangle(cornerRadius: espessura / 2)
                        .fill(éOAceso ? Self.ambar : Self.fio)
                        .frame(width: espessura, height: area - sobra)
                        .position(x: x, y: lado / 2)
                        .shadow(color: éOAceso ? Self.ambar.opacity(0.55) : .clear,
                                radius: lado * 0.045)
                }

                // A trama: o fio horizontal que atravessa todos. É o que transforma fios
                // paralelos em TECIDO — e é literalmente o nome do diário do supervisor.
                RoundedRectangle(cornerRadius: espessura / 2)
                    .fill(Color(white: 1.0, opacity: 0.38))
                    .frame(width: area, height: espessura * 0.85)
                    .position(x: lado / 2, y: lado / 2 + area * 0.055)

                // O nó no fio aceso: onde a atenção está. Um ponto, não um símbolo — a 16pt
                // qualquer glifo aqui vira sujeira.
                Circle()
                    .fill(Self.ambar)
                    .frame(width: espessura * 2.4, height: espessura * 2.4)
                    .shadow(color: Self.ambar.opacity(0.8), radius: lado * 0.05)
                    .position(x: margem + CGFloat(aceso) * passo, y: lado / 2 + area * 0.055)
            }
            .frame(width: lado, height: lado)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
#endif
