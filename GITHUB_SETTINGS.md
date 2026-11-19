# GitHub Repository Settings

この repository は 2026-07-04 に repository-specific approval を得て公開済みです (承認記録は `PUBLIC_READY.md`)。visibility の再変更や release activity には、引き続き明示的な approval が必要です。

## 基本設定

- Visibility: `PUBLIC`
- Default branch: `main`
- Description: `Obsidianのノート本文を編集せずにgraph接続性を保証するWindows向けプロンプトとリファレンス実装`
- Wiki: off
- Projects: off
- Issues: on

## Pull Request / Merge 設定

- Squash merge: on
- Merge commit: off
- Rebase merge: off
- Delete branch on merge: on
- Auto merge: off
- Update branch: on

この repository では、履歴を読みやすく保つために squash merge を基本にします。

## 公開前の必須確認

- `PUBLIC_READY.md` の checklist を確認する。
- `tools\public-safety-scan.ps1` を実行する。
- `tools\verify-obsidian-graph-network.ps1` を実行する。
- commit history に secret、personal path、private vault contents が含まれていないことを確認する。
- public visibility change は、対象 repository 名と操作内容を明示して approval を得てから行う。
