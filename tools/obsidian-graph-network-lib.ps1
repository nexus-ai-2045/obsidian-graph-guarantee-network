#Requires -Version 5.1

$script:GraphNetGraphNetworkFolder = '_graph-network'
$script:GraphNetCoverageShardPrefix = 'coverage-shard'
$script:GraphNetGraphExcludedTopFolders = @(
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
  $script:GraphNetGraphNetworkFolder
)
$script:GraphNetGraphExcludedPathParts = @(
  '.git',
  '.github',
  '.pytest_cache',
  '__pycache__',
  'node_modules',
  '.raw',
  'cache',
  'vendor',
  $script:GraphNetGraphNetworkFolder
)

# Graph color palette (Obsidian RGB integers). The anchors, coverage shards, and
# the intake hub carry fixed colors; each lane hub takes the next palette color,
# cycled deterministically in top-folder order. No personal folder name is ever
# hard-coded here: lane colors are assigned positionally by Get-GraphNetLaneDefinitions.
$script:GraphNetColorAnchor = 16763904   # graph-network-root and NETWORK-GUARANTEE
$script:GraphNetColorShard = 8947848     # coverage shards
$script:GraphNetColorIntake = 6737151    # intake / unclassified hub (catch-all)
$script:GraphNetLaneHubPalette = @(
  56831,     # lane color 0
  16737894,  # lane color 1
  52267,     # lane color 2
  54117,     # lane color 3
  12255487,  # lane color 4
  10066329,  # lane color 5
  3381759,   # lane color 6
  16747520,  # lane color 7
  14431557,  # lane color 8
  16763904   # lane color 9
)

function Get-GraphNetGraphNetworkPath {
  param([string]$Vault)
  return (Join-Path $Vault $script:GraphNetGraphNetworkFolder)
}

function ConvertTo-GraphNetWikiTarget {
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

function Get-GraphNetTopFolder {
  param(
    [string]$Path,
    [string]$Vault
  )

  # The top-level vault folder that owns a covered note, or '' for a note that
  # sits directly in the vault root. This single derivation drives the dynamic
  # lane taxonomy: distinct non-empty results become lane hubs and root-level
  # notes (empty result) are routed to the intake hub.
  $relative = $Path.Substring($Vault.Length).TrimStart('\')
  $parts = @($relative -split '\\' | Where-Object { $_ })
  if ($parts.Count -le 1) {
    return ''
  }
  return $parts[0]
}

function ConvertTo-GraphNetHubSlug {
  param([string]$Folder)

  # File-name-safe slug for a top-level folder: lower-cased, every run of
  # non-alphanumeric characters folded to a single '-', trimmed. A folder made
  # entirely of non-ASCII characters collapses to 'folder'; collision handling
  # is the caller's job (Get-GraphNetLaneDefinitions appends a deterministic
  # numeric suffix).
  $lower = $Folder.ToLowerInvariant()
  $slug = [regex]::Replace($lower, '[^a-z0-9]+', '-')
  $slug = $slug.Trim('-')
  if ([string]::IsNullOrEmpty($slug)) {
    $slug = 'folder'
  }
  return $slug
}

function Get-GraphNetLaneDefinitions {
  param([string[]]$TopFolders = @())

  # Derive the lane model from the vault's own top-level folders instead of any
  # hard-coded taxonomy. Input is the top folder of every covered note ('' for a
  # root-level note). Output order is stable: the intake hub first, then one lane
  # hub per distinct folder in ordinal-ascending order, so hub names, colors, and
  # link order stay deterministic across runs and machines.
  #   Hub       base file name (without .md) of the generated hub
  #   Title     heading and link label (the folder name verbatim; no semantic renaming)
  #   Color     Obsidian graph color (fixed for intake, palette-cycled for lanes)
  #   TopFolder routing key: the folder routed into this hub ('' = vault root)
  $distinct = [System.Collections.Generic.List[string]]::new()
  $seenFolders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($top in $TopFolders) {
    if (($top -ne '') -and $seenFolders.Add($top)) {
      $distinct.Add($top)
    }
  }
  $distinct.Sort([System.StringComparer]::Ordinal)

  $lanes = [System.Collections.Generic.List[object]]::new()

  # The intake hub always exists. It is the catch-all for vault-root notes and
  # for any shard bucket whose dominant folder cannot be resolved, which keeps
  # the generated network a single connected component even for vaults with no
  # root-level notes or with empty shard buckets.
  $lanes.Add([ordered]@{
    Hub = 'hub-intake--unclassified'
    Title = 'Intake / Unclassified'
    Color = $script:GraphNetColorIntake
    TopFolder = ''
  })

  $usedSlugs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $paletteIndex = 0
  foreach ($folder in $distinct) {
    $slug = ConvertTo-GraphNetHubSlug -Folder $folder
    $baseSlug = $slug
    $suffix = 2
    # Ordinal-ascending iteration means the alphabetically earliest original
    # folder keeps the base slug and later collisions take -2, -3, ... So a slug
    # clash resolves deterministically in favor of the original folder name.
    while (-not $usedSlugs.Add($slug)) {
      $slug = '{0}-{1}' -f $baseSlug, $suffix
      $suffix++
    }
    $color = $script:GraphNetLaneHubPalette[$paletteIndex % $script:GraphNetLaneHubPalette.Count]
    $paletteIndex++
    $lanes.Add([ordered]@{
      Hub = ('hub-lane--{0}' -f $slug)
      Title = $folder
      Color = $color
      TopFolder = $folder
    })
  }

  return @($lanes)
}

function Test-GraphNetExcludedPathPart {
  param(
    [string]$Part,
    [bool]$TopLevel = $false
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
  if ($Part.ToLowerInvariant().Contains('cache')) {
    return $true
  }
  return $false
}

function Test-GraphNetCoveredNotePath {
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
    if (Test-GraphNetExcludedPathPart -Part $parts[$i] -TopLevel ($i -eq 0)) {
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
      if ($entry.PSIsContainer) {
        # Reparse points (junctions / symlinks) are not descended into, so
        # the walk cannot cycle through self-referencing links.
        if ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
          continue
        }
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

function Get-GraphNetStableBuckets {
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

function Get-GraphNetDominantTop {
  param([object[]]$Items = @())

  # Count descending, then ordinal name ascending: a deterministic tie-break
  # that resolves identically on every run and every machine. Sort-Object's
  # default string comparison is culture-sensitive, so a plain Name sort could
  # pick a different lane under another UI culture and break cross-machine
  # idempotency; an explicit ordinal sort matches the rest of the pipeline.
  $groups = @($Items | Group-Object Top)
  if ($groups.Count -eq 0) {
    return ''
  }
  $maxCount = ($groups | Measure-Object -Property Count -Maximum).Maximum
  $topNames = [string[]]@($groups | Where-Object { $_.Count -eq $maxCount } | ForEach-Object { [string]$_.Name })
  [System.Array]::Sort($topNames, [System.StringComparer]::Ordinal)
  return [string]$topNames[0]
}

function Get-GraphNetAutoBucketCount {
  param([int]$CoveredNoteCount)

  if ($CoveredNoteCount -lt 0) {
    throw "Covered note count must be zero or greater."
  }

  # min(64, max(8, ceil(N / 16))): small vaults get a small shard ring
  # instead of a fixed 64-shard layout, large vaults stay capped at 64.
  $scaled = [int][System.Math]::Ceiling($CoveredNoteCount / 16.0)
  return [System.Math]::Min(64, [System.Math]::Max(8, $scaled))
}

function Get-GraphNetNetworkAdjacency {
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
      $node = '{0}/{1}' -f $script:GraphNetGraphNetworkFolder, [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
      $adjacency[$node] = [System.Collections.Generic.HashSet[string]]::new()
      $contents[$node] = $content
    }
  }

  $linkPattern = '\[\[({0}/[^|\]]+)' -f [regex]::Escape($script:GraphNetGraphNetworkFolder)
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

function Get-GraphNetComponentStats {
  param([hashtable]$Adjacency)

  # BFS over an arbitrary undirected adjacency (node -> set of neighbor nodes),
  # returning both the connected-component count and the largest component size.
  # Isolated nodes (empty neighbor set) each form their own single-node
  # component, so the count includes orphans. Shared by the generated-network
  # guarantee (which needs the count to equal 1) and the read-only native audit
  # (which needs both the count and the largest component size).
  $visited = [System.Collections.Generic.HashSet[string]]::new()
  $components = 0
  $largest = 0

  foreach ($start in @($Adjacency.Keys | Sort-Object)) {
    if ($visited.Contains($start)) {
      continue
    }
    $components++
    $size = 0
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($start)
    $null = $visited.Add($start)
    while ($queue.Count -gt 0) {
      $current = $queue.Dequeue()
      $size++
      foreach ($neighbor in $Adjacency[$current]) {
        if (-not $visited.Contains($neighbor)) {
          $null = $visited.Add($neighbor)
          $queue.Enqueue($neighbor)
        }
      }
    }
    if ($size -gt $largest) {
      $largest = $size
    }
  }

  return [pscustomobject]@{
    ComponentCount = $components
    LargestComponentSize = $largest
  }
}

function Get-GraphNetNetworkConnectedComponentCount {
  param([string]$NetworkPath)

  # The guarantee requires exactly one connected component: shard ring -> lane
  # hub -> root anchors must never split into islands, because shards no longer
  # link the roots directly. Component counting itself is the generic BFS in
  # Get-GraphNetComponentStats so the generated-network check and the native
  # audit share one traversal.
  $adjacency = Get-GraphNetNetworkAdjacency -NetworkPath $NetworkPath
  return (Get-GraphNetComponentStats -Adjacency $adjacency).ComponentCount
}

function Get-GraphNetWikilinkTargets {
  param([string]$Content)

  # Pull the link targets out of every [[...]] wikilink in a note body. For each
  # link the alias (target|alias), heading (target#heading), and block reference
  # (target^block) are stripped so only the note-identifying target remains.
  # Embeds (![[...]]) are treated as links too. Whitespace-only targets are
  # dropped. This is the shared wikilink parse for the native connectivity audit.
  $targets = [System.Collections.Generic.List[string]]::new()
  foreach ($match in [regex]::Matches($Content, '\[\[([^\[\]]+)\]\]')) {
    $inner = $match.Groups[1].Value
    $pipe = $inner.IndexOf('|')
    if ($pipe -ge 0) {
      $inner = $inner.Substring(0, $pipe)
    }
    # Cut at the earliest heading (#) or block (^) marker so both forms, and the
    # combined target#heading^block form, reduce to the bare target.
    $hash = $inner.IndexOf('#')
    $caret = $inner.IndexOf('^')
    $cut = -1
    if (($hash -ge 0) -and ($caret -ge 0)) {
      $cut = [System.Math]::Min($hash, $caret)
    } elseif ($hash -ge 0) {
      $cut = $hash
    } elseif ($caret -ge 0) {
      $cut = $caret
    }
    if ($cut -ge 0) {
      $inner = $inner.Substring(0, $cut)
    }
    $inner = $inner.Trim()
    if ($inner.Length -gt 0) {
      $targets.Add($inner)
    }
  }
  return @($targets)
}

function Get-GraphNetMedian {
  param([int[]]$Values = @())

  # Median of a set of integer degrees. Even-sized sets average the two middle
  # values, so the result can be fractional; the empty set is 0. Sorting is
  # numeric (integers), which is culture-independent.
  $sorted = @($Values | Sort-Object)
  $n = $sorted.Count
  if ($n -eq 0) {
    return [double]0
  }
  $mid = [int][System.Math]::Floor($n / 2)
  if (($n % 2) -eq 1) {
    return [double]$sorted[$mid]
  }
  return ([double]($sorted[$mid - 1] + $sorted[$mid]) / 2.0)
}

function Get-GraphNetNativeGraph {
  param(
    [string]$Vault,
    [object[]]$Notes = @()
  )

  # Build the vault's native (author-authored) undirected wikilink graph over the
  # covered notes, deliberately excluding every link into the generated
  # _graph-network folder so the machine-added coverage edges do not mask the
  # vault's real connectivity. Link targets resolve to a covered note by:
  #   (a) relative-path match (separators and a trailing .md normalized away), or
  #   (b) a unique basename match (ordinal, case-insensitive).
  # Ambiguous (multiple basename hits or case-folded path collisions) and
  # unresolved targets are counted in UnresolvedLinks and never form an edge, so
  # the walk never crashes on a dangling or duplicate link. Every covered note is
  # a node even with no edges, so orphans are represented.
  $encoding = [System.Text.UTF8Encoding]::new($false)
  $networkPrefix = $script:GraphNetGraphNetworkFolder + '/'

  $nodeByPath = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $ambiguousPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $nodesByBasename = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)

  $adjacency = @{}
  $nodeList = [System.Collections.Generic.List[string]]::new()

  foreach ($note in $Notes) {
    $node = ConvertTo-GraphNetWikiTarget -Path $note.FullName -Vault $Vault
    $nodeList.Add($node)
    if (-not $adjacency.ContainsKey($node)) {
      $adjacency[$node] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    }

    # A case-folded relative-path collision (for example Foo/a and foo/a) makes
    # that path ambiguous for resolution instead of silently binding to one note.
    if ($nodeByPath.ContainsKey($node)) {
      $null = $ambiguousPaths.Add($node)
    } else {
      $nodeByPath[$node] = $node
    }

    $base = $note.BaseName
    if (-not $nodesByBasename.ContainsKey($base)) {
      $nodesByBasename[$base] = [System.Collections.Generic.List[string]]::new()
    }
    $nodesByBasename[$base].Add($node)
  }

  $unresolved = 0
  foreach ($note in $Notes) {
    $node = ConvertTo-GraphNetWikiTarget -Path $note.FullName -Vault $Vault
    $content = [System.IO.File]::ReadAllText($note.FullName, $encoding)
    foreach ($rawTarget in (Get-GraphNetWikilinkTargets -Content $content)) {
      $normalized = ($rawTarget -replace '\\', '/').TrimStart('/')
      if ($normalized.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring(0, $normalized.Length - 3)
      }
      if ($normalized.Length -eq 0) {
        continue
      }
      # Links into the generated network are removed from the native graph
      # entirely: they are neither an edge nor an unresolved link.
      if ($normalized.StartsWith($networkPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
      }

      $resolved = $null
      if ($nodeByPath.ContainsKey($normalized) -and (-not $ambiguousPaths.Contains($normalized))) {
        $resolved = $nodeByPath[$normalized]
      } else {
        $base = $normalized
        $slash = $normalized.LastIndexOf('/')
        if ($slash -ge 0) {
          $base = $normalized.Substring($slash + 1)
        }
        if ($nodesByBasename.ContainsKey($base) -and ($nodesByBasename[$base].Count -eq 1)) {
          $resolved = $nodesByBasename[$base][0]
        }
      }

      if ($null -eq $resolved) {
        $unresolved++
        continue
      }
      if ($resolved -ne $node) {
        $null = $adjacency[$node].Add($resolved)
        $null = $adjacency[$resolved].Add($node)
      }
    }
  }

  return [pscustomobject]@{
    Adjacency = $adjacency
    Nodes = @($nodeList)
    UnresolvedLinks = $unresolved
  }
}

function Get-GraphNetExpectedGeneratedFiles {
  param(
    [int]$BucketCountUsed,
    [string]$ShardPrefix,
    [object[]]$LaneDefinitions = @()
  )

  # The full set of _graph-network files a run generates: the two root anchors,
  # the coverage shard ring, and every hub (intake plus each lane). Both the
  # -PruneStale sweep and the validate-phase stale detector treat any generated
  # file that is NOT in this set as a leftover from an older layout (previous
  # shard prefix, retired root name, or a hub that no longer matches the lane
  # model). Keeping one definition means the sweep and the validator can never
  # disagree about what "current" means. Comparison is case-insensitive to match
  # Windows file-name semantics.
  $expected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $null = $expected.Add('graph-network-root.md')
  $null = $expected.Add('NETWORK-GUARANTEE.md')
  for ($i = 0; $i -lt $BucketCountUsed; $i++) {
    $null = $expected.Add(('{0}-{1:D2}.md' -f $ShardPrefix, $i))
  }
  foreach ($lane in $LaneDefinitions) {
    $null = $expected.Add(('{0}.md' -f $lane.Hub))
  }
  return $expected
}

function Get-GraphNetStaleGeneratedFiles {
  param(
    [string]$NetworkPath,
    [System.Collections.Generic.HashSet[string]]$ExpectedFiles,
    [string]$ShardPrefix
  )

  # A _graph-network markdown file is stale when it is not one of this run's
  # expected generated files AND either:
  #   * its name matches a generated shard naming pattern (the historical
  #     'bridge-*' shards, or a '<ShardPrefix>-*' shard beyond the current bucket
  #     count), or
  #   * it carries the network_generated marker, which catches every
  #     previous-generation artifact regardless of name: an older coverage shard
  #     prefix from an earlier version, a renamed root anchor, and hub files
  #     that no longer match the current lane model.
  # Manual notes without the marker and outside the generated name patterns are
  # never swept, so hand-authored files inside the folder stay put. This single
  # rule is shared by the -PruneStale sweep and the validate-phase detector so a
  # plain run fails on the same leftovers that -PruneStale archives.
  $encoding = [System.Text.UTF8Encoding]::new($false)
  $stale = [System.Collections.Generic.List[object]]::new()
  Get-ChildItem -LiteralPath $NetworkPath -Force -File -Filter '*.md' | ForEach-Object {
    if ($ExpectedFiles.Contains($_.Name)) {
      return
    }
    $isGeneratedName = ($_.Name -like 'bridge-*.md') -or ($_.Name -like "$ShardPrefix-*.md")
    $carriesMarker = $false
    if (-not $isGeneratedName) {
      $content = [System.IO.File]::ReadAllText($_.FullName, $encoding)
      $carriesMarker = ($content -match '(?m)^network_generated:\s*true\s*$')
    }
    if ($isGeneratedName -or $carriesMarker) {
      $stale.Add($_)
    }
  }
  return @($stale)
}

function Get-GraphNetGraphIgnoreFilters {
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

function Get-GraphNetGraphSearchFilter {
  return '-path:".git" -path:".github" -path:".obsidian" -path:".smart-env" -path:".pytest_cache" -path:"__pycache__" -path:"node_modules" -path:"_workspace-local-secrets" -path:"tools" -path:"cache" -path:"vendor"'
}

function New-GraphNetColorGroup {
  param(
    [string]$Query,
    [int]$Rgb
  )

  return [ordered]@{ query = $Query; color = [ordered]@{ a = 1; rgb = $Rgb } }
}

function Get-GraphNetGraphColorGroups {
  param([object[]]$LaneDefinitions = @())

  $groups = [System.Collections.Generic.List[object]]::new()

  # Root anchors (fixed anchor color).
  $groups.Add((New-GraphNetColorGroup 'path:"_graph-network/graph-network-root"' $script:GraphNetColorAnchor))
  $groups.Add((New-GraphNetColorGroup 'path:"_graph-network/NETWORK-GUARANTEE"' $script:GraphNetColorAnchor))

  # Coverage shards (fixed shard color).
  $groups.Add((New-GraphNetColorGroup ('path:"_graph-network/{0}"' -f $script:GraphNetCoverageShardPrefix) $script:GraphNetColorShard))

  # Lane hub color groups, derived from the dynamic lane model so hub names and
  # colors track the vault's top-level folders. The intake hub carries its fixed
  # color and each lane hub carries its palette-cycled color, both already
  # resolved on the lane definition, so this loop stays free of any hard-coded
  # personal folder name.
  foreach ($lane in $LaneDefinitions) {
    $groups.Add((New-GraphNetColorGroup ('path:"_graph-network/{0}"' -f $lane.Hub) $lane.Color))
  }

  return @($groups)
}

function Get-RequiredGraphNetGraphColorQueries {
  param([object[]]$LaneDefinitions = @())

  # The color group queries the guarantee requires: both root anchors, the
  # coverage shard prefix, and every generated hub (intake plus each lane).
  $required = [System.Collections.Generic.List[string]]::new()
  $required.Add('path:"_graph-network/graph-network-root"')
  $required.Add('path:"_graph-network/NETWORK-GUARANTEE"')
  $required.Add(('path:"_graph-network/{0}"' -f $script:GraphNetCoverageShardPrefix))
  foreach ($lane in $LaneDefinitions) {
    $required.Add(('path:"_graph-network/{0}"' -f $lane.Hub))
  }
  return @($required)
}
