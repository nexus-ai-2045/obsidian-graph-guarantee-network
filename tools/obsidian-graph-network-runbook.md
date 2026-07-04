# Obsidian Graph Network Runbook

## Update

Run this after adding, moving, or deleting vault notes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\update-obsidian-graph-network.ps1 -Vault "C:\Path\To\Vault"
```

`-Vault` is required and has no default; the updater fails fast with a usage
error when it is omitted, so a fresh clone can never write into an unintended
parent directory.

`-BucketCount` defaults to `0` (auto). Auto derives the coverage shard count
from the covered note count `N` as `min(64, max(8, ceil(N / 16)))`, and the
updater output reports the resolved value as `BucketCountUsed`. Pass an
explicit value of `2` or greater to override; `1` and negative values fail
clearly, because a single shard cannot give a note two distinct shard edges.

When the resolved shard count shrinks — on the first run after upgrading from
the previous fixed 64-shard default, or after enough note deletions that auto
resolves to a smaller count — the higher-numbered shard files left on disk
still carry live links and would break the exact-two-edges guarantee. The
updater detects those leftover shard files and fails instead of reporting
`GuaranteeOk : True`; rerun the same command with `-PruneStale` to archive
them and restore the guarantee.

Vaults generated before the shard-navigation reduction (when every shard still
linked `FDE-NETWORK` and `NETWORK-GUARANTEE` directly) are rewritten once on
the first run with the current layout, so expect `UpdatedFiles > 0` for that
migration run. The immediate rerun must return to `UpdatedFiles : 0`.

For a fresh operator or agent, use the copy-ready prompt in:

```text
tools\obsidian-fde-graph-network-prompt.md
```

## Test

Run the full local test harness after changing the update script or graph-network operating rules:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-obsidian-graph-network.ps1
```

Before treating implementation or operations as complete, run the aggregate verification:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify-obsidian-graph-network.ps1
```

It must finish with `OperationalGuaranteeOk : True` and
`ImplementationResidualWork : 0`.

The test harness covers:

- Normal generation
- Idempotent second run
- Exactly two FDE coverage shard edges per covered note
- Single connected wikilink component across all generated network files
  (auto 8-shard ring and explicit `-BucketCount 17`)
- Coverage shards never link the root anchors directly, and root anchor
  degree stays bounded by the lane hub count
- Clear failure when an isolated generated-marker file splits the network
- System/generated folder exclusion
- Flat `_graph-network` structure
- No note-body mutation
- UTF-8-readable generated Markdown
- Smart Connections exclusion enforcement
- Obsidian graph settings and color group restoration
- Bounded incremental updates after note additions
- `-PruneStale` behavior
- Stale coverage shard detection and `-PruneStale` recovery after the shard ring shrinks
- Clear failures for invalid vaults, invalid bucket counts, and missing Smart exclusion

## Contract Module

Keep shared FDE graph-network constants and helpers in:

```text
tools\obsidian-graph-network-lib.ps1
```

The updater and test harness should both use this module for coverage shard
naming, excluded top-level folders, wiki target generation, and required graph
color queries. Do not reintroduce duplicate local copies of those rules.

## Success Criteria

The command must finish with:

- `GuaranteeOk : True`
- `MissingTargets : 0`
- `UnresolvedTargets : 0`
- `TrailingDotTargets : 0`
- `LessThanTwo : 0`
- `MoreThanTwo : 0`
- `NetworkConnectedComponents : 1`
- `Utf8Failures : 0`
- `SmartExcludesGraphNetwork : True`
- `GraphSettingsOk : True`
- `GraphSettingsUpdated : False` on idempotent follow-up runs

If any of these are false, treat the update as failed and do not trust the graph guarantee.

## Design Contract

- Notes are not edited.
- `_graph-network` stays flat; no nested generated folders.
- Every covered Markdown note gets exactly two FDE coverage shard links.
- Coverage shards link only the previous shard, the next shard, and their lane
  hub; shards do not link the root anchors directly (degree reduction). Root
  anchors reach the shard ring through the lane hubs and the single ring entry
  link, so root anchor degree stays O(lane count) instead of O(shard count).
- All generated `_graph-network` files form a single connected wikilink
  component; the updater fails the run when this is violated and the test
  harness re-verifies it with a BFS over the parsed `[[...]]` links.
- Obsidian graph color groups stay enabled for FDE anchors, lane hubs, and coverage shards.
- `_graph-network` is for Obsidian graph connectivity only and must stay excluded from Smart Connections.
- No background watcher or scheduled job is used.

## Operational Notes

- Keep updates manual/lightweight; do not add a watcher or scheduled job unless the performance model is redesigned.
- Keep `_graph-network` excluded from Smart Connections so generated coverage links do not become embedding input.
- Keep Obsidian graph configured with orphans hidden, unresolved links hidden, and FDE graph color groups enabled.
- Never reframe the generated network as a generic bridge network; the generated coverage nodes are FDE coverage shards.
- If Smart Connections is slow after large vault changes, prefer excluding heavy folders and disabling block embeddings before resetting data.
- If Smart data must be reset, do it intentionally when the machine can sit idle; re-import is expected to be intensive on large vaults.
