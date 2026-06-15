param(
  [string]$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
  throw 'ripgrep (rg) is required for the public safety scan.'
}

Push-Location -LiteralPath $Root
try {
  $secretPattern = '(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|BEGIN (RSA|OPENSSH|PRIVATE) KEY|(api[_-]?key|secret|password|passwd|client_secret|refresh_token|access_token)\s*[:=]\s*[''"]?[A-Za-z0-9_./+=-]{12,})'
  # NOTE: 個人識別子 (mac username / 個人 email) はこの公開スクリプトに直書きしない。
  # 漏えいベクトルは汎用トークンで検出する: -Users- はダッシュ形パス (例 -Users-<name>-Projects),
  # Dropbox / OneDrive は cloud-sync フォルダだが、説明文中の語との誤検知を避けるため
  # パス区切り直後 ([\/]) のときだけ実パス成分として検出する。メールは汎用正規表現で捕捉。
  $personalPathPattern = '(C:\\Users\\|D:\\|/Users/|-Users-|[\\/](Dropbox|OneDrive)|MyDocuments|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|__Eマンガ|成年|DL版|torrent|DMM)'

  $secretMatches = @(rg --hidden -n -i $secretPattern . --glob '!.git/**' --glob '!d-drive-*.csv' --glob '!mydocuments-top-folder-summary.csv' --glob '!tools/public-safety-scan.ps1' 2>$null)
  $pathMatches = @(rg --hidden -n $personalPathPattern . --glob '!.git/**' --glob '!d-drive-*.csv' --glob '!mydocuments-top-folder-summary.csv' --glob '!tools/public-safety-scan.ps1' 2>$null)
  $publicReadyPath = Join-Path $Root 'PUBLIC_READY.md'
  $publicReadyText = if (Test-Path -LiteralPath $publicReadyPath -PathType Leaf) { Get-Content -LiteralPath $publicReadyPath -Raw -Encoding UTF8 } else { '' }
  $publicReadinessFileOk = (
    ($publicReadyText -match 'Machine-readable status:\s*not approved for public release') -and
    ($publicReadyText -match 'Repository-specific approval')
  )
  $largeUntracked = @(git ls-files --others --exclude-standard | ForEach-Object {
    $item = Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue
    if ($item -and $item.Length -gt 1048576) {
      [pscustomobject]@{ Path = $_; Bytes = $item.Length }
    }
  })

  [pscustomobject]@{
    Root = (Get-Location).Path
    SecretPatternMatches = $secretMatches.Count
    PersonalPathMatches = $pathMatches.Count
    LargeUntrackedFiles = $largeUntracked.Count
    PublicReadinessFileOk = $publicReadinessFileOk
    SecretMatches = $secretMatches
    PersonalPathMatchesList = $pathMatches
    LargeUntracked = $largeUntracked
    PublicReady = (($secretMatches.Count -eq 0) -and ($pathMatches.Count -eq 0) -and ($largeUntracked.Count -eq 0) -and $publicReadinessFileOk)
  }
} finally {
  Pop-Location
}
