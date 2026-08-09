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
for s in sounio-herd sounio-herd-tmux sounio-herd-split sounio-lane-worktrees sounio-loomd cli-canary; do
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
| `sounio-herd-tmux` | as 11 lanes em **uma** sessão tmux (`sounio-dev`) → 1 workspace, N abas no cmux |
| `sounio-herd-split` | as 11 lanes em **uma sessão por lane** → N workspaces no cmux (1 por agente) |
| `sounio-herd` | as mesmas lanes em **herdr**, com estado semântico dos agentes |
| `sounio-loomd` | mantém o **loomd** de pé (sessão tmux dedicada `loomd`) — o supervisor que publica estado vindo do protocolo (`exact`), não de tela raspada (`inferred`) |

Todos idempotentes: criam só as lanes que faltam e (nos de tmux) revivem no lugar
as que morreram.

### tmux vs split — os dois mapeamentos para o cmux

O cmux (`cmux ssh-tmux <host>`) lê o **servidor tmux inteiro**: cada *sessão* vira
um workspace na sidebar, cada *janela* vira uma aba vertical. Daí os dois modos:

- **`sounio-herd-tmux`** — 1 sessão `sounio-dev` com 11 janelas → **1 workspace,
  11 abas**. As lanes ficam agrupadas como "o projeto Sounio".
- **`sounio-herd-split`** — 11 sessões de 1 janela → **11 workspaces de topo**,
  cada agente com nome, branch/PR e **notificação independente**. Melhor para ver
  de relance quem travou esperando aprovação.

O split é **não-destrutivo**: não toca na `sounio-dev`. Dá para rodar os dois e
comparar no cmux; se preferir o split, aposente a `sounio-dev` depois.

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
  Use colchetes (`mosh-server[.]real`) ou exclua o próprio PID. Medido de novo em
  09-ago-2026, agora com `pkill`: um `pkill -f /workspace/.loomd/...` disparado de
  dentro de um `su -c "...pkill -f /workspace/.loomd/..."` casou o **próprio su** e
  matou o comando no meio. O `sounio-loomd` não contém pgrep nem pkill: derruba por
  `tmux kill-session` e decide vivacidade por `/livez`.
- **`root` no `kubectl exec` NÃO tem `CAP_SYS_PTRACE`.** `readlink /proc/<pid>/exe`
  de um processo de outro UID devolve EACCES, e o campo sai **vazio** — igualzinho
  a "não existe processo". Leia `/proc/<pid>/exe` como o **dono** do processo.
- **`curl -w '%{http_code}'` já imprime `000` quando a conexão falha.** Um
  `|| echo 000` de fallback concatena e produz `000000`; e sem fallback nenhum, o
  `set -e` mata o script no exit 7 do curl. O certo é `|| true`.
- **`ss` não existe neste container.** `ss | grep 4400` sai 1 por ENOENT, o que se
  lê distraidamente como "porta livre". Para saber quem está em LISTEN, leia
  `/proc/net/tcp{,6}` (estado `0A`, porta em hexadecimal: 4400 = `1130`).
- **O binário de cada agente mora no HOME da lane** (`.agents/<lane>/.local/bin`,
  `.kimi-code/bin`). Passar só `HOME` sem o `PATH` correspondente faz o
  `agent start` falhar por timeout.
- **`remain-on-exit` é window-option e precisa ser GLOBAL (`set-option -g`).**
  `set-option -t <sessão> remain-on-exit on` **não** propaga para as janelas —
  elas herdam o global `off` e *somem* quando o agente sai (uma atualização de
  agente apagava a lane inteira do cmux, sem aviso). Com `-g on`, o painel fica em
  estado morto, visível, e é revivido no lugar por `respawn-pane -k`.
- **Nome de sessão que colide com nome de janela precisa de `:` no target.** No
  split, a sessão `claude-2` e a janela `sounio-dev:claude-2` coexistem; um target
  de pane `"=claude-2"` fica ambíguo e o tmux resolve para *nada* (campos vazios).
  Force o escopo de sessão com o dois-pontos: `"=claude-2:"`.
