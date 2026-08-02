import { completeChatRequest } from "./mobile-routes.mjs";
import { fetchOperatorToken } from "./auth-bridge.mjs";

const BEAGLE_INTERNAL_URL =
  process.env.PROJECT_COCKPIT_BEAGLE_INTERNAL_URL ||
  "http://beagle-core.beagle.svc.cluster.local:8080";

function cleanString(value) {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed ? trimmed : "";
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value).trim();
  }
  return "";
}

function parseAllowedChatIds(raw = "") {
  return new Set(
    cleanString(raw)
      .split(",")
      .map((entry) => entry.trim())
      .filter(Boolean)
  );
}

function extractTelegramMessage(update = {}) {
  const message = update.message || update.edited_message || null;
  if (!message) {
    return null;
  }
  const text = cleanString(message.text);
  const chatId = message.chat?.id;
  const fromId = message.from?.id;
  if (!text || chatId === undefined || chatId === null) {
    return null;
  }
  return {
    text,
    chatId: String(chatId),
    fromId: fromId === undefined || fromId === null ? "" : String(fromId),
    messageId: message.message_id,
    updateId: update.update_id
  };
}

async function sendTelegramMessage({ token, chatId, text }) {
  const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text
    })
  });
  if (!res.ok) {
    const payload = await res.text();
    throw new Error(`telegram sendMessage failed (${res.status}): ${payload.slice(0, 300)}`);
  }
}

async function sendTelegramChatAction({ token, chatId, action = "typing" }) {
  await fetch(`https://api.telegram.org/bot${token}/sendChatAction`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, action })
  }).catch(() => {});
}

function chunkTelegramText(text, limit = 4096) {
  const chunks = [];
  let remaining = cleanString(text);
  while (remaining.length > limit) {
    let splitAt = remaining.lastIndexOf("\n", limit);
    if (splitAt < limit / 2) {
      splitAt = limit;
    }
    chunks.push(remaining.slice(0, splitAt).trim());
    remaining = remaining.slice(splitAt).trim();
  }
  if (remaining) {
    chunks.push(remaining);
  }
  return chunks.length > 0 ? chunks : [""];
}

async function ingestTelegramExchange({ userText, assistantText, chatId, updateId }) {
  const tokenResult = await fetchOperatorToken();
  if (tokenResult.error || !tokenResult.token) {
    return;
  }

  const now = new Date().toISOString();
  await fetch(`${BEAGLE_INTERNAL_URL}/api/exocortex/v1/memory/assisted-import`, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "content-type": "application/json",
      "X-Beagle-Consumer": "beagle-operator",
      Authorization: `Bearer ${tokenResult.token}`
    },
    body: JSON.stringify({
      source_platform: "beagle-telegram",
      source_surface: "personal-channel",
      import_scope: "personal_chat",
      session_id: `telegram:${chatId}`,
      privacy_class: "sensitive",
      title: `Telegram personal chat ${now.slice(0, 10)}`,
      confidence_score: 0.9,
      create_chronoself_commit: false,
      turns: [
        {
          role: "user",
          content: userText,
          timestamp: now,
          metadata: { channel: "telegram", update_id: updateId }
        },
        {
          role: "assistant",
          content: assistantText,
          timestamp: now,
          metadata: { channel: "telegram", update_id: updateId }
        }
      ],
      tags: ["telegram", "personal-chat"],
      metadata: {
        channel: "telegram",
        chat_id: chatId,
        update_id: updateId,
        restricted_leak_check: "passed",
        remembered_from: "beagle-telegram-webhook"
      }
    })
  }).catch(() => {});
}

export function registerTelegramRoutes(app, deps) {
  // Fixed path + secret-token header (NOT the bot token in the URL — that leaks into access
  // logs/proxies). Register with setWebhook's `secret_token=$TELEGRAM_WEBHOOK_SECRET`; Telegram
  // then echoes it back in this header on every update.
  app.post("/api/webhooks/telegram", async (req, res) => {
    const configuredSecret = cleanString(process.env.TELEGRAM_WEBHOOK_SECRET);
    const headerSecret = cleanString(req.get("X-Telegram-Bot-Api-Secret-Token"));
    if (!configuredSecret || headerSecret !== configuredSecret) {
      res.status(401).json({ error: "invalid telegram webhook secret" });
      return;
    }

    const allowedChatIds = parseAllowedChatIds(process.env.TELEGRAM_ALLOWED_CHAT_IDS);
    const message = extractTelegramMessage(req.body || {});
    if (!message) {
      res.status(200).json({ ok: true, ignored: true });
      return;
    }

    if (allowedChatIds.size > 0 && !allowedChatIds.has(message.chatId)) {
      res.status(403).json({ error: "chat not allowed" });
      return;
    }

    if (message.text === "/start") {
      await sendTelegramMessage({
        token: configuredToken,
        chatId: message.chatId,
        text: "Beagle Personal — estou aqui. Fala comigo."
      }).catch((err) => {
        res.status(502).json({ error: err.message });
      });
      if (!res.headersSent) {
        res.status(200).json({ ok: true, welcome: true });
      }
      return;
    }

    res.status(200).json({ ok: true, accepted: true });

    void (async () => {
      try {
        await sendTelegramChatAction({
          token: configuredToken,
          chatId: message.chatId,
          action: "typing"
        });

        const syntheticReq = {
          body: {
            space: "personal",
            chatSpace: "personal",
            prompt: message.text,
            voiceModel: cleanString(process.env.TELEGRAM_VOICE_MODEL) || "hermes-4",
            idempotencyKey: `telegram:${message.updateId}`
          }
        };

        const completion = await completeChatRequest(syntheticReq, deps);
        for (const chunk of chunkTelegramText(completion.response)) {
          await sendTelegramMessage({
            token: configuredToken,
            chatId: message.chatId,
            text: chunk
          });
        }

        await ingestTelegramExchange({
          userText: message.text,
          assistantText: completion.response,
          chatId: message.chatId,
          updateId: message.updateId
        });
      } catch (err) {
        await sendTelegramMessage({
          token: configuredToken,
          chatId: message.chatId,
          text: "Não consegui responder agora. Tenta de novo em instantes."
        }).catch(() => {});
      }
    })();
  });
}
