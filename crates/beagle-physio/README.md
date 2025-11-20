# BEAGLE Physiological Metrics

Integração de métricas fisiológicas (HRV, Heart Rate, Sleep) do Apple Watch no loop metacognitivo do BEAGLE.

## Funcionalidades

- **HRV Integration**: Recebe HRV do Apple Watch via HTTP
- **Flow State Detection**: Detecta FLOW, STRESS, NORMAL baseado em HRV
- **Speed Control**: Ajusta velocidade do loop adversarial automaticamente
- **Metacognitive Integration**: Integra com `beagle-metacog`

## Estados Fisiológicos

- **FLOW** (HRV > 80ms): Loop acelera 50% (multiplicador 1.5x)
- **STRESS** (HRV < 50ms): Loop desacelera 30% (multiplicador 0.7x)
- **NORMAL** (50-80ms): Loop normal (multiplicador 1.0x)

## Uso no Loop

```rust
use beagle_physio::speed_control;

// No loop adversarial:
let base_delay = 1000; // 1 segundo
let adjusted_delay = speed_control::get_adjusted_delay(base_delay);

// Usa o delay ajustado
tokio::time::sleep(Duration::from_millis(adjusted_delay)).await;
```

## Endpoint HTTP

O endpoint `/api/hrv` recebe métricas do Apple Watch:

```bash
POST http://t560.local:9000/api/hrv
Content-Type: application/json

{
  "hrv": 75.5,
  "state": "FLOW",
  "timestamp": 1234567890.0
}
```

## Speed Control API

```rust
// Obtém multiplicador atual
let multiplier = speed_control::get_global_speed_multiplier();

// Define multiplicador (normalmente feito pelo endpoint HRV)
speed_control::set_global_speed_multiplier(1.5);

// Calcula delay ajustado
let delay = speed_control::get_adjusted_delay(1000); // base: 1000ms
```

## Status

✅ Módulo criado
✅ Endpoint HTTP integrado
✅ Speed control implementado
✅ Integração com loop metacognitivo

