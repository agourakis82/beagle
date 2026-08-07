# habitat-bin

Scripts que rodam **dentro** do pod do habitat, em `~/bin` do usuário
`openvscode-server`. Não confundir com [`../scripts/`](../scripts), que roda no
plano de controle (render, publish, scaffold).

O `~/bin` do habitat fica no PVC, então sobrevive a recriação do pod — mas não é
versionado por si só. Este diretório é a fonte de verdade; a cópia no PVC é a
que executa.

## Implantar

```bash
POD=sounio-workspace-control-0
NS=beagle
for s in sounio-herd sounio-herd-tmux; do
  kubectl cp -n "$NS" -c workspace-ssh "$s" "$POD:/workspace/.home/openvscode-server/bin/$s"
  kubectl -n "$NS" exec "$POD" -c workspace-ssh -- sh -c \
    "chmod +x /workspace/.home/openvscode-server/bin/$s && \
     chown openvscode-server:openvscode-server /workspace/.home/openvscode-server/bin/$s"
done
```

Use `kubectl cp` e não um heredoc por `kubectl exec`: as aspas aninhadas
corrompem o arquivo silenciosamente.

## O que há aqui

| script | o quê |
|---|---|
| `sounio-herd-tmux` | abre a herd das 11 lanes em **tmux** (sessão `sounio-dev`) |
| `sounio-herd` | as mesmas lanes em **herdr**, com estado semântico dos agentes |

Ambos são idempotentes: criam só as lanes que faltam e reconectam na sessão
existente.

### Por que dois

O `sounio-herd-tmux` é o caminho principal, por duas razões concretas:

1. Ele lança cada lane pelo `~/bin/sounio-lane-shell`, o lançador canônico do
   habitat, que aplica os **limites de memória por agente** (`ulimit -Sv`,
   `NODE_OPTIONS=--max-old-space-size`) e força **IPv4 no DNS** — o egress IPv6
   do workspace está quebrado. Sem isso, uma lane de claude pode consumir o
   cgroup inteiro do sidecar SSH.
2. O **cmux**, a GUI de macOS, anexa a sessões *tmux* remotas via `tmux -CC`
   (control mode) e espelha janelas como abas nativas. Ele não enxerga zellij
   nem herdr.

O `sounio-herd` existe porque o herdr reconhece o agente em cada painel e expõe
`idle | working | blocked | done` por uma API de socket — coisa que o tmux não
faz. **Mas ele tem uma limitação conhecida:** a API `herdr agent start` sobe o
binário do agente diretamente e não aceita um wrapper, então as lanes criadas por
ele **não passam pelo `sounio-lane-shell`** e ficam sem os limites de memória.
Use com consciência disso, ou prefira o tmux e deixe a detecção de agente para o
cmux.

## Armadilhas já pagas

- **Socket por UID.** `tmux` usa `$TMUX_TMPDIR/tmux-$UID` e o zellij usa
  `$TMPDIR/zellij-$UID`. Consultar como `root` via `kubectl exec` olha o
  diretório errado e faz uma sessão viva parecer morta. O `sounio-herd-tmux`
  exporta `TMUX_TMPDIR` explicitamente por isso.
- **`TMPDIR` só em shell interativo.** O `.zshrc`/`.bashrc` do habitat define
  `TMPDIR=/workspace/.tmp` (workspace-disk-guard), mas shell não-interativo não
  os lê. Daí o `ZELLIJ_SOCKET_DIR` fixado no `.zshenv`.
- **`pgrep -f <padrão>` casa com a própria linha de comando** de quem chama.
  Use colchetes (`mosh-server[.]real`) ou exclua o próprio PID.
- **O binário de cada agente mora no HOME da lane** (`.agents/<lane>/.local/bin`,
  `.kimi-code/bin`). Passar só `HOME` sem o `PATH` correspondente faz o
  `agent start` falhar por timeout.
