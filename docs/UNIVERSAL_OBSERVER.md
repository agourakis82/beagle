# Universal Observer v0.2 + v0.3 - Documentação Completa

## Visão Geral

O **Universal Observer** é o sistema de captura completa do BEAGLE, implementando vigilância total de todas as atividades do usuário para alimentar o exocórtex.

## Funcionalidades Implementadas

### v0.2 - "Ativa Tudo"

1. **File Watcher** - Monitora mudanças em:
   - `papers/drafts/`
   - `notes/`
   - `thoughts/`

2. **Clipboard Watcher** - Captura clipboard a cada 3 segundos
   - macOS: `pbpaste`
   - Linux: `xclip` ou `xsel`
   - Windows: WinAPI

3. **Screenshot Capture** - Screenshots automáticos a cada 30 segundos
   - macOS: `screencapture`
   - Linux: `gnome-screenshot` ou `scrot`
   - Windows: PowerShell

4. **Input Activity Detection** - Detecta atividade de teclado/mouse
   - Monitora a cada 500ms
   - Loga quando detecta atividade após 60s de inatividade

5. **Browser History Scraping** - Captura histórico do navegador a cada 5 minutos
   - Chrome (SQLite)
   - Firefox (SQLite)

### v0.3 - "HealthKit Edition"

6. **HealthKit Bridge** - Endpoint HTTP para receber dados de HealthKit
   - Endpoint: `POST http://localhost:8081/health`
   - Recebe: HRV, frequência cardíaca, SpO2, mindfulness minutes
   - Análise fisiológica automática via BeagleRouter

## Estrutura

```
beagle-observer/
├── src/
│   ├── lib.rs          → UniversalObserver + todas as capturas
│   └── bin/
│       └── observer.rs → Binário principal
└── examples/
    └── test_observer.rs → Exemplo de uso
```

## Uso

### Binário Principal

```bash
# Inicia surveillance total
cargo run --bin observer --package beagle-observer --release
```

### Exemplo de Teste

```bash
# Testa todas as funcionalidades por 10 segundos
cargo run --example test_observer --package beagle-observer
```

### Programático

```rust
use beagle_observer::UniversalObserver;

let mut observer = UniversalObserver::new()?;
let mut rx = observer.get_observations_receiver()
    .ok_or_else(|| anyhow::anyhow!("Falha ao obter receiver"))?;

// Inicia surveillance
observer.start_full_surveillance().await?;

// Recebe observações
while let Some(obs) = rx.recv().await {
    println!("{}: {}", obs.source, obs.content_preview);
}
```

## HealthKit Bridge (v0.3)

### Swift App (macOS/iOS)

Crie um app Swift que envia dados para o bridge:

```swift
let payload: [String: Any] = [
    "timestamp": ISO8601DateFormatter().string(from: Date()),
    "hrv_sdnn": 42.5,
    "hr": 72.0,
    "spo2": 98.0,
    "mindful_minutes_last_hour": 12.0
]

var request = URLRequest(url: URL(string: "http://localhost:8081/health")!)
request.httpMethod = "POST"
request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
URLSession.shared.dataTask(with: request).resume()
```

### Análise Fisiológica

```rust
let health_obs: Vec<Observation> = observations
    .iter()
    .filter(|o| o.source == "healthkit")
    .cloned()
    .collect();

let analysis = observer.physiological_state_analysis(&health_obs).await?;
// → Análise completa via Grok 4 Heavy
```

## Observações

Cada observação contém:

```rust
pub struct Observation {
    pub id: String,                    // UUID único
    pub timestamp: String,              // RFC3339
    pub source: String,                 // "file_change", "clipboard", etc.
    pub path: Option<String>,          // Caminho do arquivo (se aplicável)
    pub content_preview: String,       // Preview do conteúdo
    pub metadata: serde_json::Value,   // Metadados adicionais
}
```

## Diretórios

- `~/beagle-data/screenshots/` - Screenshots salvos
- `~/beagle-data/observations/` - Observações salvas (futuro)

## Requisitos

### macOS
- `screencapture` (built-in)
- `pbpaste` (built-in)
- `sqlite3` (para browser history)

### Linux
- `gnome-screenshot` ou `scrot`
- `xclip` ou `xsel`
- `sqlite3`

### Windows
- PowerShell (built-in)
- WinAPI (via winapi crate)

## Integração com BEAGLE

O Universal Observer se integra automaticamente com:
- `beagle-config` - Configuração de diretórios
- `beagle-llm` - Análise fisiológica via BeagleRouter
- `beagle-core` - Processamento de observações (futuro)

## Segurança e Privacidade

⚠️ **AVISO**: O Universal Observer captura **TUDO** que você faz. Use com cuidado:
- Dados sensíveis podem ser capturados
- Screenshots podem conter informações privadas
- Browser history é completamente acessível
- HealthKit data é altamente sensível

Recomendações:
- Use apenas em ambiente controlado
- Revise logs regularmente
- Configure filtros para dados sensíveis (futuro)

## Roadmap

- [ ] Apple Notes export
- [ ] Obsidian vault sync
- [ ] GPS location tracking
- [ ] Microphone ambient capture
- [ ] EEG data (Muse S)
- [ ] Filtros de privacidade
- [ ] Criptografia de observações sensíveis
- [ ] Dashboard web para visualização

## Referências

- [BEAGLE Architecture](./ARCHITECTURE_COHESION.md)
- [BEAGLE LLM Router](./BEAGLE_LLM_ROUTER.md)
- [HealthKit Documentation](https://developer.apple.com/documentation/healthkit)

---

**Status**: ✅ 100% Implementado e Funcional

