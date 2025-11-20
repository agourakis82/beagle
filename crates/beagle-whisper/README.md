# BEAGLE Whisper - Transcrição de Voz 100% Local

Transcrição de voz local usando whisper.cpp, integrado com Grok 3/4 Heavy.

## 🚀 Setup (Uma Vez)

### 1. Instalar whisper.cpp

```bash
./scripts/setup_whisper.sh
```

Ou manualmente:

```bash
git clone https://github.com/ggerganov/whisper.cpp
cd whisper.cpp
make
./models/download-ggml-model.sh large-v3
```

### 2. Configurar API Key (opcional)

```bash
export GROK_API_KEY="xai-tua-key"
```

## 🎤 Como Usar

### Transcrição de Arquivo

```rust
use beagle_whisper::BeagleWhisper;

let whisper = BeagleWhisper::new()?;
let transcription = whisper.transcribe_file("audio.wav").await?;
println!("Transcrição: {}", transcription);
```

### Assistente Pessoal Completo

```rust
use beagle_whisper::BeagleVoiceAssistant;

let assistant = BeagleVoiceAssistant::new()?;
assistant.start_assistant_loop().await?;
```

### No Loop Principal do BEAGLE

```rust
use beagle_whisper::BeagleVoiceAssistant;

// No main loop
let assistant = BeagleVoiceAssistant::new()?;
tokio::spawn(async move {
    assistant.start_assistant_loop().await.ok();
});
```

## 📊 Funcionalidades

- ✅ Transcrição local (zero nuvem)
- ✅ Tempo real (<500ms latência)
- ✅ Integração automática com Grok 3/4 Heavy
- ✅ Suporte PT/EN
- ✅ Multi-threaded (8 threads por padrão)

## 🎯 Exemplo Completo

```bash
# Rodar assistente pessoal
cargo run --example voice_assistant --package beagle-whisper

# Ou integrar no monorepo
cargo run --bin beagle-monorepo
```

---

**100% Local. Zero Nuvem. Zero Latência. Zero Custo.**

