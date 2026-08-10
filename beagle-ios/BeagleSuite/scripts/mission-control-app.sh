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

cat > "$DEST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <!-- Escuro por decisão: o Mission Control é uma tela de plantão, e o BeagleTheme resolve por
       aparência. Sem isto, um Mac em modo claro renderizava texto claro sobre fundo claro. -->
  <key>NSRequiresAquaSystemAppearance</key><false/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$DEST/Contents/PkgInfo"

# Assinatura ad-hoc: sem ela o macOS pede permissão a cada execução e o ícone às vezes não
# atualiza no Dock. Ad-hoc basta para uso local; distribuir exigiria conta e notarização.
codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || echo "  (codesign ad-hoc falhou — o app roda, mas o Dock pode teimar no ícone)"

# O Dock cacheia ícone por caminho; sem isto o app novo aparece com o ícone genérico.
touch "$DEST"

echo "== pronto: $DEST =="
if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$DEST" "/Applications/$APP_NAME.app"
  echo "== instalado em /Applications =="
fi
