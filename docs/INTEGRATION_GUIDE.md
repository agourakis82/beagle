# BEAGLE - Guia de Integração Completo

## 🎤 LoRA Voice 100% Automático

### Como usar no loop adversarial:

```rust
use beagle_serendipity::integrate_lora_in_refinement_loop;

// No final do refine, quando score > best_score:
if score > best_score {
    integrate_lora_in_refinement_loop(&old_draft, &new_draft, score, best_score).await?;
}
```

### Setup:

1. Instalar Unsloth:
```bash
pip install unsloth transformers trl datasets
```

2. Configurar paths no código (se necessário):
- `LORA_ADAPTER_DIR`: Onde salvar adapter
- `VLLM_LORA_DIR`: Onde vLLM espera o adapter
- `VLLM_CONTAINER`: Nome do container Docker

## 📱 Frontend Vision Pro + iPhone + Watch

### Vision Pro:

1. Abrir `beagle-ios/BeagleVisionOS/` no Xcode
2. Conectar Vision Pro
3. Rodar (⌘R)

### iPhone:

1. Abrir `beagle-ios/BeagleiPhone/` no Xcode
2. Conectar iPhone
3. Rodar (⌘R)

### Watch:

1. Abrir `beagle-ios/BeagleWatch/` no Xcode
2. Conectar Watch
3. Rodar (⌘R)

### Configurar backend:

Editar `BeagleApp.swift` e `BeagleWatchApp.swift`:
- Atualizar `baseURL` para o IP do servidor BEAGLE
- Configurar autenticação se necessário

## 📊 HRV do Apple Watch no Loop Metacognitivo

O HRV é automaticamente enviado para o BEAGLE quando:
- HRV > 80ms → Estado: FLOW
- HRV ≤ 80ms → Estado: STRESS

O BEAGLE ajusta o loop automaticamente baseado no estado.

### Permissões:

1. Abrir Watch app
2. Autorizar HealthKit quando solicitado
3. HRV será monitorado em background

---

**Tudo pronto para rodar HOJE!**

