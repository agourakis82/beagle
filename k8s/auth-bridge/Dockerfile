# Minimal auth-bridge image. Pure Node — talks to the Kubernetes API
# directly via the in-pod service-account token. No kubectl needed,
# 30MB smaller image, no subprocess memory spike.
FROM node:20-bookworm-slim

WORKDIR /app
COPY server.mjs ./server.mjs

EXPOSE 7070
USER node
CMD ["node", "server.mjs"]
