## Update: Integração Vertex AI

- **Data**: `$(date +%Y-%m-%d)` <!-- substitua manualmente ao publicar -->

### Concluído ✅

- Configuração do Google Cloud SDK e autenticação via Application Default Credentials.
- Vertex AI API habilitada para o projeto `pcs-helio`.
- Crate `beagle-llm` com `VertexAIClient` (Claude 3.5 Haiku, Sonnet 4.5 e Sonnet 4).
- Endpoint `POST /api/v1/chat` operacional no `beagle-server`.
- Roteamento de modelos: Haiku (default), Sonnet 4.5 (`model=sonnet-4.5`), Sonnet 4 (`model=sonnet-4`).
- Script `scripts/benchmark_vertex.sh` para medições de latência/custo.

### Modelos Disponíveis

| Modelo | Uso padrão | Custo estimado (1M tokens in/out) | Latência (estimada) |
|--------|------------|------------------------------------|---------------------|
| Claude Haiku 4.5 | Primário (≈80%) | US$ 0.25 / 1M (entrada) · US$ 1.25 / 1M (saída) | 2–4 s |
| Claude Sonnet 4.5 | Premium (≈15%) | US$ 3 / 1M · US$ 15 / 1M | 8–12 s |
| Claude Sonnet 4 | Fallback (≈5%) | US$ 3 / 1M · US$ 15 / 1M | 6–10 s |

### Endpoints

- `GET /health` – status do servidor.
- `GET /api/v1/nodes` – inventário de nós.
- `POST /api/v1/chat` – inferência LLM (Vertex AI).
- `GET /swagger-ui` – documentação interativa (OpenAPI 3.1).

### Exemplos de Uso

```bash
# Haiku 4.5 (default)
curl -X POST http://localhost:3000/api/v1/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Resuma o status da plataforma Beagle."}'

# Sonnet 4.5 (explicitamente)
curl -X POST http://localhost:3000/api/v1/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Explique a bioética da IA generativa.", "model": "sonnet-4.5"}'
```

### Projeção de Custo Mensal (créditos Google Cloud)

- Créditos gratuitos Vertex AI: **US$ 300 / 12 meses**.
- 3.000 requisições/mês (100/dia) com Haiku → ~US$ 6.
- Estimativa conservadora (mix 80/15/5) → < US$ 45/mês.
- Dentro da reserva gratuita: ✅.

### Próximos Passos

- [ ] Engine de Personalidade (Layer 6.5) com prompts contextuais.
- [ ] Persistência de contexto multi-turn.
- [ ] Streaming de respostas via SSE/H3.
- [ ] Integração com Qdrant para recuperação semântica.

