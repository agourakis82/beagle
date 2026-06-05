# Sounio: acesso SSH ao MacBook Pro M3 para teste em hardware real

Este runbook explica como o agente que roda no T560/Cabernet ou no workspace
Kubernetes do Sounio deve acessar o MacBook Pro via SSH para executar testes que
precisam de hardware Apple Silicon real.

## Contexto

O desenvolvimento ativo do Sounio acontece remotamente, com o T560/Cabernet como
superficie operacional e o workspace canonico em Kubernetes. Alguns testes do
port native/AD nao devem ser considerados fechados somente com build Linux ou
cross-compile: eles precisam rodar em um Mac Apple Silicon de verdade.

O alvo atual para essa validacao e o MacBook Pro:

- Tailscale DNS: `macbook-pro-de-demetrios-2.tail21cbc4.ts.net`
- Tailscale IP: `100.91.184.41`
- Usuario macOS: `demetriosagourakis`
- Usuario/host SSH completo: `demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net`

O Mac Pro tambem existe na Tailnet (`mac-pro-de-demetrios.tail21cbc4.ts.net`),
mas na ultima verificacao ele deu timeout. Para a rodada atual, use o MacBook Pro
como alvo primario.

## Por que este teste precisa rodar no MacBook Pro

O objetivo nao e apenas confirmar que o codigo compila. O teste precisa provar
que o binario `aarch64-macos` gerado pelo Sounio executa corretamente no ABI real
do macOS/Apple Silicon.

Em particular, o agente deve validar:

- execucao real em `arm64` no macOS, sem depender de inferencia por cross-compile;
- chamadas/runtime basicas, incluindo `print_f64`;
- valor numerico conhecido de sensibilidade/AD;
- alinhamento de stack pointer conforme exigencia ABI;
- comportamento de entrada/saida quando o binario e copiado para o Mac e executado
  fora do container Linux.

Sem essa rodada, o port AD-shadow pode parecer correto no ambiente remoto, mas
ainda falhar em detalhes de ABI, loader, permissao de execucao ou alinhamento no
hardware real.

## Pre-requisitos no MacBook Pro

No MacBook Pro, o Remote Login precisa estar ligado:

1. System Settings
2. General
3. Sharing
4. Remote Login: On

O arquivo `~/.ssh/authorized_keys` do usuario `demetriosagourakis` precisa conter
as chaves publicas dos ambientes que vao acessar o Mac. As chaves ja autorizadas
para este fluxo sao:

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDLacRx80HpPnwLoll0EoPe7Uca08Wil+SckW0os9N9w sounio-workspace
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGmwNq7Cj9UECnacMrmM8ALrkI3uhbOWevGY328C+8j5 devsounio@codex-sounio
```

As permissoes esperadas no Mac:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

Se o agente receber `Permission denied (publickey)`, primeiro confira se a chave
publica que ele esta usando e exatamente uma das chaves acima. Depois confira se
o Remote Login esta ligado e se as permissoes do `~/.ssh` nao estao abertas
demais.

## Acesso a partir do workspace Kubernetes do Sounio

Do workspace/container onde o Sounio roda, a chave privada esperada para este
fluxo fica em:

```text
/workspace/.home/openvscode-server/.ssh/id_ed25519
```

Teste de conectividade recomendado:

```bash
ssh \
  -i /workspace/.home/openvscode-server/.ssh/id_ed25519 \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o ConnectTimeout=8 \
  demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net \
  'hostname; sw_vers; uname -m; arch'
```

Resultado esperado:

- conexao SSH sem senha;
- `sw_vers` mostrando macOS;
- `uname -m` / `arch` indicando `arm64`.

Se houver alerta de host key, registre a chave do Mac antes da rodada:

```bash
ssh-keyscan macbook-pro-de-demetrios-2.tail21cbc4.ts.net >> ~/.ssh/known_hosts
```

## Acesso a partir do T560/Cabernet

No T560, use o mesmo alvo Tailnet:

```bash
ssh demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net \
  'hostname; sw_vers; uname -m; arch'
```

Se o T560 estiver usando uma chave diferente da chave autorizada no Mac, a conexao
vai falhar com `Permission denied (publickey)`. Nesse caso, uma destas duas coisas
precisa acontecer:

- autorizar no Mac a chave publica efetivamente usada pelo T560; ou
- apontar explicitamente o SSH do T560 para a chave privada cuja publica ja esta
  no `authorized_keys` do Mac.

Para descobrir qual chave o cliente esta oferecendo, rode:

```bash
ssh -vvv -o BatchMode=yes demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net true
```

Procure por linhas `Offering public key`.

## Rodada de validacao do binario macOS

O padrao de validacao e:

1. gerar ou localizar o binario `aarch64-macos` no workspace remoto;
2. copiar o binario para uma pasta temporaria no MacBook Pro;
3. marcar como executavel;
4. executar no MacBook Pro via SSH;
5. comparar stdout/stderr e exit code com o esperado;
6. remover artefatos temporarios se necessario.

Exemplo de esqueleto:

```bash
MAC_HOST=demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net
MAC_DIR=/tmp/sounio-hw-verify
BIN_LOCAL=/workspace/sounio/artifacts/macos/test_ad_shadow_aarch64

ssh "$MAC_HOST" "mkdir -p '$MAC_DIR'"
scp "$BIN_LOCAL" "$MAC_HOST:$MAC_DIR/test_ad_shadow_aarch64"
ssh "$MAC_HOST" "chmod +x '$MAC_DIR/test_ad_shadow_aarch64' && '$MAC_DIR/test_ad_shadow_aarch64'"
```

Quando estiver rodando a partir do workspace Kubernetes e precisar forcar a chave:

```bash
MAC_HOST=demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net
MAC_KEY=/workspace/.home/openvscode-server/.ssh/id_ed25519
MAC_DIR=/tmp/sounio-hw-verify
BIN_LOCAL=/workspace/sounio/artifacts/macos/test_ad_shadow_aarch64

ssh -i "$MAC_KEY" -o IdentitiesOnly=yes "$MAC_HOST" "mkdir -p '$MAC_DIR'"
scp -i "$MAC_KEY" -o IdentitiesOnly=yes "$BIN_LOCAL" "$MAC_HOST:$MAC_DIR/test_ad_shadow_aarch64"
ssh -i "$MAC_KEY" -o IdentitiesOnly=yes "$MAC_HOST" \
  "chmod +x '$MAC_DIR/test_ad_shadow_aarch64' && '$MAC_DIR/test_ad_shadow_aarch64'"
```

O teste minimo que destrava o port AD-shadow deve imprimir:

- uma saida `print_f64` conhecida;
- um valor de sensibilidade/derivada conhecido;
- exit code `0`.

Se o binario falhar com permissao, confira `chmod +x`. Se falhar com formato de
executavel, confira se o artefato e realmente `Mach-O 64-bit executable arm64`.
Se falhar em runtime/alinhamento, isso e sinal valido para corrigir o backend,
nao para ignorar a rodada.

## Troubleshooting rapido

Conectividade Tailnet:

```bash
tailscale status | grep -E 'macbook-pro-de-demetrios-2|100.91.184.41'
```

SSH sem senha:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 \
  demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net true
```

Diagnostico de chave:

```bash
ssh -vvv -o BatchMode=yes \
  demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net true
```

Validar arquitetura do binario antes de copiar:

```bash
file /path/to/binario
```

Validar arquitetura no Mac:

```bash
ssh demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net 'uname -m; arch'
```

## Regra operacional

Nao iniciar o port AD-shadow como "concluido" sem antes passar pela rodada de
hardware no MacBook Pro. O MacBook Pro e a fonte de verdade para confirmar que o
binario `aarch64-macos` roda no ABI real do Apple Silicon.
