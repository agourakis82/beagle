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
- Salva drafts temporários (`/tmp/bad.txt`, `/tmp/good.txt`)
- Chama `scripts/train_lora_unsloth.py` no M3 Max
- Move adapter para `/home/agourakis82/beagle-data/lora/current_voice/`
- Reinicia vLLM via SSH no cluster

## Script Unsloth

O script `scripts/train_lora_unsloth.py` aceita variáveis de ambiente:
- `BAD_DRAFT`: Caminho para draft ruim
- `GOOD_DRAFT`: Caminho para draft bom
- `OUTPUT_DIR`: Diretório de saída do adapter

## Integração Manual

Se quiser usar manualmente:

```rust
use beagle_lora_auto::train_and_update_voice;

if score > best_score {
    let bad = current_draft.clone();
    let good = new_draft.clone();
    
    tokio::spawn(async move {
        if let Err(e) = train_and_update_voice(&bad, &good).await {
            error!("LoRA auto falhou: {e}");
        } else {
            info!("Voz atualizada — o BEAGLE fala mais como tu agora");
        }
    });
}
```

## Status

✅ Crate criado
✅ Integrado no loop adversarial
✅ Script Unsloth atualizado
✅ Compila sem erros
