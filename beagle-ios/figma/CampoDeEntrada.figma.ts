// url=https://www.figma.com/design/dgN7JrAPdQnvKzccdBrlW5/Beagle-Companion?node-id=9-11
// source=BeagleSuite/Sources/BeagleCockpit/Companion/ChatComposer.swift
// component=ChatComposer
//
// A variante Repouso/Escrevendo NÃO é uma prop: é o estado derivado de `text`
// estar vazio ou não. O snippet reflete isso em vez de inventar um parâmetro —
// foi exatamente confundir estado derivado com condição de guarda que deixou o
// microfone morto no app (o toque caía num `return` silencioso).
import figma from 'figma'
const instance = figma.selectedInstance

const rascunho = instance.getEnum('Estado', {
  'Repouso': '""',
  'Escrevendo': '"não durmo desde ontem"',
})

export default {
  example: figma.code`@State private var texto = ${rascunho}
@State private var profundidade: ChatDepth = .conversa

ChatComposer(
    text: $texto,
    depth: $profundidade,
    isStreaming: false
)`,
  imports: ['import BeagleCore'],
  id: 'campo-de-entrada',
  metadata: { nestable: false },
}
