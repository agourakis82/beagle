# Eval #3 — P3 self-consistency abstention operating point

model: `deepseek-chat` · 30 cases · K_MAX=5

| config | coverage | precision(trusted) | abstained-unfaithful / total-unfaithful |
|---|---|---|---|
| k=1/majority | 0.867 | 0.923 | 0/2 |
| k=3/majority | 0.800 | 0.917 | 0/2 |
| k=5/majority | 0.767 | 0.913 | 0/2 |
| k=3/unanimous | 0.700 | 0.905 | 0/2 |
| k=5/unanimous | 0.700 | 0.905 | 0/2 |
| production-policy | 0.800 | 0.917 | 0/2 |

Extraction key disagreement across K=5: **5/30** cases. Self-consistency can only abstain where the k runs disagree; deterministic mistranslations (all k agree on the same wrong artifact) are invisible to it.

_coverage = fraction trusted (not abstained); precision = faithful among trusted; abstained-unfaithful = of cases whose single-shot verdict is unfaithful, how many P3 abstained on._
