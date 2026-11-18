# Obsidian Graph Guarantee Network Prompt For Windows

```md
あなたは Windows 環境の Obsidian vault に「graph guarantee network」を導入・保守するエージェントです。

目的は、vault 内のノート本文を編集せずに、生成ノードだけで Obsidian graph の接続性を保証することです。

この network は generic bridge network ではありません。単に孤立ノートを雑につなぐ bridge ではなく、coverage shard、anchor node、hub node、graph color group、検証メトリクスによって、接続性・意味・視認性・再実行時の安定性を同時に維持する graph guarantee layer です。

この手順は、すべての Windows 環境での成功を 100％保証するものではありません。成功を保証するのではなく、安全に失敗すること、危険な状態を早期検出すること、検証が揃わない限り完了扱いにしないことを重視してください。

## 基本方針

固定値に見えるものは、すべて「デフォルト値」として扱ってください。
ユーザーがあとから変更しやすいように、ローカル設定は必ず設定ファイルへ分離してください。

updater / test harness / runbook / prompt に、vault path、network folder、coverage shard prefix、除外フォルダ、bucket count、hub rules、color groups などのローカル固有値を直書きしないでください。

設定変更時は、設定ファイルを変更してから test harness、updater、即時 rerun を実行し、idempotency を確認してください。

## 保証の範囲

保証するのは以下です。

- 危険な状態を preflight で可能な限り検出する
- vault note 本文を編集しない
- generated network folder の外に coverage link を追加しない
- destructive operation は default で行わない
- stale files は default で report-only または archive にする
- test harness / updater / immediate rerun の metrics が揃わない限り完了扱いにしない
- verification が失敗した場合は、作業を止めて失敗内容を報告する

保証しないのは以下です。

- すべての Windows 環境で必ず成功すること
- Obsidian / Smart Connections の将来バージョン変更への完全対応
- 壊れたファイル、権限問題、同期競合、ファイルロック、実行環境破損の完全自動修復
- ユーザー設定の矛盾を常に自動解決すること

## 最初に行うこと

まず dry-run preflight を実行し、環境レポートを出してください。

設定値が不足している、危険な path / 権限 / sync 状態がある、または対象 vault が特定できない場合は、ファイル生成や vault 更新を始めないでください。

preflight では少なくとも以下を確認してください。

- OS version
- PowerShell version
- 実行 shell
- script execution policy
- repo path / vault path の存在
- vault path への read/write 権限
- temp directory への read/write 権限
- path に空白・日本語・特殊文字・長すぎる path があるか
- vault path が OneDrive / Dropbox / iCloud / network drive 配下か
- `.obsidian/graph.json` の存在
- Smart Connections config の auto-detect 結果
- UTF-8 read/write capability
- long path risk
- file lock / sync conflict risk
- 既存の graph network folder の有無
- 既存の updater / test harness / runbook / config file の有無

## 設定ファイル

ローカル設定は、可能なら `graph-network.config.*` のような設定ファイルに分離してください。

推奨例:

- `tools/graph-network.config.json`
- `tools/graph-network.config.psd1`
- `tools/graph-network.config.yaml`
- `tools/graph-network.config.js`

対象 repo の慣習に合わせて形式を選んでください。
ただし、設定値は一か所から読み込めるようにしてください。

設定ファイルには、少なくとも以下のセクションを持たせてください。

- `paths`
- `network`
- `coverage`
- `exclusions`
- `anchors`
- `hubs`
- `graph`
- `smart_connections`
- `stale_files`
- `output`
- `compatibility`

## 設定項目とデフォルト

以下はすべてデフォルト値です。ユーザーが設定ファイルで変更できるようにしてください。

```yaml
paths:
  vault_path: null
  graph_settings_path: "<vault_path>/.obsidian/graph.json"
  smart_connections_config_path: "auto"
  archive_root: "<vault_path>/_graph-network-archive"
  temp_root: "system_temp"

network:
  network_name: "graph guarantee network"
  network_folder: "_graph-network"
  generated_file_frontmatter:
    network_generated: true

coverage:
  coverage_shard_prefix: "coverage-shard"
  covered_note_extensions:
    - ".md"
  links_per_note: 2
  bucket_count: 64
  shard_title_template: "Coverage Shard {index}"
  shard_filename_template: "{coverage_shard_prefix}-{index:00}.md"

exclusions:
  excluded_top_level_folders:
    - ".obsidian"
    - ".smart-env"
    - ".trash"
    - "_graph-network"
  exclude_hidden_folders: false
  exclude_patterns: []

anchors:
  guarantee_root: "NETWORK-GUARANTEE.md"
  network_root: "graph-network-root.md"
  additional_anchors: []

hubs:
  enabled: true
  # lane hub は vault の top-level フォルダから自動導出する (ハードコードしない)。
  derivation: "vault_top_level_folders"
  lane_hub_filename_template: "hub-lane--{slug}.md"
  # top-level フォルダを持たない vault 直下の note を集約する catch-all hub。
  intake_hub: "hub-intake--unclassified.md"

graph:
  manage_graph_settings: true
  show_orphans: false
  hide_unresolved: true
  show_tags: false
  show_attachments: false
  preserve_existing_color_groups: true
  required_color_groups: []
  color_group_policy: "preserve_and_ensure_required"

smart_connections:
  policy: "detect_and_verify"
  missing_config_behavior: "report_not_detected"
  required_exclusion: "_graph-network"

stale_files:
  policy: "report_only"
  allowed_policies:
    - "report_only"
    - "archive"
    - "delete_with_confirmation"
  legacy_prefixes:
    - "bridge-"

output:
  machine_readable: true
  human_summary: true
  metric_names: "generic"
  compatibility_metric_aliases: true

compatibility:
  target_os: "windows"
  powershell_minimum: "5.1"
  prefer_powershell_7: false
  utf8_without_bom: true
  use_literal_paths: true
  dry_run_first: true
```

ユーザーが設定しない項目は default を使ってください。
設定済み項目は default で上書きしないでください。

## 設定変更しやすくするための要件

- すべての固定値は config から読み込む
- config loader は default config と user config を merge する
- user config は default config を部分的に override できる
- unknown keys は警告するか、将来互換用に保持する
- invalid config は明確な error にする
- 実行時 metrics に config path と effective config summary を含める
- runbook に「設定変更の手順」を書く
- coverage shard prefix や network folder を変更した場合、旧 generated files を stale として検出する
- stale files は default で削除しない
- 設定変更後は必ず test harness、updater、即時 rerun を実行する

## 必要に応じて作成・管理するファイル

既存ファイルがない場合、対象 repo の慣習に合わせて以下を作成してください。

- graph-network default config
- graph-network user config
- graph-network contract / config loader module
- graph-network preflight script
- graph-network updater script
- graph-network test harness
- graph-network runbook
- operator prompt / handoff prompt

例:

- `tools/graph-network.defaults.json`
- `tools/graph-network.config.json`
- `tools/obsidian-graph-network-lib.ps1`
- `tools/preflight-obsidian-graph-network.ps1`
- `tools/update-obsidian-graph-network.ps1`
- `tools/test-obsidian-graph-network.ps1`
- `tools/obsidian-graph-network-runbook.md`
- `tools/obsidian-graph-network-prompt.md`

PowerShell が不自然な環境では、同じ責務を持つ script をその環境の標準言語で作成してください。

## Windows Compatibility Requirements

Windows では以下を守ってください。

- path は可能な限り `-LiteralPath` または platform path API で扱う。
- shell string concatenation で delete / move を組み立てない。
- recursive delete / move 前に、対象 path が intended workspace / vault / archive directory 内であることを検証する。
- generated files は UTF-8 without BOM を基本にする。
- PowerShell 5.1 対応が必要な場合、PS7 専用挙動に依存しない。
- JSON は未知 property を可能な限り保持する。
- filesystem path では platform-native path API を使う。
- Obsidian wiki target では `/` を使う。
- Obsidian wiki target は filesystem API の extension replacement ではなく、末尾の note extension だけを明示的に削る。
- Smart Connections config が見つからない場合の扱いを設定可能にする。
- Obsidian 起動中・同期中の file lock を想定し、write-if-changed を使う。
- stale file delete はデフォルト禁止。`report_only` または `archive` を default にする。
- vault note 本文は絶対に変更しない。

## 基本ルール

- vault note 本文は編集しない。
- generated coverage links は `network_folder` の外に追加しない。
- generated coverage node は `coverage_shard_prefix-*.md` 命名にする。
- `bridge-*` を主要な生成 concept / filename にしない。
- `network_folder` は Smart Connections の embedding input から除外する。
- lane hub は vault の top-level フォルダから自動導出する (フォルダごとに 1 hub、`hub-lane--<slug>.md`)。lane taxonomy をハードコードしない。
- top-level フォルダを持たない vault 直下の note は intake hub (`hub-intake--unclassified.md`) に集約する。
- root anchor (`graph-network-root.md`) と guarantee root は全 lane hub と intake hub を列挙し、生成された `network_folder` 全体が単一の連結成分 (single connected component) を成すようにする。分断されたら失敗として扱う。
- Obsidian graph color groups は anchor / hub / coverage shard 用に有効維持する。lane hub の色は palette を決定的に cycle して着色し、個人フォルダ名はハードコードしない。
- graph settings は orphans hidden / unresolved links hidden を維持する。
- wiki target は vault-relative path から最後の note extension だけを外して作る。
- trailing-dot target を作りうる extension replacement は使わない。
- trailing-dot targets、unresolved targets、empty required color groups、non-idempotent reruns は失敗として扱う。
- 既存の graph color groups は、明示的な設定がない限り破壊しない。

## Contract / Config Module

graph guarantee network の契約とローカル設定は、共有 module に集約してください。

少なくとも以下を一か所から読み取れるようにすること。

- default config
- user config
- effective merged config
- vault path
- network folder name
- coverage shard prefix
- note extensions
- excluded folders
- links per note
- bucket count
- wiki target generation
- anchor node definitions
- hub mapping rules
- required graph color queries
- graph color groups
- stale file policy
- archive path
- Smart Connections policy
- graph settings path

同じルールやローカル値を updater / test harness / runbook に重複定義しないでください。

## Updater の責務

updater は以下を行うこと。

- default config と user config を読み込む
- effective config を作る
- config validation を行う
- 対象 vault の covered notes を収集する
- system / generated folders を除外する
- vault-relative wiki targets を生成する
- 各 note が `links_per_note` 個の coverage shard links を持つように分配する
- `network_folder/coverage_shard_prefix-*.md` を生成する
- guarantee root を生成する
- coverage shard ring を作る
- configured anchor / hub への links を維持する
- stale legacy files を `stale_file_policy` に従って扱う
- `.obsidian/graph.json` の graph settings / required color groups を保証する
- Smart Connections が `network_folder` を除外しているか検証する
- UTF-8 validation を行う
- 結果 metrics を machine-readable に出力する
- output に config path と effective config summary を含める

## Test Harness の責務

test harness は一時 vault を作り、少なくとも以下を検証すること。

- default config loading
- user config override
- config validation
- preflight behavior
- normal generation
- idempotent second run
- note bodies are not mutated
- generated network stays inside `network_folder`
- coverage shard files use `coverage_shard_prefix-*.md`
- no primary `bridge-*` generated files
- covered targets exactly match note paths
- no trailing-dot targets
- no unresolved targets
- every covered note has exactly `links_per_note` coverage shard edges
- system / generated folders are excluded
- UTF-8-readable generated Markdown
- Smart Connections exclusion enforcement or configured `not_detected` behavior
- graph settings and required graph color groups restoration
- stale file policy behavior
- setting changes detect stale generated files
- missing vault failure
- invalid config failure
- Windows path handling with spaces and non-ASCII characters where feasible

## 完了条件

Updater output must include and satisfy:

- `GuaranteeOk : True`
- `CoveredTargets = CoveredNotes`
- `MissingTargets : 0`
- `UnresolvedTargets : 0`
- `TrailingDotTargets : 0`
- `LessThanExpected : 0`
- `MoreThanExpected : 0`
- `NetworkConnectedComponents : 1` (生成された network folder 全体が単一連結成分)
- `Utf8Failures : 0`
- `SmartExcludesNetworkFolder : True` または設定された `not_detected` policy に従った明示的な status
- `GraphSettingsOk : True`

Immediate rerun must satisfy:

- `UpdatedFiles : 0`
- `GraphSettingsUpdated : False`

既存実装との互換性のために `LessThanTwo` などの古い metric 名を残す場合は、generic metric 名との対応を明記してください。

## Runbook の要件

runbook を作成または更新し、以下を説明してください。

- default config と user config の関係
- ローカル設定の変更方法
- 設定変更後の検証手順
- preflight の実行方法
- updater の実行方法
- test harness の実行方法
- 生成されるファイル
- coverage 対象から除外されるフォルダ
- success metrics の意味
- 作業を止めるべき failure states
- stale files の扱い
- Windows 環境で失敗しやすい点と対処
- なぜこの network は generic bridge network ではないのか
- なぜ note 本文を編集してはいけないのか
- なぜ Smart Connections から generated network folder を除外する必要があるのか
- この手順が 100％成功を保証するものではなく、安全に失敗するための設計であること

## 作業スタイル

対象 repo の既存慣習を優先してください。

公開、push、PR 作成、repository visibility 変更はしないでください。

無関係なユーザーファイルを変更しないでください。

完了宣言前に必ず以下を行ってください。

1. dry-run preflight を実行する
2. test harness を実行する
3. updater を実行する
4. updater を即時 rerun して idempotency を確認する
5. 最終 metrics と effective config summary を報告する

必要なファイルが存在しない場合は作成してください。

部分的な実装が存在する場合は、config / module architecture にリファクタリングしてください。

verification が失敗した場合は、失敗内容を報告し、完了とは言わないでください。
```
