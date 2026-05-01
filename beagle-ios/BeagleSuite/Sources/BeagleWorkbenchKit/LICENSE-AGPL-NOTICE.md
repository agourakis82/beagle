# BeagleWorkbenchKit License Boundary

`BeagleWorkbenchKit` is the Apple AGPL boundary for terminal/workbench UI and
Warp-derived bridge concepts.

SPDX-License-Identifier: AGPL-3.0-only

This module must not contain private memories, truthsets, tokens, raw terminal
logs, or cluster artifacts. SwiftData remains cache/outbox only; canonical
memory remains in the Beagle cluster.
