#!/usr/bin/env bash
set -euo pipefail

T560_HOST=10.100.100.2
T560_PASS="${T560_PASS:?defina T560_PASS no ambiente (nunca no script); prefira chave SSH}"
SCRIPT_LOCAL=/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/prove-t560-5860-two-node.sh
SCRIPT_REMOTE=/root/prove-t560-5860-two-node.sh

sshpass -p "$T560_PASS" scp -o StrictHostKeyChecking=no "$SCRIPT_LOCAL" "root@$T560_HOST:$SCRIPT_REMOTE"
sshpass -p "$T560_PASS" ssh -o StrictHostKeyChecking=no "root@$T560_HOST" "chmod +x '$SCRIPT_REMOTE' && bash '$SCRIPT_REMOTE'"
