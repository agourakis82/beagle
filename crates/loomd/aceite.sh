B=/workspace/.home/openvscode-server
export PATH="$B/bin:$B/.local/node-v20.20.2-linux-x64/bin:$B/.local/bin:$PATH"
export HOME=$B/.agents/codex-1
export LOOMD_ADDR=127.0.0.1:4400 LOOMD_TRAMA=/tmp/loomd/trama.jsonl
export LOOMD_CODEX_LANES=lab-1 LOOMD_CWD=/tmp/loomdws
export LOOMD_CODEX_ARGS="-c model_reasoning_effort=high -c approval_policy=untrusted -c sandbox_mode=workspace-write"
export LOOMD_CODEX_BIN="$B/.local/node-v20.20.2-linux-x64/bin/codex"
rm -rf /tmp/loomd /tmp/loomdws; mkdir -p /tmp/loomd /tmp/loomdws
printf "linha um\nlinha dois\n" > /tmp/loomdws/alvo.txt
# Rebuild SEMPRE antes de medir: `cargo test` não atualiza target/release/loomd, e rodar o
# binário velho já custou uma rodada inteira de diagnóstico errado.
( export PATH="$B/.cargo/bin:$PATH"; export HOME=$B; cd /workspace/.loomd && cargo build --release -j 8 2>&1 | grep -E "^error" )
/workspace/.loomd/target/release/loomd & LD=$!
sleep 3
q(){ curl -s --max-time 30 "$@"; }
echo "── manda o pedido (política untrusted força aprovação):"
q -X POST localhost:4400/v2/lanes/lab-1/prompt -H 'content-type: application/json' \
  -d '{"text":"edite alvo.txt trocando dois por DOIS"}'; echo
echo "── esperando a lane pedir aprovação…"
T0=$(date +%s%3N)
for i in $(seq 1 90); do
  P=$(q localhost:4400/v2/state | grep -o '"kind":"awaiting_approval"' | head -1)
  [ -n "$P" ] && break; sleep 1
done
T1=$(date +%s%3N)
echo "── estado agora:"; q localhost:4400/v2/state | head -c 400; echo
echo "── APROVA sem anexar:"; q -X POST localhost:4400/v2/lanes/lab-1/approve -H 'content-type: application/json' -d '{"allow":true}'; echo
sleep 12
echo "── arquivo:"; cat /tmp/loomdws/alvo.txt
echo "── último diff, respondido da TRAMA:"; q localhost:4400/v2/state | python3 -c "
import sys,json
d=json.load(sys.stdin)
for l in d['lanes']:
    print('   lane',l['lane'],'kind',l['kind'],'turns',l.get('turns'),'confidence',l['confidence'])
    if l.get('last_diff'): print('   diff:',repr(l['last_diff'][:70]))
"
echo "── trama (eventos tipados, todos exact?):"
q 'localhost:4400/v2/trama?since=0' | python3 -c "
import sys,json
ev=json.load(sys.stdin)['events']
print('   total',len(ev),'· exact:',sum(1 for e in ev if e['confidence']=='exact'))
print('   ', ' → '.join(e['kind'] for e in ev[:14]))
"
kill $LD 2>/dev/null
