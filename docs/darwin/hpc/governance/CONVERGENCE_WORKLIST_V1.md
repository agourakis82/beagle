# Convergence Worklist v1

## Purpose

Translate the ecosystem authority map into repo-by-repo decisions that can be executed without reopening sovereignty debates every cycle.

## Decision Vocabulary

- `keep sovereign`
- `keep contained`
- `absorb`
- `freeze`

## Initial Queue

| Repo | Current reading | Decision | Authority owner | Immediate next action |
| --- | --- | --- | --- | --- |
| `beagle` | exocortex / platform / cockpit / integration monorepo | `keep sovereign` | `beagle` | align public repo description with actual platform role |
| `sounio` | language / compiler / stdlib / runtime substrate | `keep sovereign` | `sounio` | freeze satellite policy and treat all language-adjacent repos as subordinate |
| `darwin-cockpit` | cockpit-named Darwin stub with thin runtime shape | `absorb` | `beagle` | stop treating it as sovereign and define the absorption target inside Beagle |
| `medlang` | historical Rust language line with public subsumption claim | `freeze` | `sounio` | align archive posture and prevent implicit competition with Sounio |

## Secondary Queue

| Repo | Current reading | Decision | Authority owner | Immediate next action |
| --- | --- | --- | --- | --- |
| `darwin-workspace` | workflow and integration layer | `keep contained` | `beagle` | document that it does not own platform or algorithmic authority |
| `darwin-pbpk-platform` | PBPK domain engine | `keep contained` | `beagle` | freeze boundary as domain engine, not platform |
| `DarwinScaffoldStudio.jl` | scaffold analytics engine | `keep contained` | `beagle` | freeze boundary as specialized scientific engine |
| `demetrios` | archived or experimental language line | `freeze` unless explicit repositioning | `sounio` | decide whether to unarchive as experimental or keep historical |
| `darwin-core` | sovereignty-styled thin line | `freeze` or `absorb` | `beagle` | decide whether any real runtime value remains |

## Review Rule

No repository should remain in an ambiguous state where its public naming implies sovereignty that its structure and authority do not support.

If a repository cannot justify sovereign status with real structural authority, it must resolve toward containment, absorption, or freeze.

## Execution Queue

The first executable queue derived from this worklist is tracked in:

- `CONVERGENCE_WORKLIST_PHASE1.md`
