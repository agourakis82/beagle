# 🔬 beagle-quantum

**Quantum-Inspired Reasoning Engine for BEAGLE SINGULARITY**

O primeiro motor de raciocínio quântico-inspirado funcional dentro de um exocórtex científico.

## 🎯 Visão Geral

Este crate implementa os três pilares quânticos clássicos simulados:

- **Superposition**: Múltiplas hipóteses simultâneas com amplitudes complexas
- **Interference**: Reforço ou cancelamento de caminhos baseado em evidências
- **Measurement**: Colapso probabilístico com logging de confiança

## 🚀 Uso Rápido

```rust
use beagle_quantum::{
    SuperpositionAgent, InterferenceEngine, MeasurementOperator,
    CollapseStrategy,
};

// 1. Gerar múltiplas hipóteses em superposição (vLLM real)
let quantum = SuperpositionAgent::new(); // Conecta ao vLLM em t560.local:8000
let mut set = quantum.generate_hypotheses(
    "Como explicar a curvatura da entropia em scaffolds?"
).await?;

// 2. Aplicar interferência com evidências
let interference = InterferenceEngine::new(0.7);
interference.interfere(&mut set, "Evidência experimental 2024 confirma modelo quântico").await?;

// 3. Colapsar para resposta final
let measurement = MeasurementOperator::new(0.2);
let final_answer = measurement.measure(set, CollapseStrategy::Probabilistic).await?;
```

## 📚 Módulos

### `superposition`
- `Hypothesis`: Hipótese individual com amplitude complexa
- `HypothesisSet`: Conjunto de hipóteses em superposição
- `SuperpositionAgent`: Gera múltiplas hipóteses simultâneas

### `interference`
- `InterferenceEngine`: Aplica interferência construtiva/destrutiva
- `InterferenceType`: Tipo de interferência (Constructive/Destructive/Neutral)

### `measurement`
- `MeasurementOperator`: Colapsa superposição para resposta única
- `CollapseStrategy`: Estratégias de colapso (Greedy/Probabilistic/Delayed)

### `mcts_integration`
- `QuantumMCTS`: Monte Carlo Tree Search com superposição

## 🧪 Testes

```bash
cargo test --package beagle-quantum
```

## 📖 Exemplos

### Exemplo Completo (com vLLM)
```bash
cargo run --example quantum_reasoning --package beagle-quantum
```

### Teste de Superposition com vLLM Real
```bash
cargo run --package beagle-quantum --example test_superposition -- \
  "Como unificar gravidade quântica com termodinâmica em scaffolds biológicos?"
```

**Nota:** Requer vLLM server rodando em `http://t560.local:8000/v1`

## 🔬 Arquitetura

```
Query → Superposition (N hipóteses)
     → Interference (evidências reforçam/cancelam)
     → Measurement (colapso para resposta)
```

## 🎓 Referências

- Quantum Computing: Superposition e Interference
- Monte Carlo Tree Search (MCTS)
- Probabilistic Reasoning

## 📝 Status

✅ **Week 1 Roadmap Completo - PRODUCTION READY**
- ✅ Superposition implementado (vLLM real, batch n=6)
- ✅ Interference implementado (construtiva/destrutiva)
- ✅ Measurement implementado (3 estratégias)
- ✅ MCTS integration implementado
- ✅ Testes E2E passando (5/5)
- ✅ vLLM client integrado (beagle-llm)
- ✅ Fallback robusto para testes sem cluster

---

**BEAGLE SINGULARITY** - Quebrando a realidade clássica, uma hipótese por vez. ⚡

