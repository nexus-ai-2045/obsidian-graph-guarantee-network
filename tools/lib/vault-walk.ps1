#Requires -Version 5.1

# Vault paths and the note walker: which Markdown files count as covered notes.
# Loaded by obsidian-graph-network-lib.ps1. Do not dot-source this file on its own.

function Get-GraphNetGraphNetworkPath {
  param([string]$Vault)
  return (Join-Path $Vault $script:GraphNetGraphNetworkFolder)
}

function Get-GraphNetRelativePathParts {
  param(
    [string]$Path,
    [string]$Vault
  )

  return @($Path.Substring($Vault.Length).Split($script:GraphNetPathSeparators, [System.StringSplitOptions]::RemoveEmptyEntries))
}

function Get-GraphNetWikilinkUnsafeNotePaths {
  param(
    [object[]]$Notes = @(),
    [string]$Vault
  )

  $unsafe = [string[]]@($Notes | ForEach-Object {
    (Get-GraphNetRelativePathParts -Path $_.FullName -Vault $Vault) -join '/'
  } | Where-Object { $_.IndexOfAny($script:GraphNetWikilinkUnsafeChars) -ge 0 })
  [System.Array]::Sort($unsafe, [System.StringComparer]::Ordinal)
  return @($unsafe)
}

function ConvertTo-GraphNetWikiTarget {
  param(
    [string]$Path,
    [string]$Vault
  )

  $relative = (Get-GraphNetRelativePathParts -Path $Path -Vault $Vault) -join '/'
  if (-not $relative.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Expected markdown note path to end with .md: $Path"
  }

  return $relative.Substring(0, $relative.Length - 3)
}
function Test-GraphNetExcludedPathPart {
  param(
    [string]$Part,
    [bool]$TopLevel = $false,
    [bool]$IsFile = $false
  )

  # Single per-segment exclusion source shared by Test-GraphNetCoveredNotePath
  # and the pruned vault walk in Get-GraphNetCoveredNoteFiles, so file filtering
  # and directory pruning can never disagree about what is excluded.
  if ($TopLevel -and ($script:GraphNetGraphExcludedTopFolders -contains $Part)) {
    return $true
  }
  if ($Part.StartsWith('.') -and $Part -ne '.archive') {
    return $true
  }
  if ($script:GraphNetGraphExcludedPathParts -contains $Part) {
    return $true
  }
  # Cache folders such as build-cache hold tool output. A note whose own file
  # name mentions cache (cache-invalidation.md) is still a note.
  if ((-not $IsFile) -and $Part.ToLowerInvariant().Contains('cache')) {
    return $true
  }
  return $false
}

function Test-GraphNetCoveredNotePath {
  param(
    [string]$Path,
    [string]$Vault
  )

  $parts = @(Get-GraphNetRelativePathParts -Path $Path -Vault $Vault)
  if ($parts.Count -eq 0) {
    return $false
  }
  for ($i = 0; $i -lt $parts.Count; $i++) {
    if (Test-GraphNetExcludedPathPart -Part $parts[$i] -TopLevel ($i -eq 0) -IsFile ($i -eq ($parts.Count - 1))) {
      return $false
    }
  }
  return $true
}

function Get-GraphNetCoveredNoteFiles {
  param([string]$Vault)

  # Iterative vault walk that prunes excluded directories at traversal time
  # instead of enumerating everything recursively and filtering afterwards,
  # so large system trees such as node_modules or .git are never descended
  # into. Pruning and the final per-file check both go through
  # Test-GraphNetExcludedPathPart, which keeps the covered note set identical to
  # a full recursive scan filtered by Test-GraphNetCoveredNotePath.
  $notes = [System.Collections.Generic.List[object]]::new()
  $pending = [System.Collections.Generic.Stack[object]]::new()
  $pending.Push([pscustomobject]@{ Path = $Vault; TopLevel = $true })

  while ($pending.Count -gt 0) {
    $current = $pending.Pop()
    # -Force keeps hidden entries visible, matching the previous
    # Get-ChildItem -Recurse -Force scan (for example work\.archive notes).
    foreach ($entry in @(Get-ChildItem -LiteralPath $current.Path -Force)) {
      if ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        continue
      }
      if ($entry.PSIsContainer) {
        if (-not (Test-GraphNetExcludedPathPart -Part $entry.Name -TopLevel $current.TopLevel)) {
          $pending.Push([pscustomobject]@{ Path = $entry.FullName; TopLevel = $false })
        }
      } elseif (($entry.Name -like '*.md') -and (Test-GraphNetCoveredNotePath -Path $entry.FullName -Vault $Vault)) {
        $notes.Add($entry)
      }
    }
  }

  return @($notes | Sort-Object FullName)
}
