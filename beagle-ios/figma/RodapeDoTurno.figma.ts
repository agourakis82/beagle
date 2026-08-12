// url=https://www.figma.com/design/fS1TEG5cDGHs0uAHA953y7/Beagle-Mission-Control-—-Sovereign-Dark?node-id=11-23
// source=beagle-ios/BeagleSuite/Sources/BeagleCore/Fleet/SessionStore.swift
// component=SessionStore.rodapeDoTurno
//
// Duração · contexto · custo, ao pé de cada turno. É o único lugar que diz QUAL turno está caro —
// o chip da Frota mostra o total da lane, este mostra a parcela.

import figma from 'figma'
const instance = figma.selectedInstance

const caso = instance.getEnum('Caso', {
  'Completo': 'completo',
  'TurnoEmCurso': 'turnoEmCurso',
  'CustoZero': 'custoZero',
  'ContextoMinimo': 'contextoMinimo',
  'SemUso': 'semUso',
})

// `duracao(concluido:)` é nil ENQUANTO o turno corre — e é opcional DENTRO da linha, não portão
// da linha inteira. Ver o achado de review em SessionStore.swift:420.
const duracao = caso === 'turnoEmCurso' ? 'nil' : '12'

// `Turno.uso` é o ÚLTIMO `usage` COM custo do turno, nunca a soma: medido nas fixtures do censo
// ACP, `cost.amount` vem nulo em 15 dos 16 eventos, e um fechamento zerado não apaga o preço.
const uso = {
  completo: 'UsoDoTurno(contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0.3728)',
  turnoEmCurso: 'UsoDoTurno(contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0.3728)',
  custoZero: 'UsoDoTurno(contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0)',
  contextoMinimo: 'UsoDoTurno(contextoUsado: 4_000, contextoTeto: 1_000_000, usd: 0.0004)',
  semUso: 'nil',
}[caso]

const saida = {
  completo: '"12s · contexto 4% · US$ 0.3728"',
  turnoEmCurso: '"contexto 4% · US$ 0.3728"',
  custoZero: '"12s · contexto 4%"',
  contextoMinimo: '"12s · contexto < 1% · US$ 0.0004"',
  semUso: '"12s"',
}[caso]

export default {
  example: figma.code`// Caso=${caso}
SessionStore.rodapeDoTurno(
    duracao: ${duracao},
    uso: ${uso}
)
// → ${saida}

// As duas regras que este rodapé existe para tornar visíveis:
//   • custo zero NÃO entra (if u.usd > 0) — "US$ 0,0000" em todo turno treina o olho a ignorar
//     a linha, e aí o número que importa também deixa de ser lido;
//   • nada arredonda para zero — abaixo de 1% o texto é "contexto < 1%", nunca "contexto 0%".
//
// O teto vem do EVENTO, não de constante: 1.000.000 no Claude, 258.400 no Codex via ACP.
// Por isso a linha mostra proporção, e não número absoluto sozinho.`,
  imports: ['import BeagleCore'],
  id: 'rodape-do-turno',
  metadata: {
    nestable: true,
    props: {
      caso,
      fonte: 'BeagleCore/Fleet/SessionStore.swift:428 — rodapeDoTurno / :448 — contextoDoRodape',
      fonteDoDado: 'Turno.uso (SessionStore.swift:139) ← Kind::Usage do loomd',
    },
  },
}
