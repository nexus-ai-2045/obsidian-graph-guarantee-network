# Obsidian FDE Graph Network Execution Prompt

Use this prompt when a fresh operator or agent must update or repair the
Obsidian FDE graph network from a blank slate.

```md
You are updating an Obsidian vault's `_graph-network`.

The goal is to preserve FDE graph connectivity with meaning, color, and
verifiable guarantees. Do not create a generic bridge network. The generated
coverage concept is `FDE coverage shard`.

## Hard Rules

- Do not edit note bodies.
- Do not add generated coverage links outside `_graph-network`.
- Do not publish, push, create a PR, or change GitHub repository visibility.
- Do not use `bridge-*` as the primary generated filename or concept.
- Generated coverage files must be named `fde-coverage-shard-XX.md`.
- Generated coverage headings must read `FDE Coverage Shard XX`.
- `_graph-network` must stay excluded from Smart Connections embedding input.
- Obsidian graph color groups must stay enabled for FDE anchors, lane hubs, and
  coverage shards.
- Empty `colorGroups` is a failed state.
- Skipping idempotency checks is a failed state.

## Target Generation

- Cover Markdown notes in the vault.
- Exclude top-level folders `.obsidian`, `.smart-env`, `.trash`, and
  `_graph-network`.
- Build each wiki target from the vault-relative note path by removing only the
  final `.md`.
- Do not use `[System.IO.Path]::ChangeExtension(..., $null)` for wiki targets.
- Do not generate trailing-dot targets such as `README.`.
- Do not generate unresolved targets.
- File names containing `]` must still parse and verify correctly.

## Required Network Shape

- `_graph-network/FDE-NETWORK.md` is the FDE network root anchor.
- `_graph-network/NETWORK-GUARANTEE.md` is the guarantee anchor.
- `_graph-network/hub-lane--*.md` files are FDE lane hubs.
- `_graph-network/fde-coverage-shard-*.md` files are coverage shards.
- Each covered note must be linked from exactly two coverage shards.
- Coverage shards must link to previous and next shards as a ring.
- Each coverage shard must link to the relevant FDE lane hub.
- No `bridge-*.md` files may remain after migration.

## Required Graph Settings

`.obsidian/graph.json` must guarantee:

- `showOrphans = false`
- `hideUnresolved = true`
- `showTags = false`
- `showAttachments = false`
- `collapse-color-groups = false`
- `colorGroups` includes visible groups for FDE anchors, lane hubs, and coverage
  shards.

## Required Verification

Run the local test harness:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-obsidian-graph-network.ps1
```

Run the updater for the target vault, then immediately rerun it to verify
idempotency.

Completion requires:

- `GuaranteeOk : True`
- `CoveredTargets = CoveredNotes`
- `MissingTargets : 0`
- `UnresolvedTargets : 0`
- `TrailingDotTargets : 0`
- `LessThanTwo : 0`
- `MoreThanTwo : 0`
- `Utf8Failures : 0`
- `SmartExcludesGraphNetwork : True`
- `GraphSettingsOk : True`
- On immediate rerun, `UpdatedFiles : 0`
- On immediate rerun, `GraphSettingsUpdated : False`

If any condition fails, the work is not complete.
```
