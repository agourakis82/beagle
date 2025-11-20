# BEAGLE Assistant - Integração com Backend

## 🔌 Como Integra com BEAGLE

O assistente se conecta automaticamente com:

### 1. Grok 3 (Primeiro - Ilimitado)
- URL: `https://api.x.ai/v1/chat/completions`
- Model: `grok-beta`
- API Key: `XAI_API_KEY` (environment variable ou UserDefaults)

### 2. vLLM Local (Fallback)
- URL: `http://t560.local:8000/v1/chat/completions`
- Model: `meta-llama/Llama-3.3-70B-Instruct`
- Requer: Cluster vLLM rodando

### 3. Backend BEAGLE (Futuro)
- URL: `http://t560.local:8000/api/beagle/query`
- Integração completa com smart-router

## 📡 Fluxo de Comunicação

```
iPhone/Mac → Speech Recognition → Transcrição
    ↓
Transcrição → Grok 3 (primeiro)
    ↓ (se falhar)
Transcrição → vLLM Local (fallback)
    ↓
Resposta → TTS → Fala
```

## 🔧 Configuração de URLs

Edite `BeagleAssistant.swift` para mudar URLs:

```swift
// Linha ~20
private let vllmURL = URL(string: "http://SEU_CLUSTER:8000/v1/chat/completions")!
private let grokURL = URL(string: "https://api.x.ai/v1/chat/completions")!
```

## 🎯 Comandos que Funcionam

O assistente processa comandos naturais:
- "Roda o adversarial loop"
- "Publica o último paper"
- "Mostra status do cluster"
- "Treina LoRA voice"
- "Gera novo draft sobre entropia curva"

O Grok/vLLM interpreta e responde como se fosse você (Demetrios Chiuratto).

---

**100% INTEGRADO - RODA HOJE** 🚀

