# Public Readiness Checklist

Status: public release 未承認。

Machine-readable status: not approved for public release.

automated checks が通っても、publication approval にはなりません。GitHub public visibility、announcement、broad sharing、release activity には、明示的な human review と approval が必要です。

## Public Release 前に必要な確認

- [ ] tracked files 全体の human review が完了している。
- [ ] README の public context と setup accuracy を確認した。
- [ ] LICENSE を確認し、受け入れた。
- [ ] SECURITY.md を確認した。
- [ ] GITHUB_SETTINGS.md を確認した。
- [ ] secret scan が完了し、actionable secrets が 0。
- [ ] personal path scan が完了し、未承認の personal paths が 0。
- [ ] large/generated local artifacts が untracked かつ ignored。
- [ ] `tools\test-obsidian-graph-network.ps1` が pass。
- [ ] `tools\public-safety-scan.ps1` が pass。
- [ ] repository visibility を変更する前に commit history を確認した。
- [ ] repository-specific approval を得てから public 化する。

## 既知のレビュー観点

- reference scripts には、内部運用由来の FDE-flavored naming が一部残っている。public launch 前に、維持・改名・説明追加のどれにするか確認する。
- primary public artifact は generic Windows prompt。
