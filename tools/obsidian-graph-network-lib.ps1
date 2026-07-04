$script:FdeGraphNetworkFolder = '_graph-network'
$script:FdeCoverageShardPrefix = 'fde-coverage-shard'
$script:FdeGraphExcludedTopFolders = @(
  '.obsidian',
  '.smart-env',
  '.trash',
  '.git',
  '.github',
  '.claude',
  '.cmux',
  '.gemini',
  '.pytest_cache',
  '_workspace-local-secrets',
  'node_modules',
  'tools',
  $script:FdeGraphNetworkFolder
)
$script:FdeGraphExcludedPathParts = @(
  '.git',
  '.github',
  '.pytest_cache',
  '__pycache__',
  'node_modules',
  '.raw',
  'cache',
  'vendor',
  $script:FdeGraphNetworkFolder
)

function Get-FdeGraphNetworkPath {
  param([string]$Vault)
  return (Join-Path $Vault $script:FdeGraphNetworkFolder)
}

function ConvertTo-FdeWikiTarget {
  param(
    [string]$Path,
    [string]$Vault
  )

  $relative = $Path.Substring($Vault.Length).TrimStart('\')
  if (-not $relative.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Expected markdown note path to end with .md: $Path"
  }

  $withoutExt = $relative.Substring(0, $relative.Length - 3)
  return ($withoutExt -replace '\\', '/')
}

function Test-FdeCoveredNotePath {
  param(
    [string]$Path,
    [string]$Vault
  )

  $relative = $Path.Substring($Vault.Length).TrimStart('\')
  $parts = @($relative -split '\\' | Where-Object { $_ })
  if ($parts.Count -eq 0) {
    return $false
  }
  $top = $parts[0]
  if ($script:FdeGraphExcludedTopFolders -contains $top) {
    return $false
  }
  foreach ($part in $parts) {
    if ($part.StartsWith('.') -and $part -ne '.archive') {
      return $false
    }
    if ($script:FdeGraphExcludedPathParts -contains $part) {
      return $false
    }
    if ($part.ToLowerInvariant().Contains('cache')) {
      return $false
    }
  }
  return $true
}

function Get-FdeStableBuckets {
  param(
    [string]$Target,
    [int]$Count
  )

  if ($Count -lt 1) {
    throw "Bucket count must be at least 1."
  }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Target.ToLowerInvariant())
    $hash = $sha.ComputeHash($bytes)
  } finally {
    $sha.Dispose()
  }

  $first = [int]([System.BitConverter]::ToUInt32($hash, 0) % $Count)
  $second = [int]([System.BitConverter]::ToUInt32($hash, 4) % $Count)
  # On a same-bucket collision, probe forward one step at a time so every
  # count greater than 1 always yields two distinct buckets. A fixed offset
  # (for example +17) breaks down when the count divides that offset.
  # Count 1 keeps the same bucket because no second bucket can exist.
  while (($Count -gt 1) -and ($second -eq $first)) {
    $second = ($second + 1) % $Count
  }

  return @([int]$first, [int]$second)
}

function Get-FdeDominantTop {
  param([object[]]$Items = @())

  # Count descending, then name ascending: a deterministic tie-break so
  # equal-sized groups always resolve to the same lane on every run.
  $groups = @($Items | Group-Object Top | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false })
  if ($groups.Count -gt 0) {
    return [string]$groups[0].Name
  }
  return ''
}

function Get-FdeAutoBucketCount {
  param([int]$CoveredNoteCount)

  if ($CoveredNoteCount -lt 0) {
    throw "Covered note count must be zero or greater."
  }

  # min(64, max(8, ceil(N / 16))): small vaults get a small shard ring
  # instead of a fixed 64-shard layout, large vaults stay capped at 64.
  $scaled = [int][System.Math]::Ceiling($CoveredNoteCount / 16.0)
  return [System.Math]::Min(64, [System.Math]::Max(8, $scaled))
}

function Get-FdeGraphIgnoreFilters {
  return @(
    '.git/',
    '.github/',
    '.obsidian/',
    '.smart-env/',
    '.trash/',
    '.pytest_cache/',
    '**/__pycache__/',
    '**/node_modules/',
    '**/.raw/',
    '**/cache/',
    '**/vendor/',
    '_workspace-local-secrets/',
    'tools/'
  )
}

function Get-FdeGraphSearchFilter {
  return '-path:".git" -path:".github" -path:".obsidian" -path:".smart-env" -path:".pytest_cache" -path:"__pycache__" -path:"node_modules" -path:"_workspace-local-secrets" -path:"tools" -path:"cache" -path:"vendor"'
}

function Get-FdeGraphColorGroups {
  return @(
    [ordered]@{ query = 'path:"brain/fde/"'; color = [ordered]@{ a = 1; rgb = 16763904 } },
    [ordered]@{ query = 'path:"brain/"'; color = [ordered]@{ a = 1; rgb = 12255487 } },
    [ordered]@{ query = 'path:"inbox/"'; color = [ordered]@{ a = 1; rgb = 6737151 } },
    [ordered]@{ query = 'path:"work/"'; color = [ordered]@{ a = 1; rgb = 54117 } },
    [ordered]@{ query = 'path:"projects/"'; color = [ordered]@{ a = 1; rgb = 54117 } },
    [ordered]@{ query = 'path:"handoffs/"'; color = [ordered]@{ a = 1; rgb = 54117 } },
    [ordered]@{ query = 'path:"decisions/"'; color = [ordered]@{ a = 1; rgb = 16737894 } },
    [ordered]@{ query = 'path:"designs/"'; color = [ordered]@{ a = 1; rgb = 16737894 } },
    [ordered]@{ query = 'path:"research/"'; color = [ordered]@{ a = 1; rgb = 52267 } },
    [ordered]@{ query = 'path:"research-digest/"'; color = [ordered]@{ a = 1; rgb = 52267 } },
    [ordered]@{ query = 'path:"references/"'; color = [ordered]@{ a = 1; rgb = 52267 } },
    [ordered]@{ query = 'path:"dev/"'; color = [ordered]@{ a = 1; rgb = 56831 } },
    [ordered]@{ query = 'path:"dev-log/"'; color = [ordered]@{ a = 1; rgb = 56831 } },
    [ordered]@{ query = 'path:"lanes/"'; color = [ordered]@{ a = 1; rgb = 14431557 } },
    [ordered]@{ query = 'path:"reports/"'; color = [ordered]@{ a = 1; rgb = 8947848 } },
    [ordered]@{ query = 'path:"archive/"'; color = [ordered]@{ a = 1; rgb = 10066329 } },
    [ordered]@{ query = 'path:"lessons-learned/"'; color = [ordered]@{ a = 1; rgb = 3381759 } },
    [ordered]@{ query = 'path:"playbooks/"'; color = [ordered]@{ a = 1; rgb = 3381759 } },
    [ordered]@{ query = 'path:"patterns/"'; color = [ordered]@{ a = 1; rgb = 3381759 } },
    [ordered]@{ query = 'path:"ideas/"'; color = [ordered]@{ a = 1; rgb = 16747520 } },
    [ordered]@{ query = 'path:"lifeops/"'; color = [ordered]@{ a = 1; rgb = 12255487 } },
    [ordered]@{ query = 'path:"AI-Bridge/"'; color = [ordered]@{ a = 1; rgb = 16747520 } },
    [ordered]@{ query = 'path:"nexus_ai/"'; color = [ordered]@{ a = 1; rgb = 16747520 } },
    [ordered]@{ query = 'path:"_graph-network/FDE-NETWORK"'; color = [ordered]@{ a = 1; rgb = 16763904 } },
    [ordered]@{ query = 'path:"_graph-network/NETWORK-GUARANTEE"'; color = [ordered]@{ a = 1; rgb = 16763904 } },
    [ordered]@{ query = 'path:"_graph-network/hub-intake--unclassified"'; color = [ordered]@{ a = 1; rgb = 6737151 } },
    [ordered]@{ query = 'path:"_graph-network/hub-lane--capture-log"'; color = [ordered]@{ a = 1; rgb = 56831 } },
    [ordered]@{ query = 'path:"_graph-network/hub-lane--decision-system"'; color = [ordered]@{ a = 1; rgb = 16737894 } },
    [ordered]@{ query = 'path:"_graph-network/hub-lane--evidence-research"'; color = [ordered]@{ a = 1; rgb = 52267 } },
    [ordered]@{ query = 'path:"_graph-network/hub-lane--execution"'; color = [ordered]@{ a = 1; rgb = 54117 } },
    [ordered]@{ query = 'path:"_graph-network/hub-lane--identity-strategy"'; color = [ordered]@{ a = 1; rgb = 12255487 } },
    [ordered]@{ query = 'path:"_graph-network/hub-lane--other"'; color = [ordered]@{ a = 1; rgb = 10066329 } },
    [ordered]@{ query = 'path:"_graph-network/fde-coverage-shard"'; color = [ordered]@{ a = 1; rgb = 8947848 } }
  )
}

function Get-RequiredFdeGraphColorQueries {
  return @(
    'path:"brain/fde/"',
    'path:"brain/"',
    'path:"inbox/"',
    'path:"work/"',
    'path:"research/"',
    'path:"decisions/"',
    'path:"_graph-network/FDE-NETWORK"',
    'path:"_graph-network/hub-lane--identity-strategy"',
    'path:"_graph-network/fde-coverage-shard"'
  )
}
