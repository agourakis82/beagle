# B22.2 GO / NO-GO

## GO

- Current retrieval baseline is benchmarked repo-natively.
- Payload-filtered retrieval is benchmarked and reported.
- Backend matrix and reranking profile are explicit artifacts.
- A bounded recommendation exists and stays aligned with the current Beagle architecture.
- Restart remains coherent.
- Cluster stays green.
- Slurm stays green.

## NO-GO

- Benchmark output is missing or not reproducible.
- Backend matrix is hand-wavy or disconnected from the current retrieval spine.
- Recommendation implies a hidden replatform.
- Restart breaks retrieval coherence.
- Cluster or Slurm regress.
