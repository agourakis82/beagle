#!/usr/bin/env bash
# Register the Beagle Personal Telegram webhook.
#
# Requires TELEGRAM_BOT_TOKEN (from @BotFather) and TELEGRAM_WEBHOOK_SECRET (a high-entropy
# random string, NOT the bot token). The bot token NEVER appears in the webhook URL — Telegram
# echoes the secret back in the `X-Telegram-Bot-Api-Secret-Token` header on every update, and
# the server verifies that. This keeps the token out of access logs / proxies.
set -euo pipefail

TOKEN="${TELEGRAM_BOT_TOKEN:-}"
SECRET="${TELEGRAM_WEBHOOK_SECRET:-}"
PUBLIC_BASE="${TELEGRAM_WEBHOOK_BASE:-https://beagle.chiuratto.ai}"

if [[ -z "$TOKEN" || "$TOKEN" == "REPLACE_WITH_BOT_TOKEN" ]]; then
  echo "error: export TELEGRAM_BOT_TOKEN with the real @BotFather token first" >&2
  exit 1
fi
if [[ -z "$SECRET" ]]; then
  echo "error: export TELEGRAM_WEBHOOK_SECRET (a random string; must match the server env)" >&2
  echo "       e.g. export TELEGRAM_WEBHOOK_SECRET=\$(openssl rand -hex 32)" >&2
  exit 1
fi

WEBHOOK_URL="${PUBLIC_BASE}/api/webhooks/telegram"
echo "Setting webhook: ${WEBHOOK_URL} (auth via secret header, not the URL)"

curl -fsS "https://api.telegram.org/bot${TOKEN}/setWebhook" \
  --data-urlencode "url=${WEBHOOK_URL}" \
  --data-urlencode "secret_token=${SECRET}"

echo
curl -fsS "https://api.telegram.org/bot${TOKEN}/getWebhookInfo"
echo
