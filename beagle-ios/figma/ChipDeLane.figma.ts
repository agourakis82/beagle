// url=https://www.figma.com/design/fS1TEG5cDGHs0uAHA953y7/Beagle-Mission-Control-—-Sovereign-Dark?node-id=10-44
// source=beagle-ios/BeagleSuite/Sources/BeagleWorkbenchKit/Fleet/FrotaView.swift
// component=LaneCard
//
// O card da Frota. Diz três coisas ao mesmo tempo: quem é a lane, em que estado está, e DE ONDE
// esse veredito veio. O custo entra ao lado do estado — a mesma fonte que o rodapé da Sessão lê.

import figma from 'figma'
const instance = figma.selectedInstance

// Exaustivo de propósito: um valor não mapeado devolveria `undefined` em silêncio.
const caso = instance.getEnum('Caso', {
  'SemCusto': 'semCusto',
  'AbaixoDeUmCentavo': 'abaixoDeUmCentavo',
  'ComCusto': 'comCusto',
  'LidoDaTela': 'lidoDaTela',
  'Ausente': 'ausente',
})

// O `usd` que cada caso representa. O loomd soma por TURNO (último `usage` COM custo, nunca a
// soma) e OMITE a chave quando é zero — então ausência de chave é zero, não "desconhecido".
const usd = {
  semCusto: '0',
  abaixoDeUmCentavo: '0.0042',
  comCusto: '12.3456',
  lidoDaTela: '0',
  ausente: '0',
}[caso]

// Procedência: `exact` veio de protocolo tipado (loomd); `inferred` veio de `capture-pane` + regex.
const confianca = (caso === 'lidoDaTela' || caso === 'ausente') ? '.inferred' : '.exact'

const state = {
  semCusto: '.running',
  abaixoDeUmCentavo: '.running',
  comCusto: '.idle',
  lidoDaTela: '.waiting',
  ausente: '.exited',
}[caso]

export default {
  example: figma.code`// Caso=${caso}
LaneCard(
    lane: LaneSnapshot(
        sid: "claude-4",
        state: ${state},
        confidence: ${confianca},
        usd: ${usd}          // do /v2/state; chave OMITIDA quando zero
    ),
    // … callbacks de ação
)

// O que o card deriva, tudo assertável sem SwiftUI:
//   lane.presenceLabel                          // LaneState.label, ou "ausente" se isAbsent
//   lane.confidenceLabel                        // "medido no protocolo" | "lido da tela"
//   SessionStore.custoDoChip(${usd})            // nil | "< US$ 0,01" | "US$ %.2f"
//   SessionStore.custoParaAcessibilidade(${usd}) // o trecho que VoiceOver precisa ouvir

// 🚨 custoDoChip NÃO usa o %.4f do rodapé, de propósito: o rodapé mede UM turno (a quarta casa
//    É o dado); o chip mede o acumulado da lane. A coerência é de PRINCÍPIO — zero não aparece,
//    nada arredonda para zero — não de string de formato.
// ⚠️ DÍVIDA: o chip não herda isStale/confidence. Transporte caído congela o número sem sinal.`,
  imports: ['import BeagleCore', 'import BeagleWorkbenchKit'],
  id: 'chip-de-lane',
  metadata: {
    nestable: true,
    props: {
      caso,
      fonteDoCusto: 'BeagleCore/Fleet/SessionStore.swift:476 — custoDoChip',
      fonteDosRotulos: 'BeagleCore/Fleet/LaneState.swift:198 — presenceLabel / confidenceLabel',
      fonteDoDesenho: 'BeagleWorkbenchKit/Fleet/FrotaView.swift — LaneCard.header',
    },
  },
}
