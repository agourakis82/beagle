// url=https://www.figma.com/design/dgN7JrAPdQnvKzccdBrlW5/Beagle-Companion?node-id=6-14
// source=BeagleSuite/Sources/BeagleCore/Components.swift
// component=TruthBadge
//
// Os quatro nomes do Figma são os quatro casos de TruthMode (BeagleCore/Truth.swift).
// Se alguém acrescentar um caso lá, esta tabela precisa crescer junto — um valor
// não mapeado sai como `undefined` e o snippet quebra em silêncio.
import figma from 'figma'
const instance = figma.selectedInstance

const modo = instance.getEnum('Verdade', {
  'Observado': '.observed',
  'Lembrado': '.remembered',
  'Declarado': '.declared',
  'Obsoleto': '.stale',
})

export default {
  example: figma.code`TruthBadge(${modo})`,
  imports: ['import BeagleCore'],
  id: 'selo-de-verdade',
  metadata: { nestable: true },
}
