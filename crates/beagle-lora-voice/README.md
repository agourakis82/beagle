# BEAGLE LoRA Voice - 100% Automático

Treina LoRA voice automaticamente a cada draft melhor no loop adversarial.

## Como Funciona

1. **Loop Adversarial detecta draft melhor** (`score > best_score`)
2. **Treina LoRA automaticamente** usando MLX no M3 Max
3. **Atualiza vLLM** com o novo adapter
4. **Nunca quebra** - se falhar, só loga e continua

## Uso

Integrado automaticamente no loop adversarial do `beagle-hermes`.

Quando `quality_score > best_quality`, o sistema:
- Salva drafts temporários (`/tmp/bad.txt`, `/tmp/good.txt`)
- Chama `scripts/train_lora_mlx.py` no M3 Max
- Copia adapter para `/home/agourakis82/beagle-data/lora/current_voice/`
- Reinicia vLLM via SSH no cluster

## Script MLX

O script `scripts/train_lora_mlx.py` é um placeholder. Substitua pelo seu código MLX real de treinamento LoRA.

## Status

✅ Crate criado
✅ Integrado no loop adversarial
✅ Script MLX placeholder criado
⚠️  Substituir script MLX pelo código real de treinamento

