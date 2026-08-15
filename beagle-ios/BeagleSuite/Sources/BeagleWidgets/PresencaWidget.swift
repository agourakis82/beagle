//
//  PresencaWidget.swift
//  BeagleWidgets — a tríade tempo · corpo · céu na tela de início
//
//  O PRIMEIRO widget do companion (os outros são de Mission Control, outra faixa).
//
//  Não faz rede. Lê o instantâneo que o app deixou no App Group e desenha. Por
//  isso ele funciona no plantão, fora do alcance do cluster — que é justamente
//  quando os outros ficam mudos.
//
//  A regra que rege tudo aqui: SEM NOTÍCIA NÃO É ZERO. Se não há instantâneo, ou
//  se o fato envelheceu, isso aparece. Um traço é honesto; um número inventado
//  não.
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
            ceu: Fato(valor: "calmo", observadoEm: .now),
            fluxo: Fato(valor: "FLOW"),
            capturasPendentes: 0
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (PresencaEntry) -> Void) {
        completion(PresencaEntry(date: .now, instantaneo: PresencaSnapshotStore()?.ler()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PresencaEntry>) -> Void) {
        let e = PresencaEntry(date: .now, instantaneo: PresencaSnapshotStore()?.ler())
        // A ATUALIZAÇÃO DE VERDADE vem do app chamando reloadAllTimelines quando
        // escreve. Esta política é só a rede de segurança para o caso de o app
        // não ser acordado por um bom tempo — e mesmo assim é barata, porque ler
        // um arquivo local não gasta o orçamento que uma requisição gastaria.
        completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct PresencaWidget: Widget {
    let kind = "PresencaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PresencaProvider()) { entry in
            PresencaWidgetView(entry: entry)
                .containerBackground(BeagleTheme.surface0, for: .widget)
        }
        .configurationDisplayName("Presença")
        .description("Tempo · corpo · céu — como ele te vê agora.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct PresencaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PresencaEntry

    var body: some View {
        if let s = entry.instantaneo {
            conteudo(s)
        } else {
            semNoticia
        }
    }

    /// A ausência tem a sua própria tela, e ela DIZ que é ausência. O
    /// ThoughtCaptureWidget devolvia `thoughtCount: 0` fixo — um zero que parece
    /// dado e não é. Aqui não.
    private var semNoticia: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("sem notícia")
                .font(.caption.weight(.medium))
                .foregroundStyle(BeagleTheme.textSecondary)
            Text("abra o app para eu saber de você")
                .font(.caption2)
                .foregroundStyle(BeagleTheme.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func conteudo(_ s: PresencaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            linha(rotulo: "corpo",
                  texto: s.corpo.valor.map { "\(Int($0)) bpm" },
                  modo: s.corpo.procedencia(agora: entry.date),
                  idade: s.corpo.observadoEm)
            linha(rotulo: "céu",
                  texto: s.ceu.valor,
                  modo: s.ceu.procedencia(agora: entry.date),
                  idade: s.ceu.observadoEm)
            if family != .systemSmall {
                linha(rotulo: "fluxo",
                      texto: s.fluxo.valor?.lowercased(),
                      modo: s.fluxo.procedencia(agora: entry.date),
                      idade: nil)
            }
            if s.capturasPendentes > 0 {
                Text("\(s.capturasPendentes) captura\(s.capturasPendentes == 1 ? "" : "s") esperando")
                    .font(.caption2)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Um fato por linha, com o símbolo de procedência que a Faixa de Estado já
    /// usa — mesmo vocabulário nas duas superfícies, para não haver duas gramáticas
    /// de verdade no mesmo aparelho.
    @ViewBuilder
    private func linha(rotulo: String, texto: String?, modo: TruthMode?, idade: Date?) -> some View {
        HStack(spacing: 6) {
            Text(rotulo)
                .font(.caption2)
                .foregroundStyle(BeagleTheme.textTertiary)
                .frame(width: 34, alignment: .leading)
            if let texto, let modo {
                Text(modo.displaySymbol)
                    .font(.caption2)
                    .foregroundStyle(cor(modo))
                Text(texto)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(modo == .stale ? BeagleTheme.textSecondary : BeagleTheme.companionInk)
                if modo == .stale, let idade {
                    Text(descricaoDaIdade(idade))
                        .font(.caption2)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            } else {
                Text("—")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    private func cor(_ m: TruthMode) -> Color {
        switch m {
        case .observed:   return BeagleTheme.truthObserved
        case .remembered: return BeagleTheme.truthRemembered
        case .declared:   return BeagleTheme.textTertiary
        case .stale:      return BeagleTheme.postureWarm
        }
    }

    /// "4h atrás" em vez de um horário: no plantão o que importa é a distância,
    /// não o relógio.
    private func descricaoDaIdade(_ quando: Date) -> String {
        let s = entry.date.timeIntervalSince(quando)
        if s < 3600 { return "\(max(1, Int(s / 60)))min atrás" }
        if s < 86_400 { return "\(Int(s / 3600))h atrás" }
        return "\(Int(s / 86_400))d atrás"
    }
}
