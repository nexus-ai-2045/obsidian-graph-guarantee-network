#Requires -Version 5.1

param(
  [string]$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

function Add-Check {
  param(
    [System.Collections.Generic.List[object]]$Checks,
    [string]$Name,
    [bool]$Passed,
    [string]$Details = ''
  )

  $Checks.Add([pscustomobject]@{
    Name = $Name
    Passed = $Passed
    Details = $Details
  })
}

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
  throw "Root directory does not exist: $Root"
}

$Root = (Resolve-Path -LiteralPath $Root).Path
$checks = [System.Collections.Generic.List[object]]::new()

Push-Location -LiteralPath $Root
try {
  $requiredFiles = @(
    'README.md',
    'LICENSE',
    'SECURITY.md',
    'PUBLIC_READY.md',
    'tools\obsidian-graph-network-lib.ps1',
    'tools\update-obsidian-graph-network.ps1',
    'tools\test-obsidian-graph-network.ps1',
    'tools\public-safety-scan.ps1',
    'tools\obsidian-graph-network-runbook.md'
  )

  $missingFiles = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf) })
  Add-Check $checks 'required files exist' ($missingFiles.Count -eq 0) ($missingFiles -join ', ')

  $testOutput = & (Join-Path $Root 'tools\test-obsidian-graph-network.ps1')
  $testSummary = @($testOutput | Where-Object { $_ -is [pscustomobject] } | Select-Object -Last 1)[0]
  Add-Check $checks 'graph network test harness passes' ($testSummary.Failed -eq 0) ($testSummary | Out-String)

  $safety = @(& (Join-Path $Root 'tools\public-safety-scan.ps1') | Where-Object { $_ -is [pscustomobject] } | Select-Object -Last 1)[0]
  Add-Check $checks 'public safety scan passes' ($safety.PublicReady -eq $true) ($safety | Out-String)

  if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
    throw 'ripgrep (rg) is required for unresolved marker checks.'
  }

  $markerMatches = @(rg --hidden -n -i 'TODO|FIXME|残務|未実装|NotImplemented|stub|placeholder' . --glob '!.git/**' --glob '!tools/verify-obsidian-graph-network.ps1' 2>$null)
  Add-Check $checks 'no unresolved implementation markers' ($markerMatches.Count -eq 0) ($markerMatches -join [Environment]::NewLine)

  $gitStatus = @(git status --short)
  Add-Check $checks 'git worktree clean' ($gitStatus.Count -eq 0) ($gitStatus -join [Environment]::NewLine)
} finally {
  Pop-Location
}

$failed = @($checks | Where-Object { -not $_.Passed })
$checks | Format-Table -AutoSize

$result = [pscustomobject]@{
  Root = $Root
  Checks = $checks.Count
  Failed = $failed.Count
  Passed = $checks.Count - $failed.Count
  ImplementationResidualWork = $failed.Count
  OperationalGuaranteeOk = ($failed.Count -eq 0)
  PublicationRequiresHumanReview = $true
}

$result

if ($failed.Count -ne 0) {
  Write-Error ("Verification failed:{0}{1}" -f [Environment]::NewLine, (($failed | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Details }) -join [Environment]::NewLine))
  exit 1
}
