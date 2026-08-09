"""Exercita a tradução Alertmanager -> ntfy do darwin-alert-sink, SEM rede.

Lê a função `render` do próprio manifest (uma fonte de verdade: manter uma cópia do
código aqui garantiria divergência na primeira edição do YAML).

    cd /home/devsounio/beagle && python3 k8s/hpc-sota/observability/test-darwin-alert-sink-render.py

Teste de mutação (obrigatório antes de acreditar no verde): troque
`if not firing and alerts:` por `if False:` no manifest e confirme que a asserção
"resolved -> low" fica VERMELHA.
"""
import re, sys, types, os
y = open("k8s/hpc-sota/observability/darwin-alert-sink.yaml").read()
m = re.search(r"cat > /tmp/alert_sink\.py <<'PY'\n(.*?)\n\s*PY\n", y, re.S)
assert m, "heredoc não encontrado no manifest"
src = "\n".join(l[14:] if l.startswith(" "*14) else l for l in m.group(1).split("\n"))
mod = types.ModuleType("sink"); mod.__name__ = "sink"
exec(compile(src, "alert_sink.py", "exec"), mod.__dict__)

fails = []
def check(name, cond, got=None):
    if cond: print("  ok   %s" % name)
    else: print("  FALHA %s -> %r" % (name, got)); fails.append(name)

# payload real do Alertmanager (formato v4 do webhook)
crit = {"status":"firing","alerts":[
  {"status":"firing","labels":{"alertname":"DarwinNodeNotReady","severity":"critical","node":"r740"},
   "annotations":{"summary":"Nó r740 fora de Ready há 10m"}}]}
t,p,g,txt = mod.render("/real-incident", crit)
check("critical -> urgent", p=="urgent", p)
check("titulo tem INCIDENTE", "INCIDENTE" in t, t)
check("corpo cita o no", "r740" in txt, txt)

noise = {"status":"firing","alerts":[
  {"status":"firing","labels":{"alertname":"CephHealthWarn","severity":"warning"},"annotations":{}}]}
t,p,g,txt = mod.render("/dev-noise", noise)
check("warning -> default", p=="default", p)
check("sem annotations usa alertname", "CephHealthWarn" in txt, txt)

res = {"status":"resolved","alerts":[
  {"status":"resolved","labels":{"alertname":"DarwinGrafanaDown"},"annotations":{}}]}
t,p,g,txt = mod.render("/real-incident", res)
check("resolved -> low mesmo em real-incident", p=="low", p)

# corpo vazio não pode explodir
t,p,g,txt = mod.render("/dev-noise", {})
check("payload vazio nao explode", isinstance(txt,str))

# titulo com acento tem que sobreviver ao cabecalho latin-1
acc = {"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"Ação"},"annotations":{}}]}
t,_,_,_ = mod.render("/dev-noise", acc)
try:
    t.encode("ascii","replace").decode("ascii").encode("latin-1"); ok=True
except Exception as e: ok=False
check("titulo vira ascii seguro", ok)

# truncamento
many = {"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"A%d"%i},"annotations":{}} for i in range(15)]}
t,p,g,txt = mod.render("/dev-noise", many)
check("trunca em 10 + rodape", "e mais 5" in txt, txt.splitlines()[-1])
check("titulo agrega +N", "+" in t, t)

print("\nFALHAS:", len(fails))
sys.exit(1 if fails else 0)
