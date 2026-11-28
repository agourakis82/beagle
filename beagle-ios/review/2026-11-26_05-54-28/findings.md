# Achados da revisão

Escopo: leitura representativa da entrada, shell, chat, store de conversa e cliente HTTP. Não é auditoria exaustiva. Nenhum código alterado.

## R1 — POST pode repetir efeitos
- Arquivo: BeagleClient.swift, linhas 201–245, módulo BeagleCore.
- Categoria: confiabilidade. Severidade High; confiança Medium; esforço M; prioridade P1.
- Evidência: loop envia POST a cada base e continua após HTTP inválido, erro de transporte ou falha de decode de resposta bem-sucedida. Sem chave de idempotência visível no método genérico.
- Impacto: a primeira requisição pode ter sido executada antes da perda/erro da resposta; o fallback pode repetir jobs ou escritas.
- Recomendação/exemplo: operationId estável com deduplicação no servidor; não repetir mutações automaticamente sem contrato de idempotência.
- Possível falso positivo: endpoints podem já deduplicar no servidor; verificar contrato antes de mudar.

## R2 — Deep link documentado não chega ao projeto
- Arquivo: BeagleCockpitApp.swift, linhas 142–164.
- Categoria: bugs. Severidade Medium; confiança High; esforço S; prioridade P2.
- Evidência: beagle://project/slug tem host project e path /slug; código exige pathComponents começar por project e ter dois elementos.
- Impacto: link documentado é ignorado. Mesmo com parsing corrigido, catálogo vazio descarta navegação e não há destino de projeto instalado no shell do iPhone.
- Recomendação/exemplo: analisar url.host e pathComponents separadamente, guardar destino até catálogo carregar e encaminhar ao shell apropriado.
- Possível falso positivo: formato beagle:///project/slug pode passar pelo parser, mas difere do contrato documentado.

## R3 — Streaming interrompe leitura anterior
- Arquivo: ChatScreen.swift, linhas 528–534.
- Categoria: experiência/confiabilidade. Severidade Medium; confiança High; esforço S; prioridade P2.
- Evidência: toda mudança de conteúdo da última mensagem executa scrollTo(bottom) sem verificar posição ou intenção de leitura.
- Impacto: tentar subir na conversa durante geração retorna ao fim a cada atualização.
- Recomendação/exemplo: seguir geração apenas quando perto do fim; oferecer botão de retorno quando afastado.
- Possível falso positivo: seguir sempre pode ser escolha deliberada; avaliar interação real.

## R4 — Corpo de resposta aparece nos logs
- Arquivo: BeagleClient.swift, linhas 150–172 e 219–241.
- Categoria: privacidade/observabilidade. Severidade Medium; confiança High; esforço S; prioridade P2.
- Evidência: print inclui até 300 caracteres da resposta em erros HTTP ou de decode.
- Impacto: respostas com conteúdo pessoal podem ficar no console e diagnósticos.
- Recomendação/exemplo: registrar status, identificador e erro de schema, com conteúdo redigido e privacidade explícita.
- Possível falso positivo: depende do conteúdo retornado; não foi observada exposição real nesta revisão.
