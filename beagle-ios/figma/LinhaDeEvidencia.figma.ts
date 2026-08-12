// url=https://www.figma.com/design/fS1TEG5cDGHs0uAHA953y7/Beagle-Mission-Control-—-Sovereign-Dark?node-id=26-8
// source=beagle-ios/BeagleSuite/Sources/BeagleWorkbenchKit/Fleet/FrotaView.swift
// component=LaneCard.evidence
//
// A linha de evidência do card da Frota: a única coisa que a lane realmente DISSE.
// O registro não é enfeite — diz que tipo de coisa está no slot, e cada tipo tem uma voz.

import figma from 'figma'
const instance = figma.selectedInstance

const registro = instance.getEnum('Registro', {
  'Titulo': 'titulo',
  'Fala': 'fala',
  'Leitura': 'leitura',
})

// De onde CADA registro nasce. Isto é o que torna a escolha verificável em vez de estética:
// o registro segue a ORIGEM do texto, não o estado da lane.
const origem = {
  titulo: 'Kind::SessionStarted — `ai-title` do transcript do Claude Code (chave `aiTitle`)',
  fala: 'Kind::AgentMessage — o agente falando, via ACP ou transcript',
  leitura: 'LanePoller (Node) — `capture-pane` + regex, confidence `.inferred`',
}[registro]

// 🚨 O tratamento que o app faz HOJE, e que este componente existe para corrigir.
const hoje = {
  titulo: '.monospaced, 60% — indistinguível de leitura de máquina',
  fala: '.monospaced, 60%, 1 linha — a fala do agente vestida de dado',
  leitura: '.monospaced, 60% — este é o único caso em que o app já acerta',
}[registro]

const proposto = {
  titulo: '.system(.subheadline) — face de UI, 1 linha. É um NOME, não uma frase.',
  fala: '.system(.subheadline, design: .serif) — até 3 linhas. É algo DITO.',
  leitura: '.system(size: 11, design: .monospaced), terciário, 1 linha, truncada.',
}[registro]

export default {
  example: figma.code`// Registro=${registro}
// origem:   ${origem}
// hoje:     ${hoje}
// proposto: ${proposto}

// A condição atual em FrotaView.swift — LaneCard.evidence:
//
//   .font(.system(.subheadline, design: lane.state == .waiting ? .serif : .monospaced))
//
// O comentário logo acima dela já declara a intenção certa: "Serif, because it is something
// being SAID to the operator, not a machine reading." A condição só honra isso quando a lane
// ESPERA — em todo outro estado a fala sai monoespaçada, e neste sistema monoespaçada é
// reservada a DADO (número, medida, identificador).
//
// O conserto é trocar o eixo da decisão: de ESTADO DA LANE para ORIGEM DO TEXTO.
//
// ⚠️ Este componente é ESPECIFICAÇÃO, não retrato. Enquanto o Swift não mudar, o Figma mostra
//    o destino e o app mostra o presente — e é por isso que este bloco diz os dois.`,
  imports: ['import BeagleCore', 'import BeagleWorkbenchKit'],
  id: 'linha-de-evidencia',
  metadata: {
    nestable: true,
    props: {
      registro,
      fonteDoDesenho: 'BeagleWorkbenchKit/Fleet/FrotaView.swift — LaneCard.evidence',
      fonteDoDado: 'loomd event.rs::from_transcript_line / from_acp_update → LaneSnapshot.detail',
      substituicaoDeFonte:
        'New York (.serif do sistema) NAO existe neste Figma; a rampa de fala usa IBM Plex Serif. ' +
        'Mesma politica declarada do SF Mono → JetBrains Mono.',
    },
  },
}
