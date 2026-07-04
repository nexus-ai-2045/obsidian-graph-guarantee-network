#Requires -Version 5.1

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

# FDE graph color palette (Obsidian RGB integers). Each lane color is defined
# once here and reused by both the lane hub color group and its matching
# top-level folder color groups, so a lane never carries two divergent colors.
$script:FdeColorFdeGold = 16763904   # FDE anchors and brain/fde notes
$script:FdeColorIntake = 6737151     # intake / unclassified lane
$script:FdeColorCaptureLog = 56831   # capture log lane
$script:FdeColorDecision = 16737894  # decision system lane
$script:FdeColorEvidence = 52267     # evidence / research lane
$script:FdeColorExecution = 54117    # execution lane
$script:FdeColorIdentity = 12255487  # identity / strategy lane
$script:FdeColorOther = 10066329     # other lane and archive/
$script:FdeColorShard = 8947848      # coverage shards and reports/
$script:FdeColorLanes = 14431557     # lanes/ decoration only
$script:FdeColorPractice = 3381759   # lessons-learned/playbooks/patterns decoration
$script:FdeColorIdeas = 16747520     # ideas/AI-Bridge/nexus_ai decoration

# Single source of truth for the generated lane hubs. Everything lane-shaped is
# derived from this list: the updater builds its top-folder -> hub routing map
# and its hub file definitions from it, and Get-FdeGraphColorGroups derives the
# lane hub color groups from it. Order matters: it drives the Lane Hubs section
# order in FDE-NETWORK.md and the lane hub color group order in graph.json.
#   Hub        base file name (without .md) of the generated lane hub
#   Title      heading and link label for the hub
#   Color      Obsidian graph color shared with the lane's folder color groups
#   TopFolders top-level vault folders routed into this lane ('other' catches
#              everything else and therefore lists none)
$script:FdeLaneDefinitions = @(
  [ordered]@{ Hub = 'hub-intake--unclassified'; Title = 'Intake / Unclassified'; Color = $script:FdeColorIntake; TopFolders = @('inbox', 'drafts') },
  [ordered]@{ Hub = 'hub-lane--capture-log'; Title = 'Capture Log Lane'; Color = $script:FdeColorCaptureLog; TopFolders = @('dev', 'dev-log') },
  [ordered]@{ Hub = 'hub-lane--decision-system'; Title = 'Decision System Lane'; Color = $script:FdeColorDecision; TopFolders = @('decisions', 'designs') },
  [ordered]@{ Hub = 'hub-lane--evidence-research'; Title = 'Evidence / Research Lane'; Color = $script:FdeColorEvidence; TopFolders = @('research', 'research-digest', 'references') },
  [ordered]@{ Hub = 'hub-lane--execution'; Title = 'Execution Lane'; Color = $script:FdeColorExecution; TopFolders = @('work', 'handoffs', 'projects') },
  [ordered]@{ Hub = 'hub-lane--identity-strategy'; Title = 'Identity / Strategy Lane'; Color = $script:FdeColorIdentity; TopFolders = @('brain', 'lifeops') },
  [ordered]@{ Hub = 'hub-lane--other'; Title = 'Other Lane'; Color = $script:FdeColorOther; TopFolders = @() }
)

function Get-FdeLaneDefinitions {
  # Return the shared lane model. Callers derive the hub routing map, the hub
  # file definitions, and the lane hub color groups from this single list.
  return @($script:FdeLaneDefinitions)
}

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

function Test-FdeExcludedPathPart {
  param(
    [string]$Part,
    [bool]$TopLevel = $false
  )

  # Single per-segment exclusion source shared by Test-FdeCoveredNotePath and
  # the pruned vault walk in Get-FdeCoveredNoteFiles, so file filtering and
  # directory pruning can never disagree about what is excluded.
  if ($TopLevel -and ($script:FdeGraphExcludedTopFolders -contains $Part)) {
    return $true
  }
  if ($Part.StartsWith('.') -and $Part -ne '.archive') {
    return $true
  }
  if ($script:FdeGraphExcludedPathParts -contains $Part) {
    return $true
  }
  if ($Part.ToLowerInvariant().Contains('cache')) {
    return $true
  }
  return $false
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
  for ($i = 0; $i -lt $parts.Count; $i++) {
    if (Test-FdeExcludedPathPart -Part $parts[$i] -TopLevel ($i -eq 0)) {
      return $false
    }
  }
  return $true
}

function Get-FdeCoveredNoteFiles {
  param([string]$Vault)

  # Iterative vault walk that prunes excluded directories at traversal time
  # instead of enumerating everything recursively and filtering afterwards,
  # so large system trees such as node_modules or .git are never descended
  # into. Pruning and the final per-file check both go through
  # Test-FdeExcludedPathPart, which keeps the covered note set identical to
  # a full recursive scan filtered by Test-FdeCoveredNotePath.
  $notes = [System.Collections.Generic.List[object]]::new()
  $pending = [System.Collections.Generic.Stack[object]]::new()
  $pending.Push([pscustomobject]@{ Path = $Vault; TopLevel = $true })

  while ($pending.Count -gt 0) {
    $current = $pending.Pop()
    # -Force keeps hidden entries visible, matching the previous
    # Get-ChildItem -Recurse -Force scan (for example work\.archive notes).
    foreach ($entry in @(Get-ChildItem -LiteralPath $current.Path -Force)) {
      if ($entry.PSIsContainer) {
        # Reparse points (junctions / symlinks) are not descended into, so
        # the walk cannot cycle through self-referencing links.
        if ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
          continue
        }
        if (-not (Test-FdeExcludedPathPart -Part $entry.Name -TopLevel $current.TopLevel)) {
          $pending.Push([pscustomobject]@{ Path = $entry.FullName; TopLevel = $false })
        }
      } elseif (($entry.Name -like '*.md') -and (Test-FdeCoveredNotePath -Path $entry.FullName -Vault $Vault)) {
        $notes.Add($entry)
      }
    }
  }

  return @($notes | Sort-Object FullName)
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

function Get-FdeNetworkAdjacency {
  param([string]$NetworkPath)

  # Build the undirected wikilink adjacency between generated network files.
  # Only files carrying the network_generated marker participate, so manual
  # notes or archived leftovers inside the folder never join the graph model.
  $encoding = [System.Text.UTF8Encoding]::new($false)
  $adjacency = @{}
  $contents = @{}

  Get-ChildItem -LiteralPath $NetworkPath -Filter '*.md' -File | ForEach-Object {
    $content = [System.IO.File]::ReadAllText($_.FullName, $encoding)
    if ($content -match '(?m)^network_generated:\s*true\s*$') {
      $node = '{0}/{1}' -f $script:FdeGraphNetworkFolder, [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
      $adjacency[$node] = [System.Collections.Generic.HashSet[string]]::new()
      $contents[$node] = $content
    }
  }

  $linkPattern = '\[\[({0}/[^|\]]+)' -f [regex]::Escape($script:FdeGraphNetworkFolder)
  foreach ($node in @($adjacency.Keys)) {
    foreach ($match in [regex]::Matches($contents[$node], $linkPattern)) {
      $target = $match.Groups[1].Value
      if (($target -ne $node) -and $adjacency.ContainsKey($target)) {
        $null = $adjacency[$node].Add($target)
        $null = $adjacency[$target].Add($node)
      }
    }
  }

  return $adjacency
}

function Get-FdeNetworkConnectedComponentCount {
  param([string]$NetworkPath)

  # BFS over the generated-file wikilink graph. The guarantee requires exactly
  # one connected component: shard ring -> lane hub -> root anchors must never
  # split into islands, because shards no longer link the roots directly.
  $adjacency = Get-FdeNetworkAdjacency -NetworkPath $NetworkPath
  $visited = [System.Collections.Generic.HashSet[string]]::new()
  $components = 0

  foreach ($start in @($adjacency.Keys | Sort-Object)) {
    if ($visited.Contains($start)) {
      continue
    }
    $components++
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($start)
    $null = $visited.Add($start)
    while ($queue.Count -gt 0) {
      $current = $queue.Dequeue()
      foreach ($neighbor in $adjacency[$current]) {
        if (-not $visited.Contains($neighbor)) {
          $null = $visited.Add($neighbor)
          $queue.Enqueue($neighbor)
        }
      }
    }
  }

  return $components
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

function New-FdeColorGroup {
  param(
    [string]$Query,
    [int]$Rgb
  )

  return [ordered]@{ query = $Query; color = [ordered]@{ a = 1; rgb = $Rgb } }
}

function Get-FdeGraphColorGroups {
  $groups = [System.Collections.Generic.List[object]]::new()

  # Leading FDE anchor and top-level folder color groups (graph view decoration).
  # These reference the shared palette so folder colors never diverge from the
  # lane hub color that shares the same lane. The order and membership are kept
  # explicit because they do not map one-to-one onto the lane model (some lanes
  # have folders without a color group, and several folders here belong to no
  # lane at all).
  $groups.Add((New-FdeColorGroup 'path:"brain/fde/"' $script:FdeColorFdeGold))
  $groups.Add((New-FdeColorGroup 'path:"brain/"' $script:FdeColorIdentity))
  $groups.Add((New-FdeColorGroup 'path:"inbox/"' $script:FdeColorIntake))
  $groups.Add((New-FdeColorGroup 'path:"work/"' $script:FdeColorExecution))
  $groups.Add((New-FdeColorGroup 'path:"projects/"' $script:FdeColorExecution))
  $groups.Add((New-FdeColorGroup 'path:"handoffs/"' $script:FdeColorExecution))
  $groups.Add((New-FdeColorGroup 'path:"decisions/"' $script:FdeColorDecision))
  $groups.Add((New-FdeColorGroup 'path:"designs/"' $script:FdeColorDecision))
  $groups.Add((New-FdeColorGroup 'path:"research/"' $script:FdeColorEvidence))
  $groups.Add((New-FdeColorGroup 'path:"research-digest/"' $script:FdeColorEvidence))
  $groups.Add((New-FdeColorGroup 'path:"references/"' $script:FdeColorEvidence))
  $groups.Add((New-FdeColorGroup 'path:"dev/"' $script:FdeColorCaptureLog))
  $groups.Add((New-FdeColorGroup 'path:"dev-log/"' $script:FdeColorCaptureLog))
  $groups.Add((New-FdeColorGroup 'path:"lanes/"' $script:FdeColorLanes))
  $groups.Add((New-FdeColorGroup 'path:"reports/"' $script:FdeColorShard))
  $groups.Add((New-FdeColorGroup 'path:"archive/"' $script:FdeColorOther))
  $groups.Add((New-FdeColorGroup 'path:"lessons-learned/"' $script:FdeColorPractice))
  $groups.Add((New-FdeColorGroup 'path:"playbooks/"' $script:FdeColorPractice))
  $groups.Add((New-FdeColorGroup 'path:"patterns/"' $script:FdeColorPractice))
  $groups.Add((New-FdeColorGroup 'path:"ideas/"' $script:FdeColorIdeas))
  $groups.Add((New-FdeColorGroup 'path:"lifeops/"' $script:FdeColorIdentity))
  $groups.Add((New-FdeColorGroup 'path:"AI-Bridge/"' $script:FdeColorIdeas))
  $groups.Add((New-FdeColorGroup 'path:"nexus_ai/"' $script:FdeColorIdeas))

  # Root anchors.
  $groups.Add((New-FdeColorGroup 'path:"_graph-network/FDE-NETWORK"' $script:FdeColorFdeGold))
  $groups.Add((New-FdeColorGroup 'path:"_graph-network/NETWORK-GUARANTEE"' $script:FdeColorFdeGold))

  # Lane hub color groups, derived from the shared lane model so hub names and
  # colors stay in lockstep with the updater's hub map and hub definitions.
  foreach ($lane in $script:FdeLaneDefinitions) {
    $groups.Add((New-FdeColorGroup ('path:"_graph-network/{0}"' -f $lane.Hub) $lane.Color))
  }

  # Coverage shards.
  $groups.Add((New-FdeColorGroup ('path:"_graph-network/{0}"' -f $script:FdeCoverageShardPrefix) $script:FdeColorShard))

  return @($groups)
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
