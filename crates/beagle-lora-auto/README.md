# BEAGLE LoRA Auto - 100% Automático

Treina LoRA voice automaticamente a cada draft melhor no loop adversarial.

## Como Funciona

1. **Loop Adversarial detecta draft melhor** (`score > best_score`)
2. **Treina LoRA automaticamente** usando Unsloth no M3 Max
3. **Atualiza vLLM** com o novo adapter
4. **Nunca quebra** - se falhar, só loga e continua

## Uso

Integrado automaticamente no loop adversarial do `beagle-hermes`.

Quando `quality_score > best_quality`, o sistema:
- Salva drafts temporários (`/tmp/bad_draft.txt`, `/tmp/good_draft.txt`)
- Chama `scripts/train_lora_unsloth.py` (customizável via `BEAGLE_LORA_SCRIPT`)
- Reinicia vLLM via SSH (host configurável via `VLLM_HOST`)

## Script Unsloth

O script `scripts/train_lora_unsloth.py` aceita variáveis de ambiente:
- `BAD_DRAFT`: Caminho ou conteúdo do draft ruim
- `GOOD_DRAFT`: Caminho ou conteúdo do draft bom
- `OUTPUT_DIR`: Diretório de saída do adapter
- `MODEL_NAME`: Modelo base (default: `unsloth/Llama-3.2-8B-Instruct-bnb-4bit`)

## Integração Manual

Se quiser usar manualmente:

```rust
use beagle_lora_auto::train_lora;

if score > best_score {
    let bad = current_draft.clone();
    let good = new_draft.clone();
    let output_dir = "/tmp/beagle_lora/manual_run";
    
    let result = std::thread::spawn(move || train_lora(&bad, &good, output_dir))
        .join()
        .expect("thread join");
    println!("Resultado: {:?}", result);
}
```

## Status

✅ Crate criado
✅ Integrado no loop adversarial
✅ Script Unsloth atualizado e parametrizado
✅ Compila sem erros
