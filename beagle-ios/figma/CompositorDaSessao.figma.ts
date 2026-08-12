// url=https://www.figma.com/design/fS1TEG5cDGHs0uAHA953y7/Beagle-Mission-Control-—-Sovereign-Dark?node-id=6-28
// source=beagle-ios/BeagleSuite/Sources/BeagleWorkbenchKit/Fleet/SessionView.swift
// component=SessionView
//
// ⚠️ NÃO PUBLICADO. Code Connect exige plano Organization/Enterprise; a conta é Pro, e tanto
//    `get_code_connect_suggestions` quanto `add_code_connect_map` responderam:
//    "You need a Dev or Full seat on an Organization or Enterprise plan to use Code Connect."
//    Este arquivo existe para que o mapeamento não se perca e possa ser revisado agora. No dia em
//    que o plano permitir, ele publica sem reescrita. Ver beagle-ios/figma/README.md.
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
