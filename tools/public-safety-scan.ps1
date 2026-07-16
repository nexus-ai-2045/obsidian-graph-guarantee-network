#Requires -Version 5.1

param(
  [string]$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
  throw 'ripgrep (rg) is required for the public safety scan.'
}

Push-Location -LiteralPath $Root
try {
  $secretPattern = '(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|BEGIN (RSA|OPENSSH|PRIVATE) KEY|(api[_-]?key|secret|password|passwd|client_secret|refresh_token|access_token)[''"]?\s*[:=]\s*[''"]?[A-Za-z0-9_./+=-]{12,})'
  # Do not hard-code personal identifiers (macOS usernames or private email addresses).
  # Detect generic path tokens instead. Cloud-sync names are scoped to a path separator
  # so prose that merely mentions Dropbox or OneDrive does not become a false positive.
  # Keep this source ASCII-only: Windows PowerShell 5.1 decodes UTF-8 without BOM
  # using the active system code page. Unicode safety terms stay equivalent via escapes.
  $personalPathPattern = '((^|[^A-Za-z0-9_])(C:\\Users\\|D:\\)|/Users/|-Users-|[\\/](Dropbox|OneDrive)|MyDocuments|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|__E\u30de\u30f3\u30ac|\u6210\u5e74|DL\u7248|torrent|DMM)'

  $secretMatches = @(rg --hidden -n -i $secretPattern . --glob '!.git/**' --glob '!d-drive-*.csv' --glob '!mydocuments-top-folder-summary.csv' --glob '!tools/public-safety-scan.ps1' 2>$null)
  if ($LASTEXITCODE -gt 1) {
    throw "ripgrep secret scan failed with exit code $LASTEXITCODE."
  }
  $pathMatches = @(rg --hidden -n -i $personalPathPattern . --glob '!.git/**' --glob '!d-drive-*.csv' --glob '!mydocuments-top-folder-summary.csv' --glob '!tools/public-safety-scan.ps1' 2>$null)
  if ($LASTEXITCODE -gt 1) {
    throw "ripgrep personal-path scan failed with exit code $LASTEXITCODE."
  }
  $publicReadyPath = Join-Path $Root 'PUBLIC_READY.md'
  $publicReadyText = if (Test-Path -LiteralPath $publicReadyPath -PathType Leaf) { Get-Content -LiteralPath $publicReadyPath -Raw -Encoding UTF8 } else { '' }
  # Repository-specific approval was granted on 2026-07-04. Keep this interlock tied
  # to the approved marker so wording drift or a rollback to not-approved fails closed.
  $publicReadinessFileOk = (
    ($publicReadyText -match 'Machine-readable status:\s*approved for public release') -and
    ($publicReadyText -match 'Repository-specific approval')
  )
  $untrackedPaths = @(git ls-files --others --exclude-standard)
  if ($LASTEXITCODE -ne 0) {
    throw "git ls-files failed with exit code $LASTEXITCODE."
  }
  $largeUntracked = @($untrackedPaths | ForEach-Object {
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
