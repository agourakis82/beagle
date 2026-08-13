#!/bin/bash
# Constrói e instala o Companion no iPhone, a partir do worktree do Companion.
#
# POR QUE ESTE SCRIPT (09-ago-2026): o anterior fazia
#   find ~/Library/Developer/Xcode/DerivedData/BeagleSuite-*/... | head -1
# Com UM checkout isso funcionava. Com dois — o principal (Mission Control, do
# outro agente) e o worktree do Companion — passam a existir duas pastas
# BeagleSuite-*, e o `head -1` escolhe uma ARBITRÁRIA. Na primeira tentativa ele
# instalou um .app de outra árvore, sem assinatura válida, e o iPhone recusou.
#
# Duas regras: caminho de DerivedData EXPLÍCITO, e o .app tem que sair de dentro
# dele — nada de adivinhar por glob.
set -euo pipefail

RAIZ="/Users/demetriosagourakis/Developer/beagle-companion/beagle-ios"
DD="$RAIZ/.derived"                       # dentro do worktree: sem ambiguidade
DEVICE="EF83DE84-8CC0-54E4-86A5-C3B6359A51E7"

cd "$RAIZ"

# Secrets.plist é gitignored (o token vazou uma vez; nunca mais no fonte).
# O worktree nasce sem ele — copia do checkout principal se faltar.
SEC="BeagleSuite/Sources/BeagleCockpit/Resources/Secrets.plist"
if [ ! -f "$SEC" ]; then
  cp "/Users/demetriosagourakis/Developer/beagle/$SEC" "$SEC" && echo "[instalar] Secrets.plist copiado"
fi

# O TOKEN DO APP PRECISA FUNCIONAR — testado, não comparado.
#
# Em 09-ago outra sessão rotacionou o token do cockpit, atualizou o Secret do
# cluster e NÃO atualizou este Secrets.plist. Compilei e instalei em cima dele
# várias vezes. Ele escrevia no companion e nada voltava — 401 antes de qualquer
# coisa — e levou um dia até alguém desconfiar do token.
#
# Falha silenciosa clássica: o app compilava, instalava, abria. Só não conversava.
#
# Testa a CAPACIDADE (este token é aceito?) em vez de comparar com uma cópia. É a
# mesma lição do proxy OAuth, onde uma guarda verificava se a variável EXISTIA e
# ela existia — com um placeholder dentro.
APP_TOKEN=$(plutil -extract COCKPIT_MOBILE_TOKEN raw -o - "$SEC" 2>/dev/null || true)
if [ -n "$APP_TOKEN" ]; then
  CODIGO=$(curl -s -o /dev/null -m 25 -w "%{http_code}" -X POST \
    -H "content-type: application/json" -H "x-cockpit-token: $APP_TOKEN" \
    --data '{"space":"personal","prompt":"ping"}' \
    https://beagle.chiuratto.ai/api/mobile/v1/companion/grounding 2>/dev/null || echo 000)
  case "$CODIGO" in
    200) echo "[instalar] token do app é aceito pelo servidor" ;;
    401|403)
      echo "[instalar] ERRO: o token deste app é RECUSADO pelo servidor (HTTP $CODIGO)."
      echo "[instalar] Instalar assim entrega um app mudo. Atualize Secrets.plist com o token vigente."
      echo "INSTALL_EXIT=1"; exit 1 ;;
    *) echo "[instalar] AVISO: não consegui testar o token (HTTP $CODIGO) — seguindo" ;;
  esac
fi

echo "[instalar] compilando (assinado)"
xcodebuild -project BeagleSuite.xcodeproj -scheme BeagleCockpit \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DD" \
  -skipPackagePluginValidation -skipMacroValidation \
  -allowProvisioningUpdates build
echo "BUILD_EXIT=$?"

APP="$DD/Build/Products/Debug-iphoneos/BeagleCockpit.app"
[ -d "$APP" ] || { echo "[instalar] ERRO: .app não encontrado em $APP"; echo "INSTALL_EXIT=1"; exit 1; }

# Verificar o ARTEFATO antes de instalar — assinatura inválida foi o que
# derrubou a primeira tentativa, e o erro só apareceu no fim do processo.
if ! codesign -v "$APP" 2>/dev/null; then
  echo "[instalar] ERRO: assinatura inválida em $APP"
  echo "INSTALL_EXIT=1"; exit 1
fi
echo "[instalar] assinatura OK — $(ls "$APP"/*.mp4 2>/dev/null | wc -l | tr -d ' ') laços, $(du -m "$APP" | cut -f1) MB"

xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "INSTALL_EXIT=$?"
