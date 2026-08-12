// url=https://www.figma.com/design/fS1TEG5cDGHs0uAHA953y7/Beagle-Mission-Control-—-Sovereign-Dark?node-id=6-28
// source=beagle-ios/BeagleSuite/Sources/BeagleWorkbenchKit/Fleet/SessionView.swift
// component=SessionView
//
// ✅ BIBLIOTECA PUBLICADA em 12-ago-2026 (o pré-requisito de publicação do Code Connect está
//    cumprido — confirmado por `search_design_system`, que só devolve o que está publicado):
//      library : Beagle Mission Control — Sovereign Dark
//      libKey  : lk-94e81045d9910ce0cfa35536cef023f96b92c3cb5a942173655e31b1af31dad5d58238b72595b4488a0c4fc808afabd41db4b886209fbc80494d80e01257af33
//      compKey : 190a94d7e57f9c21ab47ea59e687b5593ec03e17   (component_set "Compositor da Sessão")
//      varSet  : 3585feff430e0c4534032cf8636ac87a2d9951f6   (coleção "Cor")
//
// ⚠️ AINDA NÃO LIGADO. O que falta é SÓ o plano: Code Connect exige Organization/Enterprise, e a
//    conta é Pro (assento Full). TRÊS endpoints medidos batem no mesmo gate —
//    `get_code_connect_suggestions`, `add_code_connect_map` e
//    `list_file_components_for_code_connect` — e o último nem chega a olhar a publicação, porque o
//    plano barra antes. Com o upgrade, este arquivo publica sem reescrita.
//    Ver beagle-ios/figma/README.md.
//
// A tese que este componente carrega: a tela não oferece um gesto que o servidor não aceita, e o
// rótulo diz a verdade ANTES do clique. Mentir no momento da decisão é pior que contar depois,
// porque o operador já agiu.

import figma from 'figma'
const instance = figma.selectedInstance

// A ÚNICA variante do conjunto. Os cinco valores são exaustivos de propósito: um valor não mapeado
// devolveria `undefined` em silêncio, que é a classe de defeito que esta fatia existe para matar.
const estado = instance.getEnum('Estado', {
  'Redireciona': 'redireciona',
  'Enfileira': 'enfileira',
  'SomenteLeitura': 'somenteLeitura',
  'CapacidadeDesconhecida': 'capacidadeDesconhecida',
  'LinkCaido': 'linkCaido',
})

// `aceita` é o dado REAL que dirige a tela — declarado pelo loomd em /v2/state e decodificado em
// LaneSnapshot.aceita. Capacidade NUNCA se deduz do nome da lane: `claude-1` (tail, leitura) e
// `claude-4` (ACP, dirigível) têm o mesmo prefixo e comportamentos opostos.
const aceitaSwift = {
  redireciona: '.redireciona',
  enfileira: '.enfileira',
  somenteLeitura: '.somenteLeitura',
  capacidadeDesconhecida: 'nil',
  linkCaido: 'nil',
}[estado]

// Os dois estados sem caixa diferem só na EXPLICAÇÃO, e a diferença é a tese:
//   .somenteLeitura → o servidor DECLAROU que é de leitura   (afirmação sobre a lane)
//   nil             → ainda não sei                          (nada se afirma sobre a lane)
// Com link caído, o texto vem de FleetStateClient.explicacaoDoLink, verbatim — nunca um segundo
// vocabulário para a mesma condição.
const linkSwift = estado === 'linkCaido'
  ? '.insistindo(motivo: "timeout", tentativas: 3)'
  : '.live'

export default {
  example: figma.code`
    // Estado=${estado}
    //
    // A Sessão NÃO descobre capacidade: ela recebe. Quem sabe é o servidor.
    SessionView(
      store: SessionStore(lane: "claude-4"),
      roster: fleet.loomdRoster,
      aceita: ${aceitaSwift},          // LaneSnapshot.aceita — do /v2/state, nunca do sid
      linkDaFrota: ${linkSwift}        // distingue "não sei" de "a fonte caiu"
    )

    // O que a tela deriva disso, tudo por função PURA e assertável sem UI:
    //   SessionStore.rotuloDeGuiar(${aceitaSwift})                    // rótulo do gesto, nil = não oferecer
    //   SessionStore.dicaDaCaixa(${aceitaSwift})                      // nil = a caixa NÃO EXISTE
    //   SessionStore.semCaixa(${aceitaSwift})                         // qual explicação entra no lugar
    //   SessionStore.razaoSemCapacidadeDeclarada(link: ${linkSwift})  // transitório vs. fonte caída
  `,
  imports: [
    'import BeagleCore',
    'import BeagleWorkbenchKit',
  ],
  id: 'compositor-da-sessao',
  metadata: {
    nestable: false,
    props: {
      estado,
      // Onde cada decisão mora, para quem for do Figma ao código sem adivinhar.
      fonteDaDecisao: 'BeagleCore/Fleet/SessionStore.swift:340,349,369,401',
      fonteDoDesenho: 'BeagleWorkbenchKit/Fleet/SessionView.swift',
      fonteDoDado: 'crates/loomd/src/trama.rs — aceita_da_lane() → /v2/state',
    },
  },
}
