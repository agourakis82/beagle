import { defineConfig } from "vite";
import solidPlugin from "vite-plugin-solid";

export default defineConfig({
  plugins: [solidPlugin()],
  server: {
    port: 4173,
    proxy: {
      "/api": {
        target: "http://127.0.0.1:4370",
        changeOrigin: true
      },
      "/ws": {
        target: "ws://127.0.0.1:4370",
        ws: true
      }
    }
  },
  build: {
    target: "esnext"
  }
});
