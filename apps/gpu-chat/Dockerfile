FROM node:22-slim AS web-build
WORKDIR /app/web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

FROM node:22-slim AS server-build
WORKDIR /app/server
COPY server/package.json server/package-lock.json ./
RUN npm ci
COPY server/ ./
RUN npm run build

FROM node:22-slim
WORKDIR /app
COPY --from=server-build /app/server/package.json ./server/package.json
RUN cd server && npm install --omit=dev
COPY --from=server-build /app/server/dist ./server/dist
COPY --from=web-build /app/web/dist ./web/dist

ENV PORT=8090
ENV GPU_CHAT_DB_PATH=/app/data/gpu-chat.db
ENV GPU_CHAT_WEB_DIST=/app/web/dist
ENV LITELLM_BASE_URL=http://litellm:4000

EXPOSE 8090
CMD ["node", "server/dist/index.js"]
