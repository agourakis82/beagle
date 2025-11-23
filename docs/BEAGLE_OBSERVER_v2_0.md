# BEAGLE Observer 2.0 - Documentação Técnica

## Visão Geral

O Observer 2.0 transforma o BEAGLE em um verdadeiro **órgão sensorial estendido**, capaz de capturar e processar métricas fisiológicas, ambientais e de clima espacial, classificando-as por severidade e integrando-as ao pipeline científico.

### Componentes Principais

- **Eventos Estruturados**: `PhysioEvent`, `EnvEvent`, `SpaceWeatherEvent`
- **Classificação de Severidade**: `Severity` (Normal/Mild/Moderate/Severe)
- **Sistema de Alerts**: Logging automático em `alerts/*.jsonl`
- **UserContext Agregado**: Contexto unificado (fisiológico, ambiental, clima espacial)
- **Integração Pipeline/Triad**: Severidades incluídas em `run_report.json`

## Eventos

### PhysioEvent

Evento fisiológico capturado de dispositivos (Apple Watch, iPhone, Vision Pro, AirPods, etc.).

**Campos principais:**
- `timestamp`: DateTime<Utc>
- `source`: String ("apple_watch_ultra", "iphone", "vision_pro", etc.)
- `session_id`: Option<String>
- **Cardiorrespiratórios**: `hrv_ms`, `heart_rate_bpm`, `spo2_percent`, `resp_rate_bpm`
- **Temperatura**: `skin_temp_c`, `body_temp_c`
- **Atividade**: `steps`, `energy_burned_kcal`, `vo2max_ml_kg_min`

**Exemplo:**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "source": "apple_watch_ultra",
  "session_id": "session_001",
  "hrv_ms": 45.0,
  "heart_rate_bpm": 72.0,
  "spo2_percent": 98.0,
  "skin_temp_c": 35.5
}
```

### EnvEvent

Evento ambiental local (GPS, altitude, pressão atmosférica, clima).

**Campos principais:**
- `timestamp`: DateTime<Utc>
- `source`: String ("iphone", "vision_pro", "home_sensor", etc.)
- `session_id`: Option<String>
- **Localização**: `latitude_deg`, `longitude_deg`, `altitude_m`
- **Ambiente**: `baro_pressure_hpa`, `ambient_temp_c`, `humidity_percent`, `uv_index`, `wind_speed_m_s`, `noise_db`

**Exemplo:**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "source": "iphone",
  "latitude_deg": -23.5505,
  "longitude_deg": -46.6333,
  "altitude_m": 760.0,
  "baro_pressure_hpa": 1013.0,
  "ambient_temp_c": 22.0,
  "humidity_percent": 65.0,
  "uv_index": 4.0
}
```

### SpaceWeatherEvent

Evento de clima espacial (Kp, fluxo de partículas, vento solar).

**Campos principais:**
- `timestamp`: DateTime<Utc>
- `source`: String ("noaa_api", "nasa", "local_cache")
- `session_id`: Option<String>
- **Índices geomagnéticos**: `kp_index`, `dst_index`
- **Vento solar**: `solar_wind_speed_km_s`, `solar_wind_density_n_cm3`
- **Partículas**: `proton_flux_pfu`, `electron_flux`
- **Radiação**: `xray_flux`, `radio_flux_sfu`

**Exemplo:**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "source": "noaa_api",
  "kp_index": 3.5,
  "solar_wind_speed_km_s": 450.0,
  "proton_flux_pfu": 5.0
}
```

## Classificação de Severidade

### Thresholds Configuráveis

Thresholds são carregados de `BeagleConfig` e podem ser ajustados via variáveis de ambiente:

**Fisiológicos:**
- `BEAGLE_HRV_LOW_MS` (default: 30.0)
- `BEAGLE_HR_TACHY_BPM` (default: 110.0)
- `BEAGLE_HR_BRADY_BPM` (default: 45.0)
- `BEAGLE_SPO2_WARNING` (default: 94.0)
- `BEAGLE_SPO2_CRITICAL` (default: 90.0)
- `BEAGLE_SKIN_TEMP_LOW_C` (default: 33.0)
- `BEAGLE_SKIN_TEMP_HIGH_C` (default: 37.5)

**Ambientais:**
- `BEAGLE_ALTITUDE_HIGH_M` (default: 2000.0)
- `BEAGLE_BARO_LOW_HPA` (default: 980.0)
- `BEAGLE_BARO_HIGH_HPA` (default: 1030.0)
- `BEAGLE_TEMP_COLD_C` (default: 10.0)
- `BEAGLE_TEMP_HEAT_C` (default: 30.0)
- `BEAGLE_UV_HIGH` (default: 6.0)

**Clima Espacial:**
- `BEAGLE_KP_STORM` (default: 5.0) - NOAA G1
- `BEAGLE_KP_SEVERE_STORM` (default: 7.0) - NOAA G3-G4
- `BEAGLE_PROTON_FLUX_HIGH_PFU` (default: 10.0)
- `BEAGLE_SOLAR_WIND_SPEED_HIGH_KM_S` (default: 600.0)

### Níveis de Severidade

- **Normal**: Valores dentro da faixa esperada
- **Mild**: Desvio ligeiro dos thresholds
- **Moderate**: Alerta - valor fora da faixa normal
- **Severe**: Evento grave - requer atenção imediata

**Nota importante**: Os thresholds são **heurísticos e configuráveis**. O BEAGLE não é um dispositivo médico e não deve ser usado para diagnóstico clínico. Estes dados são usados para modulação de comportamento do exocórtex, não para diagnóstico.

## API HTTP

### POST `/api/observer/physio`

Registra um evento fisiológico.

**Request:**
```json
{
  "source": "apple_watch_ultra",
  "session_id": "session_001",
  "hrv_ms": 45.0,
  "heart_rate_bpm": 72.0,
  "spo2_percent": 98.0,
  "resp_rate_bpm": 16.0,
  "skin_temp_c": 35.5
}
```

**Response:**
```json
{
  "status": "ok",
  "severity": "Normal",
  "hrv_level": "normal"
}
```

### POST `/api/observer/env`

Registra um evento ambiental.

**Request:**
```json
{
  "source": "iphone",
  "latitude_deg": -23.5505,
  "longitude_deg": -46.6333,
  "altitude_m": 760.0,
  "baro_pressure_hpa": 1013.0,
  "ambient_temp_c": 22.0,
  "humidity_percent": 65.0,
  "uv_index": 4.0
}
```

**Response:**
```json
{
  "status": "ok",
  "severity": "Normal"
}
```

### POST `/api/observer/space_weather`

Registra um evento de clima espacial.

**Request:**
```json
{
  "source": "noaa_api",
  "kp_index": 3.5,
  "solar_wind_speed_km_s": 450.0,
  "proton_flux_pfu": 5.0
}
```

**Response:**
```json
{
  "status": "ok",
  "severity": "Normal"
}
```

### GET `/api/observer/context`

Retorna o contexto agregado atual do usuário.

**Response:**
```json
{
  "physio": {
    "last_update": "2024-01-01T12:00:00Z",
    "hrv_level": "normal",
    "severity": "Normal",
    "heart_rate_bpm": 72.0,
    "spo2_percent": 98.0,
    "stress_index": 0.35
  },
  "env": {
    "last_update": "2024-01-01T12:00:00Z",
    "severity": "Normal",
    "location": [-23.5505, -46.6333, 760.0],
    "ambient_temp_c": 22.0,
    "humidity_percent": 65.0,
    "uv_index": 4.0,
    "summary": "Localização: -23.5505°N, -46.6333°E, 760m, Temp: 22.0°C, Umidade: 65%, UV: 4.0"
  },
  "space": {
    "last_update": "2024-01-01T12:00:00Z",
    "severity": "Normal",
    "kp_index": 3.0,
    "heliobio_risk_level": "calm"
  }
}
```

### GET `/api/observer/context/:run_id`

Retorna o contexto agregado para um run específico (atualmente retorna contexto atual).

## Sistema de Alerts

### Geração Automática

Alerts são gerados automaticamente quando a severidade agregada de um evento é **Moderate** ou **Severe**.

**Localização:**
- `BEAGLE_DATA_DIR/alerts/physio.jsonl` - Alertas fisiológicos
- `BEAGLE_DATA_DIR/alerts/env.jsonl` - Alertas ambientais
- `BEAGLE_DATA_DIR/alerts/space.jsonl` - Alertas de clima espacial

**Formato (JSONL):**
```json
{"timestamp":"2024-01-01T12:00:00Z","category":"physio","metric":"spo2_percent","severity":"Severe","value":88.0,"threshold":90.0,"session_id":"session_001","run_id":null,"message":"ALERTA CRÍTICO: spo2_percent = 88.00 (threshold: 90.00)"}
```

## Integração com Pipeline

### UserContext no Pipeline

O pipeline BEAGLE obtém o `UserContext` completo antes de gerar o draft:

```rust
let user_ctx = ctx.observer.current_user_context().await?;
```

### Run Report

O `run_report.json` inclui as severidades do Observer:

```json
{
  "run_id": "...",
  "observer": {
    "physio_severity": "Normal",
    "env_severity": "Normal",
    "space_severity": "Normal",
    "hrv_level": "normal",
    "heart_rate_bpm": 72.0,
    "spo2_percent": 98.0,
    "stress_index": 0.35,
    "heliobio_risk_level": "calm",
    "kp_index": 3.0,
    "env_summary": "..."
  }
}
```

### Triad Integration

O UserContext pode ser passado para a Triad para modulação de prompts baseada no estado fisiológico/ambiental:

```rust
// No prompt da Triad:
// "Estado fisiológico: HRV normal, FC 72bpm, SpO₂ 98%, severidade: Normal.
//  Ambiente: Localização: -23.5505°N, -46.6333°E, 760m, Temp: 22.0°C.
//  Clima espacial: Kp: 3.0, risco: calm."
```

## Testes End-to-End

### Executar Testes

```bash
cd apps/beagle-monorepo
cargo test --test observer_e2e
```

### Testes Disponíveis

1. **`test_physio_event_ingest_and_alert`**: Testa ingest de evento fisiológico com SpO₂ crítica e verifica geração de alert Severe
2. **`test_env_event_ingest_and_alert`**: Testa ingest de evento ambiental com altitude/pressão anormais e verifica geração de alert Moderate
3. **`test_space_weather_event_ingest_and_alert`**: Testa ingest de evento de clima espacial com Kp alto e verifica geração de alert
4. **`test_user_context_aggregation`**: Testa agregação de eventos em UserContext
5. **`test_observer_pipeline_integration`**: Testa integração com pipeline (verifica que severidades aparecem no contexto)
6. **`test_alert_file_creation`**: Testa criação e escrita de arquivos de alerts

## Uso Prático

### Exemplo: Captura de HRV e SpO₂ via Apple Watch

```rust
use beagle_observer::PhysioEvent;

let event = PhysioEvent {
    timestamp: chrono::Utc::now(),
    source: "apple_watch_ultra".to_string(),
    session_id: Some("workout_001".to_string()),
    hrv_ms: Some(42.5),
    heart_rate_bpm: Some(115.0),
    spo2_percent: Some(94.0), // Atenção
    resp_rate_bpm: Some(18.0),
    skin_temp_c: Some(36.2),
    body_temp_c: None,
    steps: Some(5000),
    energy_burned_kcal: Some(250.0),
    vo2max_ml_kg_min: Some(45.0),
};

let severity = observer.record_physio_event(event, None).await?;
if severity >= Severity::Moderate {
    // Alerta gerado automaticamente em alerts/physio.jsonl
    println!("Atenção: severidade fisiológica {}", severity.as_str());
}
```

### Exemplo: Consulta de Contexto para Pipeline

```rust
let user_ctx = observer.current_user_context().await?;

// Verifica severidades
if user_ctx.physio.severity >= Severity::Moderate {
    // Ajusta prompt do pipeline baseado em estado fisiológico
    println!("Estado fisiológico requer atenção: {}", user_ctx.physio.severity.as_str());
}

// Usa contexto no pipeline
let prompt = format!(
    "Pergunta: {}\n\nContexto do usuário:\n- HRV: {} (severidade: {})\n- Ambiente: {}\n- Clima espacial: {}",
    question,
    user_ctx.physio.hrv_level.as_deref().unwrap_or("N/A"),
    user_ctx.physio.severity.as_str(),
    user_ctx.env.summary.as_deref().unwrap_or("N/A"),
    user_ctx.space.heliobio_risk_level.as_deref().unwrap_or("N/A"),
);
```

## Notas Importantes

1. **Não é um dispositivo médico**: Os thresholds são heurísticos e não devem ser usados para diagnóstico clínico.
2. **Configuração via env vars**: Thresholds podem ser ajustados via variáveis de ambiente para diferentes contextos de uso.
3. **Armazenamento**: Eventos são mantidos em memória (últimos 1000 de cada tipo). Alerts são persistidos em `alerts/*.jsonl`.
4. **Integração**: O Observer está totalmente integrado ao pipeline e Triad, fornecendo contexto contextualizado para modulação de comportamento do exocórtex.

## Próximos Passos

- **Visualização**: Dashboard web para visualização de métricas e alerts em tempo real
- **Machine Learning**: Modelos para predição de estado cognitivo baseado em métricas fisiológicas
- **Automação**: Ações automáticas baseadas em severidade (ex.: pausar pipeline se SpO₂ crítica)
- **Integração com HealthKit/Google Fit**: Captura automática de métricas de dispositivos móveis

---

**BEAGLE Observer 2.0** - Órgão sensorial estendido do exocórtex científico 🧠📊

