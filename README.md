# Obsidian Graph Guarantee Network

Obsidian のノート本文を編集せずに、生成ノードだけで graph の接続性を保証するための、Windows 向けプロンプト兼リファレンス実装です。

生成ノードは専用フォルダに置き、missing targets、unresolved targets、trailing-dot targets、UTF-8 読み取り、Smart Connections 除外、graph settings、即時 rerun の idempotency などのメトリクスで検証します。

## 含まれるもの

- `tools/obsidian-graph-network-generic-windows-prompt.md`: Windows 環境で使える、設定変更しやすい汎用日本語プロンプト。
- `tools/obsidian-graph-network-lib.ps1`: updater と test harness が共有する helper module。
- `tools/update-obsidian-graph-network.ps1`: graph network の reference updater。
- `tools/audit-obsidian-graph-network.ps1`: 生成リンクを除いた vault 本来の連結性を測る read-only 診断 (vault を変更しない)。
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

## 連結性の read-only 診断

updater は covered note を生成 coverage リンクで機械的に 2 本ずつ繋ぐため、実行後は生成ネットワークがすべてを接続済みに見せ、vault 本来の孤立や断片化が隠れます。生成リンクを除いた vault 本来 (native) の連結性を把握したいときは、read-only 診断を実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\audit-obsidian-graph-network.ps1 -Vault "C:\Path\To\Vault"
```

この診断は updater とは別物で、vault にも repo にも一切書き込まず、生成 `_graph-network` フォルダにも触れず、updater を呼びません。covered note の走査・除外述語・wikilink parse は updater と共有します。`-Vault` は必須で、省略時は updater と同様に usage error で失敗します。`-Top` は任意で、孤立サンプルの表示件数を指定します (default `20`、`0` で非表示)。

wikilink の解決は basename ベースの近似です。相対パス一致を優先し、無ければ ordinal case-insensitive な basename の一意一致で解決します。曖昧 (basename 複数一致) や未解決の target は `UnresolvedLinks` に計上し、edge にはしません。出力は機械可読な object と人間可読サマリで、孤立数 (`OrphanNotes`)、native の連結成分数 (`NativeConnectedComponents`)、最大成分サイズ、native degree の分布などを含みます。同一 vault では二度実行しても同一の出力になります。

## 命名と移行

生成物の命名は汎用化されています。coverage shard は `coverage-shard-NN.md`、root anchor は `graph-network-root.md`、lane hub は vault の top-level フォルダから自動導出します (`hub-lane--<folder>.md` と、フォルダを持たない note 用の `hub-intake--unclassified.md`)。lane の分類はハードコードせず、対象 vault の実際のフォルダ構成に追従します。

旧レイアウトで生成した vault では、この命名変更後に旧名の生成ファイルが stale として残ることがあります。その場合は updater を一度だけ `-PruneStale` 付きで実行し、stale ファイルを archive してから guarantee を再確認してください。

## 公開ステータス

この repository は 2026-07-04 に repository-specific approval を得て公開済みです (記録: [PUBLIC_READY.md](PUBLIC_READY.md))。repository visibility change、announcement、broad sharing には、引き続き明示的な human review と approval が必要です。

GitHub 側の repository settings は [GITHUB_SETTINGS.md](GITHUB_SETTINGS.md) に日本語でまとめています。
