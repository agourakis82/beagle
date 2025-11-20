# BEAGLE Stress Test - Full Cycle End-to-End 100x

Testa se o BEAGLE sobrevive 100 iterações completas sem quebrar.

## Ciclo Completo Testado

1. **Quantum Superposition** - Gera hipóteses
2. **Adversarial Self-Play** - Refina até >98.5%
3. **Paper Generation** - Gera paper final
4. **LoRA Training** - Treina LoRA se score melhorou
5. **vLLM Restart** - Reinicia vLLM com novo LoRA

## Como Rodar

```bash
# Compila e roda
cargo run --release --bin beagle-stress-test

# Com logging detalhado
RUST_LOG=info cargo run --release --bin beagle-stress-test
```

## Relatório

O teste gera um relatório JSON com:
- Total de ciclos executados
- Taxa de sucesso
- Duração média/mínima/máxima por ciclo
- Resumo de erros encontrados
- Detalhes de cada ciclo

Arquivo salvo: `beagle_stress_test_YYYYMMDD_HHMMSS.json`

## Critério de Sucesso

- **≥95% sucesso**: BEAGLE é robusto, pode rodar 24h
- **<95% sucesso**: Precisa de ajustes antes de rodar 24h

## Timeouts

- Quantum: 30s
- Adversarial: 5min
- Paper Generation: 2min
- LoRA Training: 15min
- vLLM Restart: 1min

## Status

✅ Estrutura criada
✅ Timeouts e retries implementados
✅ Relatório JSON completo
⚠️  Integração com componentes reais pendente (atualmente simula)

## Próximos Passos

1. Integrar com `beagle-quantum` real
2. Integrar com `beagle-hermes` adversarial real
3. Integrar com geração de paper real
4. Integrar com `beagle-lora-voice` real
5. Integrar com vLLM restart real

