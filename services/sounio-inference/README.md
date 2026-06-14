# Sounio Inference Service

Exposes Sounio's verified-inference stdlib as HTTP verbs. Each verb renders a small
`.sio` program from the (untrusted) request, compiles it to a standalone native ELF
with `souc` (cached by source hash → repeats ~1ms), runs it, returns a structured verdict.

The Sounio side does pure computation; **this service is the security boundary** —
untrusted JSON is validated to typed numerics/ints here, and only those reach generated
source. This is Sounio's first production consumer.

## Verbs (v1, CPU)
| Verb | Path | Nature | Stdlib |
|------|------|--------|--------|
| `smt.check` | `POST /v1/smt/check` | logical decision (SAT/UNSAT) | `theorem::smt` DPLL(T) |
| `gum.propagate` | `POST /v1/gum/propagate` | numeric uncertainty propagation | `epistemic::gum` |
| `causal.dsep` | `POST /v1/causal/dsep` | structural graph reasoning | `causal::base` (Pearl Bayes-ball) |

`GET /health`, `GET /v1/catalog`.

## Run (dev)
```bash
python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt
SOUNIO_DIR=/home/devsounio/sounio uvicorn app:app --port 8799
```

## Env
- `SOUNIO_DIR` (default `/home/devsounio/sounio`), `SOUC_BIN`, `SOUNIO_STDLIB_PATH`
- `SOUNIO_VERB_CACHE` (ELF cache dir), `SOUNIO_COMPILE_TIMEOUT`, `SOUNIO_RUN_TIMEOUT`

## TODO (next)
- Containerize (bundle souc compiler artifact + stdlib), k8s deploy (CPU v1), register as MCP tool.
- Triad seam → HTTP client to `smt.check`; retire #31 Julia ODE as "verification".
