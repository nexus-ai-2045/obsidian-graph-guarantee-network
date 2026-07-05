# Obsidian Graph Guarantee Network

Obsidian のノート本文を編集せずに、生成ノードだけで graph の接続性を保証するための、Windows 向けプロンプト兼リファレンス実装です。

生成ノードは専用フォルダに置き、missing targets、unresolved targets、trailing-dot targets、UTF-8 読み取り、Smart Connections 除外、graph settings、即時 rerun の idempotency などのメトリクスで検証します。

## 含まれるもの

- `tools/obsidian-graph-network-generic-windows-prompt.md`: Windows 環境で使える、設定変更しやすい汎用日本語プロンプト。
- `tools/obsidian-graph-network-lib.ps1`: updater と test harness が共有する helper module。
- `tools/update-obsidian-graph-network.ps1`: graph network の reference updater。
- `tools/test-obsidian-graph-network.ps1`: local test harness。
- `tools/verify-obsidian-graph-network.ps1`: 実装・運用チェックをまとめて確認する aggregate verification。
- `tools/obsidian-graph-network-runbook.md`: operator runbook。
- `tools/public-safety-scan.ps1`: 公開前の safety scan。
- `GITHUB_SETTINGS.md`: GitHub repository settings の日本語メモ。

## 設計原則

- vault note 本文は編集しない。
- generated coverage links は generated network folder の中だけに置く。
- 固定値に見えるものは default として扱い、ユーザー設定へ逃がせるようにする。
- dry-run、preflight、write-if-changed、test、即時 rerun を重視する。
- verification metrics が揃わない限り成功扱いにしない。
- すべての Windows 環境での成功を保証するものではなく、安全に失敗することを優先する。

## ローカルチェック

test harness を実行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-obsidian-graph-network.ps1
```

public-safety scan を実行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\public-safety-scan.ps1
```

実装・運用チェックをまとめて実行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify-obsidian-graph-network.ps1
```

完了扱いにするには、verification command が `OperationalGuaranteeOk : True` と `ImplementationResidualWork : 0` を返す必要があります。

任意の vault に updater を実行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\update-obsidian-graph-network.ps1 -Vault "C:\Path\To\Vault"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\update-obsidian-graph-network.ps1 -Vault "C:\Path\To\Vault"
```

即時 rerun では `UpdatedFiles : 0` と `GraphSettingsUpdated : False` が期待値です。

## 命名と移行

生成物の命名は汎用化されています。coverage shard は `coverage-shard-NN.md`、root anchor は `graph-network-root.md`、lane hub は vault の top-level フォルダから自動導出します (`hub-lane--<folder>.md` と、フォルダを持たない note 用の `hub-intake--unclassified.md`)。lane の分類はハードコードせず、対象 vault の実際のフォルダ構成に追従します。

旧レイアウトで生成した vault では、この命名変更後に旧名の生成ファイルが stale として残ることがあります。その場合は updater を一度だけ `-PruneStale` 付きで実行し、stale ファイルを archive してから guarantee を再確認してください。

## 公開ステータス

この repository は 2026-07-04 に repository-specific approval を得て公開済みです (記録: [PUBLIC_READY.md](PUBLIC_READY.md))。repository visibility change、announcement、broad sharing には、引き続き明示的な human review と approval が必要です。

GitHub 側の repository settings は [GITHUB_SETTINGS.md](GITHUB_SETTINGS.md) に日本語でまとめています。
