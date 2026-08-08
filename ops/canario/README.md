# Canário externo do companion

Sonda o companion **de fora do cluster**, a cada 5 minutos, e avisa por um canal
que não é nosso.

## Por que existe

Em 07-ago-2026 o companion ficou inacessível por horas e o dono só soube por
acidente. Duas falhas empilhadas — túnel morto por nó com DNS quebrado, e o
cérebro autenticando com um placeholder — e a sonda que existia não viu nem uma
nem outra. Quando finalmente viu, não conseguiu avisar: ela notifica um ntfy que
mora no mesmo cluster que estava quebrado.

Três regras saíram disso:

1. **Sondar de onde o usuário está.** A sonda in-cluster é estruturalmente cega
   para o túnel Cloudflare, para o DNS de pod do nó em que ela caiu, e para o
   certificado. Esta roda no host Proxmox, que é um domínio de falha separado —
   sobrevive à morte do k8s inteiro.

2. **Checar SEMÂNTICA, não liveness.** HTTP 200 não prova nada aqui: foi um 200
   que carregou `401 Invalid bearer token` até a tela dele como se fosse fala do
   companion. O canário procura assinaturas de erro no corpo, detecta o "chão"
   (presença enlatada sem modelo) e reprova resposta curta demais.

3. **O aviso não pode compartilhar destino com o alarmado.** Vai pelo ntfy.sh
   público — que não é nosso, não roda aqui e não cai com a gente. O ntfy
   self-hospedado continua servindo para diagnóstico verboso, que pode se dar ao
   luxo de morrer junto.

## Estado no disco, de propósito

`estado` guarda ok/quebrado. Sem isso, uma queda de madrugada viraria 30
notificações e ele aprenderia a ignorá-las — que é como um alarme morre de
verdade. Avisa na quebra, cala enquanto continua quebrado, avisa na volta.

## Instalação

    cp canario.sh ~/.beagle/canario/
    cp beagle-canario.* ~/.config/systemd/user/
    systemctl --user daemon-reload && systemctl --user enable --now beagle-canario.timer

`loginctl enable-linger devsounio` é obrigatório (sobreviver a reboot).

O tópico fica em `~/.beagle/ntfy-topico-externo.txt` — fora do git, porque quem
souber o nome pode ler e escrever nele.

## O que ele AINDA não cobre

Se a casa inteira cair (energia, internet), o canário morre junto e ninguém é
avisado — ausência não vira alarme. O conserto é um dead-man's switch externo
(healthchecks.io): o canário pinga um serviço de fora a cada sucesso, e é a
FALTA do ping que dispara a notificação. Cinco minutos de trabalho, exige criar
a conta.
