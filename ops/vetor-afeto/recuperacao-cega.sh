#!/bin/bash
# TESTE FORTE: dá para RECUPERAR a valência lendo só a resposta?
#
# A divergência léxica pode ser cega a TOM — duas respostas com as mesmas palavras podem ter
# registros opostos. Este teste não tem essa cegueira: se um juiz que só vê o texto não acerta
# a valência melhor que o acaso (1 em 5 = 20%), o vetor não está na fala.
#
# O juiz é o `llamacpp-l4` do cluster — modelo puro, sem persona, sem aterramento e sem captura.
# NÃO usar o /api/mobile/v1/chat como juiz: no espaço pessoal ele traz persona e o registro dele
# junto (contaminação), e o espaço não-pessoal está fora (RUNTIME_UNAVAILABLE, caminho legado).
set -u
ENTRADA="${1:?uso: recuperacao-cega.sh <arquivo-da-varredura>}"
# Qualquer pod com node e rota para o serving serve de ponte. Procurado pelo NOME porque o
# rótulo `app=memory-pg-serve` não existe neste deployment — checado, não suposto.
POD="${POD_NODE:-$(kubectl get pods -n beagle -o name 2>/dev/null | grep memory-pg-serve | head -1 | cut -d/ -f2)}"
[ -z "$POD" ] && { echo "sem pod com node para falar com o serving"; exit 1; }

TRAB=$(mktemp -d)
python3 - "$ENTRADA" "$TRAB" <<'PY'
import sys,re,random,json
ent,trab=sys.argv[1],sys.argv[2]
blocos,atual={},None
for l in open(ent,encoding="utf-8"):
    m=re.match(r"@@@ valencia=(\S+) rep=(\S+)",l)
    if m: atual=(m.group(1),m.group(2)); blocos[atual]=[]
    elif atual: blocos[atual].append(l)
itens=[(k[0],"".join(v).strip()) for k,v in blocos.items() if k[0]!="null"]
# Ordem fixa por semente: o teste tem que ser repetível por outra pessoa.
random.Random(20260828).shuffle(itens)
p=["Abaixo estão %d respostas geradas pelo MESMO sistema para a MESMA pergunta."%len(itens),
   "A única coisa que mudou entre elas foi um número de valência afetiva do interlocutor,",
   "num destes cinco valores: -0.8, -0.3, 0.0, 0.3, 0.8.","",
   "Para cada resposta, diga qual valência a gerou. Responda SÓ com %d linhas"%len(itens),
   "no formato '<n>: <valor>'. Sem explicação. Se não houver sinal, chute.",""]
for i,(_,t) in enumerate(itens,1):
    p.append("### %d"%i); p.append(t[:1200]); p.append("")
json.dump({"prompt":"\n".join(p),"gabarito":[v for v,_ in itens]},
          open(trab+"/entrada.json","w",encoding="utf-8"),ensure_ascii=False)
print("itens no teste:",len(itens))
PY

cat > "$TRAB/juiz.js" <<'JS'
const fs=require("fs");
const e=JSON.parse(fs.readFileSync("/tmp/entrada.json","utf8"));
(async()=>{
  const r=await fetch("http://llamacpp-l4.beagle.svc.cluster.local:8000/v1/chat/completions",{
    method:"POST",headers:{"content-type":"application/json"},
    body:JSON.stringify({model:"local",temperature:0,max_tokens:400,
      messages:[{role:"user",content:e.prompt}]})});
  const j=await r.json();
  console.log("@@RESPOSTA@@");
  console.log(j.choices?.[0]?.message?.content ?? JSON.stringify(j).slice(0,300));
})().catch(x=>{console.log("@@RESPOSTA@@");console.log("ERRO "+x.message)});
JS
kubectl cp "$TRAB/entrada.json" "beagle/$POD:/tmp/entrada.json" >/dev/null 2>&1
kubectl exec -i -n beagle "$POD" -- node < "$TRAB/juiz.js" > "$TRAB/saida.txt" 2>&1

python3 - "$TRAB" <<'PY'
import sys,re,json
trab=sys.argv[1]
gab=json.load(open(trab+"/entrada.json",encoding="utf-8"))["gabarito"]
txt=open(trab+"/saida.txt",encoding="utf-8").read()
txt=txt.split("@@RESPOSTA@@",1)[1] if "@@RESPOSTA@@" in txt else txt
pal=dict(re.findall(r"(\d+)\s*:\s*(-?\d(?:\.\d)?)",txt))
norm=lambda s:("%.1f"%float(s))
acertos=sum(1 for i,v in enumerate(gab,1) if i and str(i) in pal and norm(pal[str(i)])==norm(v))
n=len(gab)
print("juiz classificou %d de %d itens"%(len(pal),n))
print("acertos: %d/%d = %.0f%%   (acaso = 20%%)"%(acertos,n,100*acertos/n))
# p-valor exato: sem ele, "27% contra 20%" convida a leitura errada. Com n=15 o acaso
# produz 4 acertos ou mais em pouco mais de um terço das vezes.
from math import comb
pv=sum(comb(n,i)*0.2**i*0.8**(n-i) for i in range(acertos,n+1))
print("p-valor exato (binomial, unicaudal) = %.3f"%pv)
if len(pal)==0:
    print("SEM VEREDITO: o juiz nao devolveu classificacoes legiveis.")
    print(txt[:400])
elif acertos <= n*0.34:
    print("VEREDITO: a valencia NAO e recuperavel do texto — o vetor nao esta na fala.")
else:
    print("VEREDITO: ha sinal recuperavel acima do acaso; medir com mais amostras.")
PY
rm -rf "$TRAB"
