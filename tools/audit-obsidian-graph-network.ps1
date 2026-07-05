#Requires -Version 5.1

param(
  [string]$Vault,
  [int]$Top = 20
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'obsidian-graph-network-lib.ps1')

# ---- read-only native connectivity audit ----
#
# STRICTLY READ-ONLY. This diagnostic never writes, creates, or deletes anything
# in the vault or the repo, and never touches the generated _graph-network
# folder or invokes the updater. It measures the vault's own (native) wikilink
# connectivity with the machine-added coverage edges removed, so orphans and
# fragmentation that the generated network otherwise hides stay visible.

if ([string]::IsNullOrWhiteSpace($Vault)) {
  throw ("Vault path is required. Usage: audit-obsidian-graph-network.ps1 -Vault <vault-directory> [-Top <n, orphan sample size, default 20>]")
}

if (-not (Test-Path -LiteralPath $Vault -PathType Container)) {
  throw "Vault directory does not exist: $Vault"
}

$Vault = (Resolve-Path -LiteralPath $Vault).Path

if ($Top -lt 0) {
  throw "Top must be zero or greater."
}

# Covered notes: reuse the same pruned walk and exclusion predicate as the
# updater so the audit measures exactly the note set the generated network
# covers. Get-GraphNetCoveredNoteFiles is read-only (Get-ChildItem only) and
# never creates the _graph-network folder.
$notes = @(Get-GraphNetCoveredNoteFiles -Vault $Vault)

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
Write-Host ''

$result
