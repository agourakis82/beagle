# Complemento: companion e OpenAI

Leitura estática em 2026-11-26; arquivos mudando por outros agentes. Nenhuma chamada autenticada, alteração de código ou teste realizado.

A integração direta já existe em BeagleMCPClient.swift: streamOpenAI (786), Chat Completions via URLSession (929), até três rodadas de ferramentas (853), memória GraphRAG com seis evidências (748). ConversationStore envia 60 mensagens e resumo (736), contexto fisiológico, grounding e continuidade (806), sincroniza resposta direta ao cluster (884). Sem chave direta, usa cluster (924).

R5: credenciais diretas persistidas em UserDefaults (561–585). Categoria segurança; High, confiança High, esforço M, P1. Preferir credenciais no cluster; caso acesso direto pessoal seja necessário, Keychain. Valores não foram acessados; risco de exposição depende de backups e acesso ao dispositivo.
R6: fallback em qualquer 400/404 troca modelo (956–973). Categoria confiabilidade; Medium, confiança High, esforço S, P2. Erro 400 pode ser schema/parâmetro; classificar erro e registrar modelo efetivamente usado. A resposta pode registrar modelo configurado, diferente do efetivo (ConversationStore 879). Sketch: resultado tipado contendo effectiveModel. Possível falso positivo: fallback pode ser intencional, mas observabilidade continua necessária.

SDK não é pré-requisito: transporte próprio já implementa streaming e tools. Responses API pode ser evolução deliberada do contrato; SDK oficial de backend pode reduzir manutenção se compatível com stack do cluster, que não foi inspecionada. Swift aparece em bibliotecas comunitárias na documentação oficial consultada: https://developers.openai.com/api/docs/libraries . Guia: https://developers.openai.com/api/docs/guides/migrate-to-responses .

Próximo passo proposto: definir se o caminho canônico de inferência é cluster ou acesso direto; medir latência de recall, primeiro token e ferramentas; corrigir credenciais/modelo efetivo; avaliar migração Responses com avaliação comparativa. Não implementar mudança ampla sem pedido.

Memória canônica não capturada: MCP Beagle indisponível e wrapper ausente, conforme verificação anterior.

## Implementação autorizada

Chaves OpenAI/Anthropic digitadas agora usam Keychain WhenUnlockedThisDeviceOnly. Migração lazy remove UserDefaults somente após gravação bem-sucedida; falha preserva legado sem usá-lo em plaintext. Erros OpenAI 400/404 não fazem downgrade entre modelos. O resultado tipado leva o modelo retornado no SSE até a mensagem persistida. Transporte injetável para fixtures sem rede.

Verificações: três métodos Swift Testing passaram no macOS (HTTP 400/404 parametrizado, modelo SSE e ciclo de credencial sintética). HTTP e SSE também passaram no simulador iOS. O teste real de Keychain foi restrito ao macOS porque o executor hostless iOS não dispõe de acesso ao Keychain; validação em app iOS assinado permanece pendente. Não foram lidas chaves reais nem efetuadas chamadas pagas. Sem SDK novo ou migração de API.

## Migração para Responses autorizada pelo usuário

Integração direta e compactor OpenAI agora usam /v1/responses com input, imagens input_image, ferramentas achatadas e eventos semânticos SSE. Continuação de tools reenvia output completo (incluindo reasoning.encrypted_content) e function_call_output com call_id, usando store=false. Respostas interrompidas/falhas são erros. Seleção explícita gpt-5.5 preservada; configuração continua válida para MoE/default. Anthropic e roteador do cluster não alterados nesta migração.

Validação: 7 resultados Swift Testing passaram no macOS; BuildProject do BeagleCockpit para iPhone 17 Pro Max (27.0) passou em 16,885 s; git diff --check passou. Nenhuma chamada paga ou credencial real acessada. Validação de produção com conta real não executada. Memória canônica no cluster não capturada: MCP Beagle indisponível e wrapper ausente na sessão.

Referências oficiais consultadas: https://developers.openai.com/api/docs/guides/migrate-to-responses ; https://developers.openai.com/api/docs/guides/function-calling ; https://developers.openai.com/api/docs/guides/streaming-responses .

## Nova verificação solicitada

Smoke de UI via device-interaction: instalação/abertura no iPhone 17 Pro Max 27.0 concluída, menu abriu, seleção GPT 5.5 confirmou voz ativa e composer recebeu foco. Sessão encerrada, nenhuma mensagem enviada. Descrição Local Sem Censura truncada. Modo demo não isolou inteiramente conversa persistida; captura não publicada.

Reexecução dos testes no macOS e iOS bloqueada na compilação de AppleDeviceToolsBridge.swift: Result com String como Error (414,434), BulaStore sem consultaPCDTDireta e buscarFarmacosSemelhantes (369,392). Nenhum novo resultado de testes aprovado nesta rodada; os sete aprovados pertencem à rodada anterior. Esquema BeagleCockpit/destino original restaurados. git diff --check passou. Nenhuma alteração de código nesta rodada. Próximo passo: concluir/corrigir a bridge em edição no workspace, reexecutar testes e depois validar API real. Captura canônica permanece indisponível nesta sessão.

## Bloqueio de compilação resolvido

AppleDeviceToolsBridge usa AccessResult próprio para autorização com mensagem, eliminando Result<Void,String>. Métodos BulaStore ausentes foram adicionados simultaneamente no workspace por outro trabalho; preservados. Limite de consulta SQLite limitado a 20. Não houve alteração das permissões do usuário, criação de eventos ou mudança de lembretes.

BuildProject BeagleCockpit iPhone passou em 63,821 s. Reexecução macOS: 8 casos passaram, zero falhas. Reexecução iOS: 5 resultados reportados passaram, zero falhas. Esquema e destino BeagleCockpit/iPhone 17 Pro Max restaurados. git diff --check passou. API real não chamada. Memória canônica não capturada: MCP Beagle e wrapper indisponíveis nesta sessão.
