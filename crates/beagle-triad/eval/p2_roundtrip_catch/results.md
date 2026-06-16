# Eval — P2 (SymbCoT round-trip) catch rate

model: `deepseek-chat` · 26 faithful + 34 corrupted pairs · **BEAGLE_TRIAD_SYMB_VERIFY must be ON** for P2 to run in prod (this eval calls the prompt directly)

| metric | value |
|---|---|
| recall (catch rate on mistranslations) | **0.824** |
| false-abstain rate (on faithful gold) | 0.423 |

## Catch rate by corruption type

| corruption | n | catch rate |
|---|---|---|
| op_swap | 8 | 1.000 |
| sign_flip | 10 | 1.000 |
| spurious_edge | 8 | 0.375 |
| unit_desync | 8 | 0.875 |

_recall = P2 abstains on a deliberately-mistranslated artifact (gold sign-flipped / op-swapped / unit-desynced / spurious-edge). false-abstain = P2 wrongly abstains on the faithful gold artifact. The P2 prompt explicitly ignores unit normalization, so `unit_desync` catch rate is expected to be low._
