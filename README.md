# Obsidian Graph Guarantee Network

Obsidian のノート本文を変更せず、既存リンクの孤立・連結性を診断する PowerShell の参照実装です。普段は読取り専用の診断を使い、生成ネットワークは利用者が明示的に選んだ場合だけ使います。

## 目的

既存ノート同士の接続と、機械的に追加した coverage リンクを区別します。診断だけなら Markdown、設定ファイル、補助ノードを新しく作りません。

生成を選んだ場合は、vault のノート本文に手を入れないまま、Graph View 上で全ノートが 1 つにつながっている状態を機械的に保証し、その保証を数値で確かめます。生成ノードは専用フォルダに置き、missing targets、unresolved targets、trailing-dot targets、UTF-8 読み取り、Smart Connections 除外、graph settings、即時 rerun の idempotency などのメトリクスで検証します。

## できること

- 既存 wikilink による孤立ノート、連結成分、次数、未解決・曖昧なリンクを読取り専用で測定します。
- 診断と生成は共通の走査・除外・リンク解析を再利用し、依存物とキャッシュを列挙前に枝刈りします。
- 任意の生成モードでは専用フォルダ内に coverage shard と hub を生成し、原ノート本文へリンクを挿入しません。
- 生成モードで追加する既定の除外は、既存の `userIgnoreFilters` を消さずに補います。
- 即時 rerun で差分が出ないこと (idempotency) をテストと検証コマンドで確かめます。

## 使い方

Windows PowerShell 5.1 以降を対象にしています。対象 vault を明示し、最初は次の診断だけを実行します。

```powershell
powershell -NoProfile -File tools\audit-obsidian-graph-network.ps1 -Vault "C:\Path\To\Vault" -Top 20
```

`-Top 0` なら孤立ノートの名前を出さず、集計だけを確認できます (default `20`)。`-Vault` の省略・不存在はエラーです。診断は vault にも repository にも書き込まず、生成 `_graph-network` フォルダにも触れず、生成側の updater を呼びません。covered note の走査・除外述語・wikilink parse は updater と共有します。

主な出力は `CoveredNotes`、`OrphanNotes`、`NativeConnectedComponents`、`LargestComponentSize`、`UnresolvedLinks`、native degree の分布です。生成された coverage リンクは native の分析から除外します。出力は機械可読な object と人間可読サマリで、同じ入力での出力は決定的です。

wikilink の解決は basename ベースの近似です。相対パス一致を優先し、無ければ ordinal case-insensitive な basename の一意一致で解決します。曖昧 (basename 複数一致) や未解決の target は `UnresolvedLinks` に計上し、edge にはしません。コードブロック (```` ``` ```` や `~~~` で囲んだ部分) とインラインのコードの中にある `[[...]]` は例として扱い、リンクに数えません。ただし、行頭から4文字以上字下げした柵と、引用 (`> `) の中の柵はコードブロックとして扱わないため、その中の `[[...]]` は数えます。

### 生成ネットワークを明示的に選ぶ場合

次は診断ではありません。専用の `_graph-network/` に Markdown を生成し、`.obsidian/graph.json` と `.obsidian/app.json` を変更します。実行前にバックアップと、対象・生成内容のレビューを行ってください。

```powershell
powershell -NoProfile -File tools\update-obsidian-graph-network.ps1 -Vault "C:\Path\To\Vault"
powershell -NoProfile -File tools\update-obsidian-graph-network.ps1 -Vault "C:\Path\To\Vault"
```

updater は covered note を生成 coverage リンクで機械的に 2 本ずつ繋ぐため、実行後は生成ネットワークがすべてを接続済みに見せ、vault 本来の孤立や断片化が隠れます。vault 本来の状態は上の診断で確認してください。即時 rerun では `UpdatedFiles : 0`、`GraphSettingsUpdated : False`、`AppSettingsUpdated : False` が期待値です。

生成されるのは `coverage-shard-NN.md`、`graph-network-root.md`、`hub-lane--<folder>.md`、`hub-intake--unclassified.md` 等です。lane の分類はハードコードせず、対象 vault の実際の top-level フォルダ構成に追従します。これらは機械的な coverage を作るもので、ノート同士の意味的な関連性を判定する機能ではありません。

`-PruneStale` は生成を止めるオプションではありません。新しい生成物を書いた後に stale 生成物を archive するので、単なる掃除や非生成モードとして使わないでください。旧レイアウトで生成した vault で旧名の生成ファイルが stale として残った場合は、updater を一度だけ `-PruneStale` 付きで実行し、guarantee を再確認してください。

## 制約と安全境界

- native のリンク解析は正規表現と path・一意 basename による近似で、Obsidian の完全なリンク解決や本文の意味理解を再現しません。
- legacy 出力 `NotesRescuedByGeneratedNetwork` は native 孤立数を代入した潜在 coverage 数です。生成物を検査して実際の救済を確認した値ではありません。
- 生成後に全ノートが接続済みに見えても、知識ネットワークの品質を保証しません。
- 生成モードは graph の表示設定を変更します。既存設定のバックアップと差分確認が必要です。
- 古い生成物を自動削除しません。所有する生成物と手書きノートを区別し、別の明示レビューで扱います。
- 対象は Windows と Windows PowerShell 5.1 以降です。macOS / Linux の PowerShell 7 での動作は保証していません。相対 path は Windows / POSIX の区切り文字を共通化していますが、fixture 検査と実機での確認は別です。
- file / directory の symlink・junction 等の reparse point は列挙対象外です。壊れたリンクや vault 外のリンク先を読まず、リンクそのものを変更・削除しません。
- `tools/public-safety-scan.ps1` は文字列パターンによる簡易検査で、秘密情報や個人情報が無いことを保証するものではありません。
- 診断結果に含まれるノート名や個人情報を、そのまま公開 repository へ保存しないでください。

## 検証

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-obsidian-graph-network.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\public-safety-scan.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify-obsidian-graph-network.ps1
```

test harness は一時 fixture を使用します。fixture 成功を実 vault での運用確認に読み替えません。verification command の `OperationalGuaranteeOk : True` と `ImplementationResidualWork : 0` も検査対象の範囲で解釈し、意味的な品質保証とは分けて扱います。

## ファイルと編集責務

- `tools/audit-obsidian-graph-network.ps1`: 通常の読取り専用入口。
- `tools/obsidian-graph-network-lib.ps1`: updater・audit・test harness が共有する走査・除外・接続分析。
- `tools/update-obsidian-graph-network.ps1`: 任意の生成・設定反映。
- `tools/test-obsidian-graph-network.ps1`: local test harness。
- `tools/verify-obsidian-graph-network.ps1`: 実装・運用チェックをまとめて確認する aggregate verification。
- `tools/public-safety-scan.ps1`: 公開前の safety scan。
- [runbook](tools/obsidian-graph-network-runbook.md): 運用・復元上の注意。
- [エージェント用プロンプト](tools/obsidian-graph-network-generic-windows-prompt.md): 診断を先に行う操作手順。
- [GITHUB_SETTINGS.md](GITHUB_SETTINGS.md): GitHub repository settings の日本語メモ。

## 公開ステータス

この repository は 2026-07-04 に repository-specific approval を得て公開済みです (記録: [PUBLIC_READY.md](PUBLIC_READY.md))。repository visibility change、announcement、broad sharing には、引き続き明示的な human review と approval が必要です。ライセンスは [MIT](LICENSE) です。
