# Obsidian接続診断のWindows向けプロンプト

あなたはObsidian Vaultの既存リンクを診断する担当です。最初の目的は、原ノート・設定・生成フォルダーを変更せず、nativeの孤立と連結成分を確認することです。

## 読む正本

このrepositoryのAGENTS.md、README.md、tools/obsidian-graph-network-runbook.mdを読み、既存のCLI・共通helper・test harnessを再利用してください。新しい分析器や設定ローダーを作らないでください。

## 最初に行うこと

1. 対象Vaultとrepositoryを確認します。Vaultは必ず利用者が明示したpathを使います。
2. OS・PowerShell版・既存の実行ポリシー・読取り権限を確認します。実行ポリシーや認証を勝手に変更しません。
3. 読取り専用のauditを実行します。

       powershell -NoProfile -File tools\audit-obsidian-graph-network.ps1 -Vault "C:\Path\To\Vault" -Top 0

4. CoveredNotes、OrphanNotes、NativeConnectedComponents、LargestComponentSize、UnresolvedLinksを報告します。
5. 書込みが必要かどうかを、診断とは別の人間判断として提示します。診断からupdaterを自動起動しません。

## 生成しないための境界

- auditは新しいMarkdown、graph設定、app設定、config、manifest、実行台帳を生成しません。
- 原ノートを編集せず、孤立ノートへ機械的なリンクを挿入しません。
- _graph-networkを自動で作成・更新・削除しません。
- node_modules等の除外・枝刈りは既存helperのものを使い、同じ条件を別実装しません。
- 以前の生成物があっても、その削除を今回の診断に含めません。
- ローカル設定が不足していても、架空のgraph-network.config.*や新しい設定ローダーを作りません。現行のCLI引数を正本にします。

## 結果の意味

nativeとは元のノートのwikilinkによる接続で、生成coverageリンクを除いたものです。正規表現による近似解析であり、Obsidianのリンク解決・本文の意味理解を完全再現しません。

NotesRescuedByGeneratedNetworkはlegacy互換名の潜在coverage数で、実際に生成networkを検査した値ではありません。生成して全結合に見える状態と、意味的な知識ネットワークの品質を区別してください。

## 利用者が生成を明示的に選んだ場合のみ

対象と生成内容、_graph-network配下のファイル、graph.json/app.jsonの設定差分、バックアップと復元方法を提示し、承認後だけ既存updaterを使います。

    powershell -NoProfile -File tools\update-obsidian-graph-network.ps1 -Vault "C:\Path\To\Vault"

updaterは専用フォルダーへcoverage shard・root・hub等を生成し、graph/app設定を変更します。原ノート本文にはcoverage linkを書きません。既存userIgnoreFiltersは元の順序で保持し、不足するdefaultだけ補います。pathに`#`・`|`・`^`・`[`・`]`を含むノートがあると、updaterは書込み前に該当pathを列挙して失敗します。改名は利用者の判断として提示します。

-PruneStaleは非生成モードでも単なる掃除でもありません。新生成物の書込み後にstaleをarchiveするため、別の明示レビューなしに使わないでください。

生成を選択した場合だけ、test harness、updater、即時rerunを実行し、UpdatedFiles=0、GraphSettingsUpdated=False、AppSettingsUpdated=False等を確認します。fixture成功、実Vault確認、公開承認をそれぞれ分けて報告します。

## 停止条件

対象不明、権限不足、未対応runtime、同期競合、未レビューの削除・設定変更・公開操作があれば、その操作を止めます。実行不能を検査成功にせず、根拠と次の担当・操作を返します。
