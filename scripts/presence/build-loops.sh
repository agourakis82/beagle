#!/usr/bin/env bash
#
# build-loops.sh — pipeline determinístico dos laços da presença primordial.
#
# RODA NO t560 (não no Mac). Lê o material cru do brainstorm, produz laços HEVC
# fechados (xfade) + poster frame PNG, e MEDE o resultado. Nada de olho: os
# critérios de aceite são duração e SSIM primeiro↔último frame.
#
# A saída vai para um diretório NEUTRO (/data/presence-out por padrão) — o
# checkout do t560 está em `reconcile/unify-beagle`, e o app vive na branch
# `integration/ios-physiome-merge` que só existe no Mac. Transferir com:
#
#   scp /data/presence-out/*.{mp4,png} \
#     mac:/Users/demetriosagourakis/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/Resources/Presence/
#
# e commitar LÁ. Só o material CONVERTIDO entra em git; a fonte crua fica aqui.
#
# Por que cada coisa:
#   -an                     remove a faixa AAC na origem. O app disputa
#                           AVAudioSession com SpeechRecognizer/Moshi; um player
#                           com trilha pode roubar a sessão de captura.
#   -map 0:v:0              descarta o stream mjpeg de capa (attached pic).
#   xfade de 1s             o material NÃO é laço: SSIM primeiro↔último frame no
#                           cru é 0.39 (ouvindo) a 0.81 (adormecido). Um corte de
#                           volta ao início seria um salto visível.
#   poster em PNG           o ffmpeg do t560 NÃO tem muxer HEIF/HEIC
#                           ("Unable to choose an output format for poster.heic").
#                           PNG de 1 frame 640px custa dezenas de KB e não
#                           adiciona dependência. Converter para HEIC no Mac com
#                           `sips -s format heic` se algum dia importar.
#
set -euo pipefail

SRC="${SRC:-/home/devsounio/beagle/.superpowers/brainstorm/2849121-1785718706/content}"
OUT="${OUT:-/data/presence-out}"
CRF="${CRF:-30}"
SCALE_W="${SCALE_W:-640}"
FPS="${FPS:-20}"
XFADE="${XFADE:-1}"          # segundos de fechamento do laço
LOOPS=("${@:-}")
if [ -z "${LOOPS[0]:-}" ]; then
  LOOPS=(st-adormecido st-atento st-ouvindo st-pensando)
fi

mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# SSIM entre o primeiro e o último frame de um mp4. Imprime só o valor All.
ssim_head_tail() {
  local mp4="$1"
  local dur first last
  dur="$(ffprobe -v error -select_streams v:0 -show_entries format=duration -of csv=p=0 "$mp4")"
  first="$TMP/first.png"; last="$TMP/last.png"
  ffmpeg -v error -y -i "$mp4" -frames:v 1 "$first"
  # -sseof -1 pega o último GOP; o último frame é o -update final
  ffmpeg -v error -y -sseof -0.2 -i "$mp4" -update 1 "$last"
  ffmpeg -v error -i "$first" -i "$last" -lavfi ssim=stats_file=- -f null - 2>/dev/null \
    | sed -n 's/.*All:\([0-9.]*\).*/\1/p' | head -1
}

printf '%-18s %8s %10s %8s %8s\n' laço dur_s tamanho ssim_cru ssim_out

for name in "${LOOPS[@]}"; do
  in="$SRC/$name.mp4"
  [ -f "$in" ] || { echo "FALTA: $in" >&2; exit 1; }

  dur="$(ffprobe -v error -select_streams v:0 -show_entries format=duration -of csv=p=0 "$in")"
  # fim do corpo e início da cauda
  body_end="$(awk -v d="$dur" -v x="$XFADE" 'BEGIN{printf "%.4f", d - x}')"

  out="$OUT/$name.mp4"
  ffmpeg -v error -y -i "$in" \
    -filter_complex "\
[0:v]scale=${SCALE_W}:-2:flags=lanczos,fps=${FPS},format=yuv420p,setsar=1,split=3[h][m][t];\
[h]trim=start=0:end=${XFADE},setpts=PTS-STARTPTS,fps=${FPS}[head];\
[m]trim=start=${XFADE}:end=${body_end},setpts=PTS-STARTPTS,fps=${FPS}[mid];\
[t]trim=start=${body_end},setpts=PTS-STARTPTS,fps=${FPS}[tail];\
[tail][head]xfade=transition=fade:duration=${XFADE}:offset=0[blend];\
[mid][blend]concat=n=2:v=1:a=0[v]" \
    -map "[v]" -an \
    -c:v libx265 -crf "$CRF" -preset slow -tag:v hvc1 -pix_fmt yuv420p \
    -movflags +faststart \
    "$out"

  # poster frame estático (Reduce Motion / Low Power Mode)
  ffmpeg -v error -y -i "$out" -frames:v 1 "$OUT/$name.png"

  # medidas
  odur="$(ffprobe -v error -select_streams v:0 -show_entries format=duration -of csv=p=0 "$out")"
  osize="$(du -h "$out" | cut -f1)"
  s_in="$(ssim_head_tail "$in")"
  s_out="$(ssim_head_tail "$out")"
  printf '%-18s %8.3f %10s %8s %8s\n' "$name" "$odur" "$osize" "${s_in:-?}" "${s_out:-?}"

  # critérios de aceite MEDIDOS
  awk -v d="$odur" -v s="${s_out:-0}" -v n="$name" 'BEGIN{
    if (d < 6.8 || d > 7.3) { printf "FALHA %s: duração %.3f fora de ~7.05s\n", n, d > "/dev/stderr"; exit 1 }
    if (s < 0.85)           { printf "FALHA %s: SSIM head↔tail %.3f < 0.85\n", n, s > "/dev/stderr"; exit 1 }
  }'
done

echo
echo "OK — saída em $OUT"
ls -la "$OUT"
