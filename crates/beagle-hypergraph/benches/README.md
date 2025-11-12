# Beagle Hypergraph Benchmarks

Performance benchmarks using [Criterion](https://github.com/bheisler/criterion.rs).

## Running Benchmarks

```bash
# Run all benchmarks
cargo bench

# Run specific benchmark group
cargo bench -- node_creation

# Save baseline for comparison
cargo bench -- --save-baseline main

# Compare against baseline
cargo bench -- --baseline main
```

## Benchmark Categories

1. **Node Creation**: Builder pattern overhead
2. **Serialization**: JSON encode/decode performance
3. **Hyperedge Operations**: Set operations (intersection, union, difference)
4. **Scaling Tests**: Performance with varying input sizes e validação
5. **Memory Allocation**: Padrões de alocação e clonagem
6. **Validation**: Desempenho da lógica de validação e tratamento de erros

## Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Node creation | <1 µs | Minimal overhead |
| JSON serialization (1KB) | <10 µs | Optimized Serde |
| Hyperedge intersection (100 nodes) | <5 µs | O(n) algorithm |
| Validation (success) | <500 ns | Fast path |
| Validation (failure) | <100 ns | Early return |

## Viewing Results

HTML reports são gerados em `target/criterion/report/index.html`.

## Continuous Integration

Benchmarks executam em cada PR para detectar regressões:

- Falha se >10% de regressão em operações críticas
- Gera relatórios de comparação automaticamente








