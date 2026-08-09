B=/workspace/.home/openvscode-server
export PATH="$B/bin:$B/.local/node-v20.20.2-linux-x64/bin:$B/.local/bin:$PATH"
export HOME=$B/.agents/codex-1
export LOOMD_ADDR=127.0.0.1:4402 LOOMD_TRAMA=/tmp/loomd3/trama.jsonl
export LOOMD_CODEX_LANES=lab-1 LOOMD_CWD=/tmp/loomdws
export LOOMD_CODEX_ARGS="-c model_reasoning_effort=high -c approval_policy=never -c sandbox_mode=read-only"
export LOOMD_CODEX_BIN="$B/.local/node-v20.20.2-linux-x64/bin/codex"
rm -rf /tmp/loomd3; mkdir -p /tmp/loomd3 /tmp/loomdws
( export PATH="$B/.cargo/bin:$PATH"; export HOME=$B; cd /workspace/.loomd && cargo build --release -j 8 2>&1 | grep -E "^error" )
/workspace/.loomd/target/release/loomd 2>/dev/null & LD=$!
sleep 3
q(){ curl -s --max-time 25 "$@"; }
echo "── turno 1: guardar um número"
q -X POST localhost:4402/v2/lanes/lab-1/prompt -H 'content-type: application/json' \
  -d '{"text":"guarde o numero 4271. responda apenas OK"}' >/dev/null
for i in $(seq 1 60); do
  q localhost:4402/v2/state | grep -q '"kind":"turn_ended"' && break; sleep 2
done
TID=$(q localhost:4402/v2/state | python3 -c "import sys,json;print(json.load(sys.stdin)['lanes'][0].get('session',''))")
echo "   thread: $TID"
# pgrep -f "codex app-server" NÃO casa: o loomd insere os `-c` no meio da linha de comando.
# Na primeira tentativa o PID veio VAZIO, nada foi morto, e o "4271" respondido pelo MESMO
# processo pareceu prova de resume. Falso positivo que quase passou.
PID=$(pgrep -f "app-server --listen" | head -1)
if [ -z "$PID" ]; then echo "   ABORTA: não achei o app-server; o teste não provaria nada"; kill $LD; exit 1; fi
echo "── MATANDO o app-server (pid $PID) — o supervisor tem que ressuscitar E retomar"
kill -9 "$PID"
sleep 15
PID2=$(pgrep -f "app-server --listen" | head -1)
echo "   pid antes=$PID  depois=$PID2"
if [ "$PID" = "$PID2" ] || [ -z "$PID2" ]; then echo "   ABORTA: o processo não foi substituído"; kill $LD; exit 1; fi
TID2=$(q localhost:4402/v2/state | python3 -c "import sys,json;print(json.load(sys.stdin)['lanes'][0].get('session',''))")
echo "   thread depois do restart: $TID2"
echo "── turno 2: o contexto sobreviveu?"
q -X POST localhost:4402/v2/lanes/lab-1/prompt -H 'content-type: application/json' \
  -d '{"text":"qual numero eu pedi para voce guardar? responda so o numero"}' >/dev/null
for i in $(seq 1 45); do sleep 2; done
q 'localhost:4402/v2/trama?since=0' | python3 -c "
import sys,json
ev=json.load(sys.stdin)['events']
print('   eventos:',len(ev))
for e in ev:
    d=(e.get('detail') or '')
    if 'retomada' in d: print('   ✦',d)
    if '4271' in d: print('   ✦ RESPOSTA:',repr(d[:60]))
"
kill $LD 2>/dev/null; pkill -f "codex app-server" 2>/dev/null; true
