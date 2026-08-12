// url=https://www.figma.com/design/dgN7JrAPdQnvKzccdBrlW5/Beagle-Companion?node-id=8-7
// source=BeagleSuite/Sources/BeagleCockpit/Companion/MessageBubble.swift
// component=MessageBubble
//
// MessageBubble recebe a mensagem inteira e decide sozinha o lado pelo papel dela.
// Por isso a variante do Figma vira o papel da mensagem de exemplo, não uma prop
// própria — inventar um parâmetro `quem:` produziria código que não compila.
import figma from 'figma'
const instance = figma.selectedInstance

const papel = instance.getEnum('Quem', {
  'Companion': '.assistant',
  'Você': '.user',
})

const texto = instance.findText('corpo', { traverseInstances: true })
const conteudo = texto && texto.type === 'TEXT' ? texto.textContent : ''

export default {
  example: figma.code`MessageBubble(
    message: ChatMessage(role: ${papel}, content: "${conteudo}"),
    isLast: false
)`,
  imports: ['import BeagleCore'],
  id: 'fala',
  metadata: { nestable: false },
}
