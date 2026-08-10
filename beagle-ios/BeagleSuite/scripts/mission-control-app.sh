#!/usr/bin/env bash
# mission-control-app.sh — empacota o Mission Control como um .app de VERDADE.
#
# POR QUE ISTO EXISTE. O Mission Control é um `executableTarget` do SwiftPM, e um executável solto
# no macOS não tem bundle: sem bundle não há ícone, não há nome no Dock, não há identidade — o
# `AppDelegate` precisava chamar `setActivationPolicy(.regular)` só para aparecer na tela. A queixa
# "precisa criar um ícone bonito" tinha causa estrutural, não de desenho.
#
# POR QUE NÃO ENTRAR NO BeagleSuite.xcodeproj. Aquele projeto é gerado do `project.yml` e está
# sendo editado por outro agente; mexer nele agora é disputa de arquivo por nada. Um bundle é uma
# árvore de diretórios com um Info.plist — dá para montar sem tocar em nada de ninguém, e sai
# reproduzível. Se um dia o alvo entrar no Xcode, este script morre e não deixa saudade.
#
#   bash scripts/mission-control-app.sh              # monta em ./.build/Sounio Mission Control.app
#   bash scripts/mission-control-app.sh --install    # e copia para /Applications
#
# O ícone é RENDERIZADO do código (`AppIconArt`), pela mesma suíte que retrata a Frota e a Sessão.
# Nenhum PNG entra no repo: o desenho é a fonte.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
PKG="$PWD"
APP_NAME="Sounio Mission Control"
BUNDLE_ID="ai.sounio.missioncontrol"
DEST="$PKG/.build/$APP_NAME.app"
SHOTS="/tmp/frota-snapshots"

# O SDKROOT do CommandLineTools vaza no ambiente e se mistura com a toolchain do Xcode
# (`Invalid manifest`). Já custou uma rodada inteira; a limpeza fica aqui, não na memória de quem
# roda.
unset SDKROOT DEVELOPER_DIR || true

echo "== build release =="
swift build -c release --product SounioMissionControl

BIN="$(swift build -c release --product SounioMissionControl --show-bin-path)/SounioMissionControl"
[ -x "$BIN" ] || { echo "FALHA: binário não saiu em $BIN" >&2; exit 1; }

echo "== ícone (renderizado do código) =="
# A suíte escreve os PNGs; se ela não rodar, o ícone não existe e o bundle sai sem — e um bundle
# sem ícone é o problema que este script existe para consertar. Então falha alto.
swift test --filter "SessionSnapshotTests/testIcone" >/dev/null 2>&1 || \
  swift test --filter SessionSnapshotTests >/dev/null 2>&1 || true
[ -f "$SHOTS/icone-1024.png" ] || { echo "FALHA: o retrato do ícone não foi gerado" >&2; exit 1; }

ICONSET="$PKG/.build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
# O renderer usa scale 2, então `icone-N.png` tem 2N pixels — ele já É o @2x daquele tamanho
# lógico. O 1x sai por redução do mesmo desenho, e não de um desenho maior: abaixo de 32pt a arte
# é a SIMPLIFICADA, e reduzir a de 1024 traria de volta o borrão de onze fios.
for L in 16 32 128 256 512; do
  cp "$SHOTS/icone-$L.png" "$ICONSET/icon_${L}x${L}@2x.png"
  sips -z "$L" "$L" "$SHOTS/icone-$L.png" --out "$ICONSET/icon_${L}x${L}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$PKG/.build/AppIcon.icns"

echo "== bundle =="
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cp "$BIN" "$DEST/Contents/MacOS/$APP_NAME"
cp "$PKG/.build/AppIcon.icns" "$DEST/Contents/Resources/AppIcon.icns"

# O heredoc abaixo é QUOTADO de propósito: dentro dele nada de $ ou de crase é interpretado.
# 🚨 Já custou: uma crase num COMENTÁRIO do plist foi EXECUTADA como comando, e o texto
# desapareceu do arquivo gerado. Plist é DADO — dado não passa por shell. Os valores entram
# depois, por sed sobre marcadores @@…@@.
cat > "$DEST/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>@@APP_NAME@@</string>
  <key>CFBundleDisplayName</key><string>@@APP_NAME@@</string>
  <key>CFBundleExecutable</key><string>@@APP_NAME@@</string>
  <key>CFBundleIdentifier</key><string>@@BUNDLE_ID@@</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>@@BUILD@@</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <!-- Escuro por decisão: o Mission Control é uma tela de plantão, e o BeagleTheme resolve por
       aparência. Sem isto, um Mac em modo claro renderizava texto claro sobre fundo claro. -->
  <key>NSRequiresAquaSystemAppearance</key><false/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <!-- 🚨 App Transport Security. Isto apareceu no PRIMEIRO uso do bundle: "cockpit não
       alcançável, não é conexão segura". O executável solto não passava pela checagem; um app com
       Info.plist passa, e o ATS bloqueia http:// por padrão. Medido no Mac: o cockpit responde 200
       em http e 000 em https — não há TLS escutando no tailnet.

       A exceção é ESCOPADA ao domínio do tailnet, nunca NSAllowsArbitraryLoads. E ela tem
       justificativa em vez de ser desvio: o tailnet é WireGuard, então o tráfego já é cifrado e
       autenticado na camada de rede; o que falta é TLS dentro de um túnel que já não é público.
       Abrir para o mundo inteiro só para alcançar um host próprio trocaria uma inconveniência por
       uma perda real.

       Se um dia o cockpit terminar TLS no tailnet (tailscale cert), esta exceção sai e o
       FleetEndpoint passa a nascer em wss. -->
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSExceptionDomains</key>
    <dict>
      <key>tail21cbc4.ts.net</key>
      <dict>
        <key>NSIncludesSubdomains</key><true/>
        <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
      </dict>
    </dict>
  </dict>
</dict>
</plist>
PLIST

BUILD_STAMP="$(date +%Y%m%d%H%M)"
/usr/bin/sed -i "" \
  -e "s|@@APP_NAME@@|$APP_NAME|g" \
  -e "s|@@BUNDLE_ID@@|$BUNDLE_ID|g" \
  -e "s|@@BUILD@@|$BUILD_STAMP|g" \
  "$DEST/Contents/Info.plist"

# O plist malformado faz o app abrir SEM ícone e sem nome, e não diz por quê. Então ele é
# conferido aqui, e a exceção de ATS é conferida por VALOR — não por "o texto está no arquivo".
plutil -lint "$DEST/Contents/Info.plist" >/dev/null \
  || { echo "FALHA: Info.plist inválido" >&2; exit 1; }
[ "$(plutil -extract CFBundleName raw -o - "$DEST/Contents/Info.plist")" = "$APP_NAME" ] \
  || { echo "FALHA: o nome não foi substituído no plist" >&2; exit 1; }
ATS=$(/usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity:NSExceptionDomains:tail21cbc4.ts.net:NSExceptionAllowsInsecureHTTPLoads' "$DEST/Contents/Info.plist" 2>/dev/null || true)
[ "$ATS" = "true" ] \
  || { echo "FALHA: sem a exceção de ATS do tailnet o app diria 'não é conexão segura'" >&2; exit 1; }

printf 'APPL????' > "$DEST/Contents/PkgInfo"

# Assinatura ad-hoc: sem ela o macOS pede permissão a cada execução e o ícone às vezes não
# atualiza no Dock. Ad-hoc basta para uso local; distribuir exigiria conta e notarização.
codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || echo "  (codesign ad-hoc falhou — o app roda, mas o Dock pode teimar no ícone)"

# O Dock cacheia ícone por caminho; sem isto o app novo aparece com o ícone genérico.
touch "$DEST"

echo "== pronto: $DEST =="
if [ "${1:-}" = "--install" ]; then
  # 🚨 REINICIAR, e PROVAR que reiniciou. Isto existe por uma falha medida, não por capricho:
  # em 10-ago-2026 o operador testou TRÊS vezes um app cujo processo tinha sido lançado CINCO
  # MINUTOS ANTES do binário novo ser escrito. Copiar para /Applications não toca no app já
  # aberto — e "testei, não funciona" e "testei o build velho" são indistinguíveis de fora.
  #
  # `quit` limpo, nunca `pkill -9`: medido também — matar à força deixa o app reabrindo SEM
  # janela nenhuma, e aí ele fica com um app inútil e nenhuma pista do porquê.
  echo "== instalando =="
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do pgrep -f "$APP_NAME.app/Contents/MacOS" >/dev/null || break; sleep 0.5; done
  pgrep -f "$APP_NAME.app/Contents/MacOS" >/dev/null && { echo "  (não encerrou sozinho; forçando)"; pkill -f "$APP_NAME.app/Contents/MacOS" || true; sleep 2; }

  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$DEST" "/Applications/$APP_NAME.app"
  open -a "/Applications/$APP_NAME.app"

  # A PROVA. Um PID mais velho que o binário significa que ele está testando outra coisa.
  for _ in $(seq 1 24); do PID=$(pgrep -f "/Applications/$APP_NAME.app/Contents/MacOS" | head -1); [ -n "$PID" ] && break; sleep 0.5; done
  BIN_MTIME=$(stat -f %m "/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || echo 0)
  if [ -z "${PID:-}" ]; then
    echo "  ⚠️  o app NÃO subiu — nada do que for testado agora vale" >&2; exit 1
  fi
  PID_START=$(ps -o lstart= -p "$PID" 2>/dev/null | xargs -0 date -j -f "%a %b %d %T %Y" +%s 2>/dev/null || echo 0)
  # ESPERAR a janela antes de reportar. Medido: contar imediatamente devolve 0 mesmo quando o app
  # sobe bem — e um script que existe para PROVAR não pode dar falso alarme; ele perde a autoridade
  # na primeira vez que grita errado.
  JANELAS=0
  for _ in $(seq 1 30); do
    JANELAS=$(osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to count windows" 2>/dev/null || echo 0)
    [ "${JANELAS:-0}" -ge 1 ] && break
    sleep 0.5
  done
  echo "== instalado e REINICIADO =="
  echo "   pid=$PID  build=$BUILD_STAMP  janelas=$JANELAS"
  [ "${JANELAS:-0}" -ge 1 ] || echo "  ⚠️  subiu SEM JANELA — o app está inútil assim (File ▸ New Window)" >&2
  if [ "$PID_START" -gt 0 ] && [ "$PID_START" -lt "$BIN_MTIME" ]; then
    echo "  ⚠️  o processo é MAIS VELHO que o binário — ele está rodando o build anterior" >&2; exit 1
  fi
fi
