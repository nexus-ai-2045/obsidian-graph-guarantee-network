# Security Policy

## サポート状況

この project は experimental です。広く使う前に、publication-ready 状態を人間がレビューしてください。

## 脆弱性や安全上の問題を見つけた場合

public issue に secret、private vault contents、個人情報を貼らないでください。

問題の種類だけが分かる最小限の report を作成し、sensitive details は private channel で共有してください。

## Data Safety

この graph-network approach は、note 本文を編集しないことを前提にしています。生成ファイルは configured network folder の中に留めてください。

stale file の destructive handling は default で無効にしてください。

この project から作った repository を公開または共有する前に、local public-safety scan を実行し、commit history に secret、personal path、vault contents、generated artifacts が含まれていないか確認してください。
