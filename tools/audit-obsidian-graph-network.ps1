#Requires -Version 5.1

param(
  [string]$Vault,
  [int]$Top = 20,
  [string]$ReportDirectory,
  [int]$SmallIslandMaxSize = 5
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'obsidian-graph-network-lib.ps1')

# ---- read-only native connectivity audit ----
#
# READ-ONLY BY DEFAULT. Without -ReportDirectory this diagnostic never writes,
# creates, or deletes anything in the vault or the repo, never touches the
# generated _graph-network folder, and never invokes the updater. With
# -ReportDirectory it writes only graph-audit.json, graph-audit.md and
# graph-audit.base into that one folder, and never edits a note. It measures the vault's own (native) wikilink
# connectivity with the machine-added coverage edges removed, so orphans and
# fragmentation that the generated network otherwise hides stay visible.

if ([string]::IsNullOrWhiteSpace($Vault)) {
  throw ("Vault path is required. Usage: audit-obsidian-graph-network.ps1 -Vault <vault-directory> [-Top <n, orphan sample size, default 20>] [-ReportDirectory <folder>] [-SmallIslandMaxSize <n, default 5>]")
}

if (-not (Test-Path -LiteralPath $Vault -PathType Container)) {
  throw "Vault directory does not exist: $Vault"
}

$Vault = (Resolve-Path -LiteralPath $Vault).Path

if ($Top -lt 0) {
  throw "Top must be zero or greater."
}

if ($SmallIslandMaxSize -lt 2) {
  throw "SmallIslandMaxSize must be 2 or greater."
}

# The report folder is resolved before the walk. When it sits inside the vault,
# its files are left out of the measured notes, so the report never measures
# itself. Writing into the generated network folder is refused.
$reportFull = $null
$reportRelative = $null
if (-not [string]::IsNullOrWhiteSpace($ReportDirectory)) {
  $reportFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory).TrimEnd([char[]]@('\', '/'))
  $vaultPrefix = $Vault.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
  if ($reportFull.StartsWith($vaultPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    $reportRelative = ($reportFull.Substring($vaultPrefix.Length) -replace '\\', '/')
    $firstPart = $reportRelative.Split('/')[0]
    if ($firstPart -ieq $script:GraphNetGraphNetworkFolder) {
      throw ("ReportDirectory must not be inside the generated {0} folder." -f $script:GraphNetGraphNetworkFolder)
    }
  } elseif ($reportFull -ieq $Vault.TrimEnd([char[]]@('\', '/'))) {
    throw "ReportDirectory must be a folder, not the vault root itself."
  }
}

# Covered notes: reuse the same pruned walk and exclusion predicate as the
# updater so the audit measures exactly the note set the generated network
# covers. Get-GraphNetCoveredNoteFiles is read-only (Get-ChildItem only) and
# never creates the _graph-network folder.
$notes = @(Get-GraphNetCoveredNoteFiles -Vault $Vault)
if ($null -ne $reportRelative) {
  $reportPrefix = $reportFull + [System.IO.Path]::DirectorySeparatorChar
  $notes = @($notes | Where-Object { -not $_.FullName.StartsWith($reportPrefix, [System.StringComparison]::OrdinalIgnoreCase) })
}

$native = Get-GraphNetNativeGraph -Vault $Vault -Notes $notes

$degrees = [int[]]@($native.Nodes | ForEach-Object { $native.Adjacency[$_].Count })

$orphanNodes = [string[]]@($native.Nodes | Where-Object { $native.Adjacency[$_].Count -eq 0 })
[System.Array]::Sort($orphanNodes, [System.StringComparer]::Ordinal)
$orphanSample = @($orphanNodes | Select-Object -First $Top)

$componentStats = Get-GraphNetComponentStats -Adjacency $native.Adjacency

if ($degrees.Count -gt 0) {
  $degreeMin = [int]($degrees | Measure-Object -Minimum).Minimum
  $degreeMax = [int]($degrees | Measure-Object -Maximum).Maximum
} else {
  $degreeMin = 0
  $degreeMax = 0
}
$degreeMedian = Get-GraphNetMedian -Values $degrees

# Every covered note gets two generated coverage edges, so the notes the
# generated network rescues from isolation are exactly the native orphans.
$rescued = $orphanNodes.Count

$result = [pscustomobject]@{
  Vault = $Vault
  CoveredNotes = $native.Nodes.Count
  OrphanNotes = $orphanNodes.Count
  OrphanSample = $orphanSample
  NativeConnectedComponents = $componentStats.ComponentCount
  LargestComponentSize = $componentStats.LargestComponentSize
  NativeDegreeMin = $degreeMin
  NativeDegreeMedian = $degreeMedian
  NativeDegreeMax = $degreeMax
  UnresolvedLinks = $native.UnresolvedLinks
  NotesRescuedByGeneratedNetwork = $rescued
}

if ($null -ne $reportFull) {
  New-Item -ItemType Directory -Force -Path $reportFull | Out-Null
  $components = Get-GraphNetComponents -Adjacency $native.Adjacency
  $reportData = Get-GraphNetAuditReportData -Summary $result -Orphans $orphanNodes -Components $components -UnresolvedDetails $native.UnresolvedLinkDetails -SmallIslandMaxSize $SmallIslandMaxSize
  $excluded = @($script:GraphNetGraphNetworkFolder)
  if ($null -ne $reportRelative) {
    $excluded += $reportRelative
  }
  $reportUpdated = 0
  if (Write-GraphNetReportFile -Path (Join-Path $reportFull $script:GraphNetReportJsonName) -Content ($reportData | ConvertTo-Json -Depth 8)) { $reportUpdated++ }
  if (Write-GraphNetReportFile -Path (Join-Path $reportFull $script:GraphNetReportMarkdownName) -Content (ConvertTo-GraphNetAuditMarkdown -Data $reportData)) { $reportUpdated++ }
  if (Write-GraphNetReportFile -Path (Join-Path $reportFull $script:GraphNetReportBaseName) -Content (ConvertTo-GraphNetAuditBase -ExcludedFolders $excluded)) { $reportUpdated++ }
  $result | Add-Member -NotePropertyName ReportDirectory -NotePropertyValue $reportFull
  $result | Add-Member -NotePropertyName ReportUpdatedFiles -NotePropertyValue $reportUpdated
}

# Human-readable summary on the information stream (Write-Host), leaving the
# machine-readable object as the sole success-stream output.
Write-Host ''
Write-Host 'Native graph connectivity audit (read-only, generated links excluded)'
Write-Host ('  Vault:                          {0}' -f $result.Vault)
Write-Host ('  Covered notes:                  {0}' -f $result.CoveredNotes)
Write-Host ('  Orphan notes (native degree 0): {0}' -f $result.OrphanNotes)
Write-Host ('  Native connected components:    {0}' -f $result.NativeConnectedComponents)
Write-Host ('  Largest component size:         {0}' -f $result.LargestComponentSize)
Write-Host ('  Native degree min/median/max:   {0} / {1} / {2}' -f $result.NativeDegreeMin, $result.NativeDegreeMedian, $result.NativeDegreeMax)
Write-Host ('  Unresolved links:               {0}' -f $result.UnresolvedLinks)
Write-Host ('  Notes rescued by generated net: {0}' -f $result.NotesRescuedByGeneratedNetwork)
if ($orphanSample.Count -gt 0) {
  Write-Host ('  Orphan sample (up to {0}):' -f $Top)
  foreach ($orphan in $orphanSample) {
    Write-Host ('    - {0}' -f $orphan)
  }
}
if ($null -ne $reportFull) {
  Write-Host ('  Report:                         {0} ({1} file(s) updated)' -f $reportFull, $result.ReportUpdatedFiles)
}
Write-Host ''

$result
