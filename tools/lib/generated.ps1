#Requires -Version 5.1

# Generated network layout: lanes, expected and stale generated files, Smart Connections and graph settings.
# Loaded by obsidian-graph-network-lib.ps1. Do not dot-source this file on its own.

function Get-GraphNetTopFolder {
  param(
    [string]$Path,
    [string]$Vault
  )

  # The top-level vault folder that owns a covered note, or '' for a note that
  # sits directly in the vault root. This single derivation drives the dynamic
  # lane taxonomy: distinct non-empty results become lane hubs and root-level
  # notes (empty result) are routed to the intake hub.
  $parts = @(Get-GraphNetRelativePathParts -Path $Path -Vault $Vault)
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

function Test-GraphNetSmartExclusionsCoverNetwork {
  param([object]$Exclusions)

  foreach ($value in @($Exclusions)) {
    if ($null -eq $value) {
      continue
    }
    foreach ($entry in ([string]$value).Split(',')) {
      $normalized = $entry.Trim().Trim([char[]]@('\', '/'))
      if ([string]::Equals($normalized, $script:GraphNetGraphNetworkFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
      }
    }
  }
  return $false
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
