# BEAGLE Assistant - Setup Completo

## 🚀 Passo a Passo para Rodar HOJE

### 1. Criar Projeto no Xcode

```bash
# Abre Xcode
open -a Xcode

# Cria novo projeto:
# - File → New → Project
# - iOS → App
# - Nome: BeagleAssistant
# - Interface: SwiftUI
# - Language: Swift
# - Minimum: iOS 17.0
```

### 2. Substituir Arquivos

Substitua os arquivos gerados pelos do diretório `beagle-ios/BeagleAssistant/`:
- `BeagleAssistantApp.swift` → App principal
- `BeagleAssistant.swift` → Cérebro do assistente
- `ContentView.swift` → UI
- `Info.plist` → Permissões

### 3. Configurar Permissões

No Xcode:
1. Selecione o projeto → Target → Info
2. Adicione as keys do `Info.plist`:
   - `NSSpeechRecognitionUsageDescription`
   - `NSMicrophoneUsageDescription`
   - `NSLocalNetworkUsageDescription`

### 4. Configurar API Key (Opcional)

**Opção 1: Environment Variable**
```bash
# No Xcode: Edit Scheme → Run → Arguments → Environment Variables
XAI_API_KEY = xai-tua-key-aqui
```

**Opção 2: Código**
```swift
// Em BeagleAssistant.swift, linha ~60:
private let grokAPIKey = "xai-tua-key-aqui"  // Ou lê de UserDefaults
```

### 5. Rodar

- **iPhone**: Conecta dispositivo → Run (⌘R)
- **Mac**: Run direto (⌘R)
- **Simulador**: Funciona, mas microfone pode não funcionar

## ✅ Teste Rápido

1. Abre o app
2. Autoriza microfone + speech recognition
3. Fala: "Olá BEAGLE"
4. Deve transcrever e responder

## 🔧 Troubleshooting

### Erro: "Speech recognizer not available"
- Verifique permissões em Settings → Privacy → Speech Recognition

### Erro: "Network error"
- Verifique se vLLM está rodando: `curl http://t560.local:8000/health`
- Ou configure Grok API key

### Erro: "Cannot find type 'BeagleAssistant'"
- Verifique que todos os arquivos estão no target
- Build (⌘B) para verificar

---

**100% REAL - RODA HOJE** 🚀
