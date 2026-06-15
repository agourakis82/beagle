# Eval #1 — P1 redactor: residual confabulation rate

Corpus: `/home/devsounio/beagle/crates/beagle-triad/eval/confabulation/corpus.jsonl` (84 cases)

## Headline metrics

| metric | value |
|---|---|
| recall (fabrications caught) | 1.000 |
| **residual confabulation rate (1−recall)** | **0.000** |
| precision | 1.000 |
| false-positive rate (over-redaction) | 0.000 |
| F1 | 1.000 |
| confusion | TP=48 FN=0 FP=0 TN=36 |

## Per failure class

| category | n | redacted-rate | TP | FN | FP | TN |
|---|---|---|---|---|---|---|
| attested_legit | 12 | 0.00 | 0 | 0 | 0 | 12 |
| benign_bait | 12 | 0.00 | 0 | 0 | 0 | 12 |
| fabricated_abstain | 12 | 1.00 | 12 | 0 | 0 | 0 |
| fabricated_gate_off | 12 | 1.00 | 12 | 0 | 0 | 0 |
| fabricated_no_record | 12 | 1.00 | 12 | 0 | 0 | 0 |
| multiverb_all_attested | 12 | 0.00 | 0 | 0 | 0 | 12 |
| multiverb_mixed | 12 | 1.00 | 12 | 0 | 0 | 0 |

_Positive = "redacted". For fabrication classes (expected=true) FN is a missed confabulation; for benign/attested classes (expected=false) FP is an over-redaction. Labels are fixed by construction per class._
