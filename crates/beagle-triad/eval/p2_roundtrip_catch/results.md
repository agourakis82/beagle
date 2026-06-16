# Eval — P2 (SymbCoT round-trip) catch rate

model: `deepseek-chat` · 26 faithful + 34 corrupted pairs

| metric | value |
|---|---|
| recall (catch rate on mistranslations) | **0.765** |
| false-abstain rate (on faithful gold) | 0.385 |

## Catch rate by corruption type

| corruption | n | catch rate |
|---|---|---|
| op_swap | 8 | 0.750 |
| sign_flip | 10 | 1.000 |
| spurious_edge | 8 | 0.500 |
| unit_desync | 8 | 0.750 |
