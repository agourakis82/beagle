//
//  PresencaWidget.swift
//  BeagleWidgets — a superfície de AÇÃO do companion
//
//  DESENHADO NO FIGMA ANTES DE CODAR (arquivo dgN7JrAPdQnvKzccdBrlW5, página
//  "Widget"). Os números aqui são os do desenho, não aproximações de memória.
//
//  DUAS VERSÕES ANTERIORES ESTAVAM ERRADAS, e vale dizer por quê:
//   1. Um MOSTRADOR de três linhas. Widget que só informa não é presença, é
//      enfeite. O que serve no plantão é chegar ao gesto.
//   2. Dois blocos chapados ocupando tudo. Cobriam a brasa — sobrava o retângulo
//      laranja. A beleza aqui É a brasa; o que a tampa destrói o widget.
//
//  A composição final: a luz nasce ATRÁS DA PALAVRA — de onde a voz sai. Tocar em
//  qualquer lugar fala. O segundo gesto é vidro, no escuro: secundário por
//  composição, não por tamanho de fonte.
//
//  LIMITE DO iOS, sem rodeio: widget não grava áudio e não aceita texto. O melhor
//  possível é abrir o app JÁ NO GESTO. É o que beagle://falar e beagle://capturar
//  fazem — e ambos os destinos passaram a existir junto com este arquivo.
//

import WidgetKit
import SwiftUI
import BeagleCore

struct PresencaEntry: TimelineEntry {
    let date: Date
    let instantaneo: PresencaSnapshot?
}

struct PresencaProvider: TimelineProvider {
    func placeholder(in context: Context) -> PresencaEntry {
        PresencaEntry(date: .now, instantaneo: PresencaSnapshot(
            geradoEm: .now,
            corpo: Fato(valor: 58, observadoEm: .now),
            ceu: Fato(valor: "calmo", observadoEm: .now)
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (PresencaEntry) -> Void) {
        completion(PresencaEntry(date: .now, instantaneo: PresencaSnapshotStore()?.ler()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PresencaEntry>) -> Void) {
        let e = PresencaEntry(date: .now, instantaneo: PresencaSnapshotStore()?.ler())
        // A atualização de verdade vem do app chamando reloadAllTimelines quando
        // escreve o instantâneo. Isto é só a rede de segurança — e é barata,
        // porque ler arquivo local não gasta o orçamento que rede gastaria.
        completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct PresencaWidget: Widget {
    let kind = "PresencaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PresencaProvider()) { entry in
            PresencaWidgetView(entry: entry)
                .containerBackground(PresencaWidgetView.base, for: .widget)
        }
        .configurationDisplayName("Falar com o Beagle")
        .description("Falar ou capturar, direto — sem abrir e procurar.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - A brasa

/// As três camadas de luz do desenho, na mesma ordem do `EmberField` do app.
///
/// `.screen` e não `.normal`: luz SOMA, tinta cobre. Três radiais sobrepostas em
/// screen leem como UM campo com um núcleo quente; em normal viram três discos
/// empilhados — foi exatamente o que fez a primeira versão parecer pobre.
///
/// `compositingGroup()` é obrigatório: sem ele o `.screen` vaza para o que está
/// atrás do widget.
private struct Brasa: View {
    /// Centro em coordenadas do quadro (0…1). No desenho fica atrás da palavra.
    let centro: UnitPoint

    var body: some View {
        GeometryReader { g in
            let lado = max(g.size.width, g.size.height)
            ZStack {
                camada(cor: Color(red: 1.00, green: 0.45, blue: 0.22), opacidade: 0.92,
                       meio: 0.30, centro: centro, raio: 0.588 * lado)
                camada(cor: Color(red: 1.00, green: 0.62, blue: 0.38), opacidade: 0.26,
                       meio: nil,
                       centro: UnitPoint(x: centro.x, y: centro.y - 0.10),
                       raio: 0.263 * lado)
                camada(cor: Color(red: 0.62, green: 0.20, blue: 0.10), opacidade: 0.50,
                       meio: nil,
                       centro: UnitPoint(x: centro.x, y: centro.y + 0.22),
                       raio: 0.417 * lado)
            }
            .compositingGroup()
        }
    }

    private func camada(cor: Color, opacidade: Double, meio: Double?,
                        centro: UnitPoint, raio: CGFloat) -> some View {
        var paradas: [Gradient.Stop] = [.init(color: cor.opacity(opacidade), location: 0)]
        if let meio {
            paradas.append(.init(color: Color(red: 0.80, green: 0.24, blue: 0.10).opacity(meio),
                                 location: 0.45))
        }
        paradas.append(.init(color: .clear, location: 1))
        return RadialGradient(gradient: Gradient(stops: paradas),
                              center: centro, startRadius: 0, endRadius: raio)
            .blendMode(.screen)
    }
}

// MARK: - Vista

struct PresencaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PresencaEntry

    /// A MESMA base da tela de Presença. Um widget com outro preto pareceria de
    /// outro app.
    static let base = Color(red: 7/255, green: 6/255, blue: 8/255)
    private static let tinta = Color(red: 1.0, green: 0.97, blue: 0.94)

    private static let falarURL = URL(string: "beagle://falar")!
    private static let capturarURL = URL(string: "beagle://capturar")!

    var body: some View {
        switch family {
        case .accessoryCircular:    circular
        case .accessoryRectangular: retangular
        case .systemMedium:         medio
        default:                    pequeno
        }
    }

    // MARK: Tela de início

    /// O widget INTEIRO é o gesto de falar — por isso o Link envolve tudo e não
    /// existe bloco de botão. O `+` flutua por cima como segundo destino.
    private var pequeno: some View {
        ZStack(alignment: .topTrailing) {
            Link(destination: Self.falarURL) {
                ZStack(alignment: .bottomLeading) {
                    Brasa(centro: UnitPoint(x: 0.34, y: 0.66))
                    palavra("falar", tamanho: 26)
                        .padding(.leading, 16)
                        .padding(.bottom, 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            Link(destination: Self.capturarURL) { vidroRedondo }
                .padding([.top, .trailing], 16)
        }
    }

    private var medio: some View {
        ZStack(alignment: .trailing) {
            Link(destination: Self.falarURL) {
                ZStack(alignment: .bottomLeading) {
                    Brasa(centro: UnitPoint(x: 0.20, y: 0.64))
                    palavra("falar", tamanho: 30)
                        .padding(.leading, 22)
                        .padding(.bottom, 22)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            Link(destination: Self.capturarURL) { vidroPilula }
                .padding(.trailing, 22)
        }
    }

    /// A palavra com o rodapé de estado. O estado é 10pt a 40%: existe para você
    /// decidir se vale falar agora, não para ser lido como dado clínico — a Tela
    /// de Dados é quem tem essa responsabilidade.
    private func palavra(_ txt: String, tamanho: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(txt)
                .font(.system(size: tamanho, weight: .semibold))
                .kerning(-0.6)
                .foregroundStyle(Self.tinta.opacity(0.96))
            if let r = resumo() {
                Text(r)
                    .font(.system(size: 10))
                    .foregroundStyle(Self.tinta.opacity(0.40))
                    .lineLimit(1)
            }
        }
    }

    private var vidroRedondo: some View {
        Image(systemName: "plus")
            .font(.system(size: 15))
            .foregroundStyle(Self.tinta.opacity(0.70))
            .frame(width: 34, height: 34)
            .background(Circle().fill(.white.opacity(0.07)))
            .overlay(Circle().strokeBorder(Self.tinta.opacity(0.13), lineWidth: 1))
            .contentShape(Circle())
    }

    private var vidroPilula: some View {
        Text("capturar")
            .font(.system(size: 14))
            .foregroundStyle(Self.tinta.opacity(0.80))
            .frame(width: 116, height: 44)
            .background(Capsule().fill(.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(Self.tinta.opacity(0.13), lineWidth: 1))
            .contentShape(Capsule())
    }

    // MARK: Tela bloqueada

    /// SEM BRASA, de propósito: acessório de tela bloqueada é renderizado
    /// monocromático pelo iOS — cor não sobrevive ali, e insistir seria desenhar
    /// algo que o aparelho não mostra.
    private var retangular: some View {
        Link(destination: Self.falarURL) {
            VStack(alignment: .leading, spacing: 2) {
                Text("falar com o Beagle")
                    .font(.system(size: 15, weight: .semibold))
                if let r = resumo() {
                    Text(r).font(.system(size: 11)).opacity(0.6).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var circular: some View {
        Link(destination: Self.falarURL) {
            Image(systemName: "mic.fill").font(.title3)
        }
    }

    // MARK: Estado

    /// Sem instantâneo devolve nil e a linha SOME — não inventa "0 bpm" nem ocupa
    /// espaço com uma ausência. O ThoughtCaptureWidget devolvia thoughtCount: 0
    /// FIXO, um zero com cara de dado; aqui não.
    private func resumo() -> String? {
        guard let s = entry.instantaneo else { return nil }
        var partes: [String] = []
        if let bpm = s.corpo.valor, let m = s.corpo.procedencia(agora: entry.date) {
            partes.append(m == .stale ? "corpo há \(idade(s.corpo.observadoEm))" : "\(Int(bpm)) bpm")
        }
        if let ceu = s.ceu.valor { partes.append(ceu) }
        if s.capturasPendentes > 0 { partes.append("\(s.capturasPendentes) na fila") }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }

    private func idade(_ quando: Date?) -> String {
        guard let quando else { return "?" }
        let s = entry.date.timeIntervalSince(quando)
        if s < 3600 { return "\(max(1, Int(s / 60)))min" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}
