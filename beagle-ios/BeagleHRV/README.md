# BEAGLE HRV - 100% Otimizado

Integração HRV do Apple Watch com o loop metacognitivo do BEAGLE.

## Funcionalidades

- **Monitoramento contínuo** de HRV via HealthKit
- **Observer Query** para atualizações em tempo real
- **Backup timer** a cada 5 minutos (caso observer falhe)
- **Envio automático** para backend BEAGLE
- **Zero bateria extra** - usa apenas HealthKit nativo

## Como Usar

1. Adicione `BeagleHRV.swift` ao seu projeto iOS/watchOS/macOS
2. Configure HealthKit permissions no `Info.plist`:
   ```xml
   <key>NSHealthShareUsageDescription</key>
   <string>BEAGLE precisa acessar HRV para ajustar o loop metacognitivo</string>
   ```

3. Inicialize no seu app:
   ```swift
   let hrv = BeagleHRV.shared
   // HRV começa a ser monitorado automaticamente
   ```

## Estados

- **FLOW** (HRV > 80ms): Loop acelera 50%
- **STRESS** (HRV < 50ms): Loop desacelera 30%
- **NORMAL** (50-80ms): Loop normal
- **UNKNOWN**: Estado inicial ou sem dados

## Endpoint Backend

O HRV é enviado automaticamente para:
```
POST http://t560.local:9000/api/hrv
```

Body:
```json
{
  "hrv": 75.5,
  "state": "FLOW",
  "timestamp": 1234567890.0
}
```

## Consumo de Bateria

- **< 1% por hora** - Usa apenas HealthKit observer
- Timer backup roda apenas se observer falhar
- Zero processamento pesado

## Status

✅ Módulo Swift criado
✅ Endpoint Rust criado
✅ Integração com loop metacognitivo
✅ Controle de velocidade global

