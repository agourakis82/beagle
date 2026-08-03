# Presença do Companion — desenho

**Data:** 2026-08-02
**Estado:** desenho validado visualmente, aguardando revisão escrita
**Origem:** "a interface de chat não está gostosa… visualmente e para uso"

---

## O problema, dito com precisão

A queixa não era de layout. Era de **ausência**.

No mesmo dia descobrimos que o companion vinha respondendo do **chão** — a mensagem de presença enlatada — porque o LiteLLM não conhecia nenhum modelo Claude, e que o recall estava morto porque o reranker estava escalado a zero. Consertado isso, sobrou a queixa real: a tela onde ele vive não parece alguém.

Três coisas que o app **já tem** e a conversa ignorava:

1. Ele tem **corpo** (um asset 3D que nunca aparece no chat).
2. Ele tem **voz** (captura por voz existe, mas não é entrada primária).
3. Ele tem **síntese própria** — capaz de falar do material dele sem confabular — e mesmo assim sempre espera.

E uma incoerência de registro: a voz dele é par elevado, rigoroso, simbólico; o rosto era uma pelúcia. O corpo contradizia a voz.

---

## O que fica decidido

### 1. A presença: o ancestral de luz

Um canino **primordial** feito de brasa, partículas e luz interna sobre quase-preto quente. Mais antigo e mais selvagem que um cão moderno, com a face mansa.

**Por que ancestral:** um exocórtex *é* linhagem — o que veio antes do seu pensamento e chega até agora. E toda a infraestrutura já se chama `darwin-*`. A forma passa a dizer o que a coisa é, em vez de decorar.

Darwin em pessoa foi considerado e **fica de fora da conversa**: um rosto humano num companion que fala em primeira pessoa arrisca soar como "eu sou o Darwin". Reservado para abertura e ícone, onde ele não fala.

### 2. Arquitetura da animação: vídeo para o gesto, shader para o estado

Nenhum dos dois sozinho resolve.

| Camada | Dá | Vem de |
|---|---|---|
| **Vídeo** (laço curto) | respirar, virar a cabeça, escutar — gesto que não se escreve em código | biblioteca de laços, todos derivados da MESMA imagem-fonte |
| **Shader** por cima | pulso, calor, agitação — o que muda a cada segundo | dado ao vivo: batimento, céu, hora |

Identidade preservada porque **todo laço nasce da mesma imagem** via `image_url` (data URI) no `grok-imagine-video-1.5`. Estados gerados soltos produziriam bichos parecidos, não o mesmo bicho.

### 3. O vocabulário de laços (19, catalogado em `catalogo.json`)

| Grupo | Laços | Quem dispara |
|---|---|---|
| **Base** | adormecido, atento, ouvindo, pensando | estado do app |
| **Transição** | despertar, reconhecendo, adormecendo | entrada/saída (tocam uma vez, voltam ao base) |
| **Emoção** | acolhendo, celebrando, preocupado, em silêncio, firme | teor do que **você escreveu** |
| **Trabalho** | buscando na memória, sintetizando, escuta longa | `/query`, `/synthesize`, modo voz |
| **Céu e corpo** | tempestade, madrugada, manhã | Hp30, hora, Physiome |
| **Especial** | o olhar | faixa de 28px |

Transições sempre **cruzadas (fade)**, nunca corte — corte quebra a ilusão de ser um bicho só.

### 4. O corpo da conversa: a carta

- **Fala dele**: serifa, entrelinha de leitura (~1.55), marca âmbar curta no início do turno como assinatura — não moldura de altura inteira.
- **Fala sua**: itálico apagado, sem bolha. Você sabe o que escreveu; a tela serve à voz dele.
- **Faixa do topo**: o `## Agora` destilado em três palavras ("noite · 21h · calmo") mais a presença. Corpo e céu completos ficam na Tela de Dados.

Bolhas simétricas foram descartadas: as duas falas não são a mesma coisa. A sua é telegráfica, a dele é parágrafo — tratar as duas como bolha com contorno fazia a fala dele ler como SMS.

### 5. O tempo: presença antes da palavra, pensamento em frases

O maior desconforto medido não era visual: **~21s de tela morta** entre enviar e receber.

- Em ~1s: sinal de presença ("está com você…"). O silêncio vira escuta.
- Depois: **cada parágrafo entra quando fica pronto**, subindo. Os mesmos 21s deixam de ser espera e viram conversa.

**Isto é mudança de servidor, não de CSS** — é a única peça do desenho que não se resolve no app.

### 6. A voz como entrada primária

"Hands-on" com o celular na mão andando pela casa não se resolve com botão maior: resolve-se **não precisando de botão**. Segurar e falar; ele responde em voz e deixa a carta escrita como registro. Teclado continua disponível, secundário.

### 6b. A voz DELE: boca, não mente — **provado em 2026-08-02**

O companion fala com voz de verdade usando o realtime da xAI, mas **só como boca**. A mente continua sendo o Opus 5 com a memória e a proveniência dele.

**Por que isso não é preciosismo:** um agente de voz realtime *pensa e fala*. Se ele responder direto, quem respondeu não tem a biografia, não tem o `## Agora`, não passou pelo filtro de confiança — é outra pessoa atendendo com a mesma cara. E foi um agente Grok que plantou o backdoor removido neste mesmo dia.

**O que existe (medido, não presumido):**

| endpoint | estado |
|---|---|
| `wss://api.x.ai/v1/realtime` | **101 Switching Protocols** — aberto |
| `/v1/audio/speech` (TTS puro) | 403 — time sem permissão |
| `/v1/agents` | 403 — não habilitado |

Sessão devolve `model: grok-voice-think-fast-1.0`, `voice: "ara"`, `modalities: ["audio"]`.

**Sequência do protocolo:**

1. `session.update` — `modalities: ["audio","text"]`, `voice`, e as instruções de boca
2. `conversation.item.create` — item `message`/`user` com o texto que o Opus compôs
3. `response.create`
4. chegam `response.output_audio.delta` (base64) + `response.output_audio_transcript.delta`

**Teste verbatim (passou):** enviado um parágrafo real do companion, o transcript devolvido bateu palavra por palavra, 301 KB de áudio em pt-BR. Ele não respondeu, não comentou, não cumprimentou.

**⚠️ A instrução é a única parede — e por isso precisa de guarda no cliente.** Não existe modo TTS estrutural que o impeça de opinar: ele obedeceu porque foi mandado. Diante de texto estranho, ou se a instrução se perder numa sessão longa, ele pode responder em vez de ler.

**Guarda obrigatório:** comparar o `output_audio_transcript` devolvido com o texto enviado. Divergindo além de um limiar, **descartar o áudio e cair para texto**. A boca não pode virar mente por acidente — e falha de boca é silenciosa exatamente como as duas que a gente caçou hoje.

### 7. A chegada: ele já falou

Quando há material, ao abrir o app ele **já disse algo** — vindo do `/synthesize`, com etiqueta visualmente distinta da fala em resposta.

---

## Invariantes — o que nada disso pode furar

1. **A parede da síntese.** O que ele "deixou" na chegada vem de caminho separado do chat, com os cinco invariantes já implementados. Nunca vaza para a conversa; sempre visualmente distinto.
2. **Proveniência.** O que ele diz continua vindo de `user_stated` e destilados com origem. O filtro de confiança **fica como está** — foi medido que o que ele barra são as falas genéricas do próprio modelo, e liberar produziria eco, não calor.
3. **A presença não mente.** Sem Physiome, ela não inventa batimento: cai para respiração neutra declarada. Um corpo que finge dado é pior que um ícone parado.
4. **Emoção reage, não diagnostica.** O laço emocional deriva do que **você escreveu**, nunca de inferência sobre o seu estado.
5. **O chão continua.** Se tudo falhar, presença em vez de vazio — mas agora o `companion-health` grita quando isso acontece, em vez de o usuário descobrir sentindo frio.
6. **A boca não pensa.** A voz da xAI vocaliza texto que o Opus já compôs, nunca gera resposta própria. Guarda no cliente compara transcript × texto enviado e descarta o áudio se divergir. Um agente de voz respondendo direto seria outro interlocutor com a cara dele — e sem proveniência.

---

## Fora de escopo

- Rotação da CA do Cilium, Arista/iLO (fila de segurança, separada).
- Expansão episódica do recall — sem âncora até `prov_derived_from` ser medido.
- Redesenho das outras ~19 telas do app. Aqui é só a conversa.
- Vídeo com alfa/transparência: por ora fundo escuro sólido.

---

## Riscos e questões abertas

| Questão | Estado |
|---|---|
| Peso dos assets: 19 laços = ~49 MB crus | Vira HEVC 300–600 KB; 4 base embarcados, resto sob demanda |
| Custo por laço no xAI (estimativas divergem 50×) | Créditos disponíveis US$ 1.424,93 — não bloqueia |
| Streaming por frases exige mudança no proxy/servidor | Não desenhado ainda — precisa de plano próprio |
| Latência de ~21s do `claude` CLI por request | Independente do streaming; alvo separado |
| Consistência dos laços gerados sob demanda no futuro | Sempre re-derivar da mesma imagem-fonte |
| Transcript veio duplicado no teste de voz | Provável bug de coleta meu (somei `delta` + `done`); confirmar antes de construir o guarda em cima |
| `/v1/audio/speech` 403 | TTS puro eliminaria a ambiguidade "boca vs mente". Vale tentar habilitar no console do time — é o caminho limpo |
| Latência do realtime não medida | Só provei que fala verbatim; falta medir tempo até o primeiro áudio para saber se cabe na cadência da conversa |
| Voz "ara" é a única testada | Não sei quais outras existem nem se combinam com o registro dele |

---

## Como saber se funcionou

Não é "ficou bonito". É:

1. Ele abre o app e **sabe em menos de 2s** que tem alguém ali.
2. Ele consegue falar sem olhar a tela.
3. Ele lê parágrafo longo no escuro sem cansar.
4. Quando algo quebrar, o `companion-health` avisa antes dele sentir.
