# Contrato HTTP Minimalista para iOS/Watch

Este documento define o contrato HTTP simplificado para integração de apps iOS e Apple Watch com o BEAGLE core server.

## Base URL

Por padrão: `http://localhost:8080` (configurável via `BEAGLE_CORE_URL`)

## Endpoints Essenciais

### 1. Health Check

```
GET /health
```

**Response:**
```json
{
  "status": "ok",
  "profile": "dev",
  "safe_mode": true,
  "data_dir": "/path/to/data",
  "llm_heavy_enabled": false,
  "xai_api_key_present": true
}
```

### 2. Enviar Dados Fisiológicos (HealthKit)

```
POST /api/observer/physio
Content-Type: application/json
```

**Request:**
```json
{
  "timestamp": "2025-01-20T10:30:00Z",  // opcional, ISO 8601
  "source": "ios_healthkit",             // obrigatório
  "hrv_ms": 55.2,                        // obrigatório
  "heart_rate_bpm": 70.5,                // opcional
  "session_id": "abc-123"                // opcional
}
```

**Response:**
```json
{
  "status": "ok",
  "hrv_level": "normal"                  // "low" | "normal" | "high"
}
```

### 3. Iniciar Pipeline

```
POST /api/pipeline/start
Content-Type: application/json
```

**Request:**
```json
{
  "question": "Qual o papel da entropia curva em scaffolds biológicos?",
  "with_triad": false                    // opcional, default: false
}
```

**Response:**
```json
{
  "run_id": "uuid-v4-string",
  "status": "created"
}
```

### 4. Verificar Status do Pipeline

```
GET /api/pipeline/status/{run_id}
```

**Response:**
```json
{
  "run_id": "uuid-v4-string",
  "status": "running",                   // "created" | "running" | "done" | "error" | "triad_running" | "triad_done"
  "question": "Qual o papel..."
}
```

### 5. Obter Artefatos do Run

```
GET /api/run/{run_id}/artifacts
```

**Response:**
```json
{
  "run_id": "uuid-v4-string",
  "draft_md": "/path/to/draft.md",       // opcional
  "draft_pdf": "/path/to/draft.pdf",     // opcional
  "run_report": "/path/to/run_report.json", // opcional
  "triad_final_md": "/path/to/triad_final.md" // opcional
}
```

### 6. Listar Runs Recentes

```
GET /api/runs/recent?limit=10
```

**Response:**
```json
[
  {
    "run_id": "uuid-1",
    "status": "done",
    "question": "Pergunta 1"
  },
  {
    "run_id": "uuid-2",
    "status": "running",
    "question": "Pergunta 2"
  }
]
```

### 7. Obter Contexto do Observer (Timeline)

```
GET /api/observer/context/{run_id}
```

**Response:**
```json
{
  "run_id": "uuid-v4-string",
  "observations": [
    {
      "id": "obs-id",
      "timestamp": "2025-01-20T10:30:00Z",
      "source": "pipeline_physio",
      "path": null,
      "content_preview": "Estado fisiológico: HRV 55.2ms (normal)",
      "metadata": {
        "hrv_ms": 55.2,
        "hrv_level": "normal"
      }
    }
  ],
  "count": 1
}
```

## Códigos de Status HTTP

- `200 OK`: Sucesso
- `400 Bad Request`: Request inválido
- `404 Not Found`: Run/job não encontrado
- `500 Internal Server Error`: Erro do servidor

## Autenticação

Atualmente não há autenticação. Em produção, adicionar:
- API Key via header `X-API-Key`
- Ou JWT token via `Authorization: Bearer <token>`

## Rate Limiting

Não implementado ainda. Em produção, considerar:
- 100 requests/minuto por IP
- 10 pipeline starts/hora por IP

## Exemplo Swift (URLSession)

```swift
func sendHRV(hrv: Double, heartRate: Double?) {
    let url = URL(string: "http://localhost:8080/api/observer/physio")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let body: [String: Any] = [
        "source": "ios_healthkit",
        "hrv_ms": hrv,
        "heart_rate_bpm": heartRate as Any,
        "timestamp": ISO8601DateFormatter().string(from: Date())
    ]
    
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hrvLevel = json["hrv_level"] as? String {
            print("HRV level: \(hrvLevel)")
        }
    }.resume()
}
```

## Notas

- Todos os timestamps são ISO 8601 (UTC)
- Todos os paths são relativos a `BEAGLE_DATA_DIR`
- O endpoint `/api/observer/physio` classifica automaticamente HRV em "low" | "normal" | "high"
- Thresholds configuráveis via `BEAGLE_HRV_LOW_THRESHOLD` e `BEAGLE_HRV_HIGH_THRESHOLD` (default: 30ms e 70ms)

