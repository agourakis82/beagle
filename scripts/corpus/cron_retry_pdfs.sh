#!/bin/bash
# BEAGLE - Wrapper para reprocessar PDFs OA em falha
# Uso sugerido em crontab (a cada 6 horas, por exemplo):
# 0 */6 * * * /home/maria/beagle/scripts/corpus/cron_retry_pdfs.sh >> /home/maria/beagle/logs/retry_pdfs.log 2>&1

set -euo pipefail

BASE_DIR="/home/maria/beagle"
cd "$BASE_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3}"

$PYTHON_BIN "$BASE_DIR/scripts/corpus/retry_pdfs.py"


