#Requires -Version 5.1

param(
  [string]$Vault,
  [int]$BucketCount = 0,
  [switch]$PruneStale,
  [string]$ArchiveRoot = (Join-Path ([System.IO.Path]::GetTempPath()) 'graph-network-runs')
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'obsidian-graph-network-lib.ps1')

function Write-GraphNetFileIfChanged {
  param(
    [string]$Path,
    [string]$Content
  )

  # Single compare-then-write path shared by every generated file and by the
  # graph.json / app.json settings writers: read the existing bytes, skip the
  # write when they already match, otherwise persist as no-BOM UTF-8. Keeping
  # this rule in one place stops the shard writer and the settings writers from
  # drifting apart on encoding or change detection.
  $encoding = [System.Text.UTF8Encoding]::new($false)

  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $existing = [System.IO.File]::ReadAllText($Path, $encoding)
    if ($existing -eq $Content) {
      return $false
    }
  }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
  return $true
}

function Write-Utf8IfChanged {
  param(
    [string]$Path,
    [string[]]$Lines
  )

  $content = ($Lines -join [Environment]::NewLine) + [Environment]::NewLine
  return (Write-GraphNetFileIfChanged -Path $Path -Content $content)
}

function Set-GraphNetGraphSettings {
  param(
    [string]$GraphConfigPath,
    [object[]]$LaneDefinitions = @()
  )

  $graphConfig = [ordered]@{}
  if (Test-Path -LiteralPath $GraphConfigPath -PathType Leaf) {
    $raw = Get-Content -LiteralPath $GraphConfigPath -Raw -Encoding UTF8
    if ($null -ne $raw -and $raw.Trim().Length -gt 0) {
      $existing = $raw | ConvertFrom-Json
      foreach ($property in $existing.PSObject.Properties) {
        $graphConfig[$property.Name] = $property.Value
      }
    }
  }

  $graphConfig['showOrphans'] = $false
  $graphConfig['hideUnresolved'] = $true
  $graphConfig['search'] = Get-GraphNetGraphSearchFilter
  $graphConfig['showTags'] = $false
  $graphConfig['showAttachments'] = $false
  $graphConfig['collapse-color-groups'] = $false
  $graphConfig['colorGroups'] = @(Get-GraphNetGraphColorGroups -LaneDefinitions $LaneDefinitions)

  $json = ($graphConfig | ConvertTo-Json -Depth 12)
  return (Write-GraphNetFileIfChanged -Path $GraphConfigPath -Content ($json + [Environment]::NewLine))
}

function Set-GraphNetAppSettings {
  param([string]$AppConfigPath)

  $appConfig = [ordered]@{}
  if (Test-Path -LiteralPath $AppConfigPath -PathType Leaf) {
    $rawAppConfig = Get-Content -LiteralPath $AppConfigPath -Raw -Encoding UTF8
    if ($null -ne $rawAppConfig -and $rawAppConfig.Trim().Length -gt 0) {
      $existingAppConfig = $rawAppConfig | ConvertFrom-Json
      foreach ($property in $existingAppConfig.PSObject.Properties) {
        $appConfig[$property.Name] = $property.Value
      }
    }
  }

  $appConfig['userIgnoreFilters'] = @(Get-GraphNetGraphIgnoreFilters)
  $appJson = $appConfig | ConvertTo-Json -Depth 8
  return (Write-GraphNetFileIfChanged -Path $AppConfigPath -Content ($appJson + [Environment]::NewLine))
}

function New-GraphNetCoverageBuckets {
  # Build phase: resolve the shard ring size for this run, derive the dynamic
  # lane model from the vault's top-level folders, and assign every covered note
  # to its two deterministic shard buckets, carrying the metadata (wiki target,
  # display name, top-level folder) that the write phase needs.
  param(
    [string]$Vault,
    [int]$RequestedBucketCount
  )

  # Pruned walk: excluded directories (node_modules, .git, .obsidian, ...) are
  # skipped at traversal time instead of being enumerated and filtered later.
  # The covered note set is identical to the previous full recursive scan.
  $notes = @(Get-GraphNetCoveredNoteFiles -Vault $Vault)

  # Derive the lane model from the top-level folder of every covered note, so
  # hubs, colors, and routing all follow the vault's actual structure.
  $tops = @($notes | ForEach-Object { Get-GraphNetTopFolder -Path $_.FullName -Vault $Vault })
  $laneDefinitions = @(Get-GraphNetLaneDefinitions -TopFolders $tops)

  if ($RequestedBucketCount -ge 1) {
    $bucketCountUsed = $RequestedBucketCount
  } else {
    $bucketCountUsed = Get-GraphNetAutoBucketCount -CoveredNoteCount $notes.Count
  }

  $buckets = @()
  for ($i = 0; $i -lt $bucketCountUsed; $i++) {
    $buckets += ,([System.Collections.Generic.List[object]]::new())
  }

  for ($i = 0; $i -lt $notes.Count; $i++) {
    $target = ConvertTo-GraphNetWikiTarget -Path $notes[$i].FullName -Vault $Vault
    $noteBuckets = Get-GraphNetStableBuckets -Target $target -Count $bucketCountUsed
    $item = [pscustomobject]@{
      Target = $target
      Name = $notes[$i].BaseName
      Top = (Get-GraphNetTopFolder -Path $notes[$i].FullName -Vault $Vault)
    }
    $buckets[$noteBuckets[0]].Add($item)
    $buckets[$noteBuckets[1]].Add($item)
  }

  return [pscustomobject]@{
    Notes = $notes
    BucketCountUsed = $bucketCountUsed
    Buckets = $buckets
    LaneDefinitions = $laneDefinitions
  }
}

function Write-GraphNetNetworkFiles {
  # Write phase: emit the generated _graph-network artifacts (coverage shards,
  # guarantee root, network root, lane hubs) and optionally archive stale
  # shards. Returns the per-note edge counts and the list of files it rewrote
  # so the validate phase and the final report can consume them.
  param(
    [string]$Network,
    [pscustomobject]$Build,
    [string]$ShardPrefix,
    [object[]]$LaneDefinitions = @(),
    [switch]$PruneStale,
    [string]$Archive
  )

  $buckets = $Build.Buckets
  $bucketCountUsed = $Build.BucketCountUsed
  $noteCount = $Build.Notes.Count

  # Derive the top-folder -> hub routing map and the hub file definitions from
  # the dynamic lane model, so hub names, titles, and folder routing are never
  # restated here. Every lane's folder maps to its hub; the intake hub (folder
  # '') is the fallback for a shard whose dominant folder resolves to no lane.
  $hubMap = @{}
  foreach ($lane in $LaneDefinitions) {
    $hubMap[$lane.TopFolder] = $lane.Hub
  }
  $fallbackHub = if ($hubMap.ContainsKey('')) {
    $hubMap['']
  } elseif ($LaneDefinitions.Count -gt 0) {
    $LaneDefinitions[0].Hub
  } else {
    'hub-intake--unclassified'
  }

  $hubDefinitions = @($LaneDefinitions | ForEach-Object {
    [pscustomobject]@{ FileName = ('{0}.md' -f $_.Hub); Title = $_.Title }
  })

  $updatedFiles = [System.Collections.Generic.List[string]]::new()
  $targetEdgeCounts = @{}

  for ($i = 0; $i -lt $bucketCountUsed; $i++) {
    $fileName = '{0}-{1:D2}.md' -f $ShardPrefix, $i
    $path = Join-Path $Network $fileName
    $prev = '{0}-{1:D2}' -f $ShardPrefix, (($i + $bucketCountUsed - 1) % $bucketCountUsed)
    $next = '{0}-{1:D2}' -f $ShardPrefix, (($i + 1) % $bucketCountUsed)

    $dominantTop = Get-GraphNetDominantTop -Items @($buckets[$i])
    $laneHub = if ($hubMap.ContainsKey($dominantTop)) { $hubMap[$dominantTop] } else { $fallbackHub }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('---')
    $lines.Add('network_generated: true')
    $lines.Add('network_role: coverage_shard')
    $lines.Add(('bucket: {0}' -f $i))
    $lines.Add(('dominant_lane: {0}' -f $dominantTop))
    $lines.Add(('note_links: {0}' -f $buckets[$i].Count))
    $lines.Add('---')
    $lines.Add('')
    $lines.Add(('# Coverage Shard {0:D2}' -f $i))
    $lines.Add('')
    $lines.Add('This generated shard preserves graph connectivity without editing note bodies.')
    $lines.Add('')
    $lines.Add('## Network Links')
    # Shards carry ring + lane hub links only. Root anchors are reached through
    # the lane hubs, which keeps root anchor degree at O(lane count) instead of
    # O(shard count) and stops the graph view from collapsing into a hairball.
    $lines.Add(('- [[_graph-network/{0}|Previous Coverage Shard]]' -f $prev))
    $lines.Add(('- [[_graph-network/{0}|Next Coverage Shard]]' -f $next))
    $lines.Add(('- [[_graph-network/{0}|Lane Hub]]' -f $laneHub))
    $lines.Add('')
    $lines.Add('## Covered Notes')

    # Ordinal sort of the covered-note links so a shard body is byte-identical
    # across machines and UI cultures (Sort-Object Target would collate
    # punctuation and case per culture and defeat cross-machine idempotency).
    $bucketItems = [object[]]@($buckets[$i])
    $bucketKeys = [string[]]@($bucketItems | ForEach-Object { [string]$_.Target })
    [System.Array]::Sort($bucketKeys, $bucketItems, [System.StringComparer]::Ordinal)
    foreach ($item in $bucketItems) {
      $lines.Add(('- [[{0}|{1}]]' -f $item.Target, $item.Name))
      if (-not $targetEdgeCounts.ContainsKey($item.Target)) {
        $targetEdgeCounts[$item.Target] = 0
      }
      $targetEdgeCounts[$item.Target]++
    }

    if (Write-Utf8IfChanged -Path $path -Lines $lines) {
      $updatedFiles.Add($fileName)
    }
  }

  $summaryPath = Join-Path $Network 'NETWORK-GUARANTEE.md'
  $summary = [System.Collections.Generic.List[string]]::new()
  $summary.Add('---')
  $summary.Add('network_generated: true')
  $summary.Add('network_role: guarantee_root')
  $summary.Add(('bucket_count: {0}' -f $bucketCountUsed))
  $summary.Add(('covered_notes: {0}' -f $noteCount))
  $summary.Add('minimum_network_edges_per_note: 2')
  $summary.Add('---')
  $summary.Add('')
  $summary.Add('# Network Guarantee')
  $summary.Add('')
  $summary.Add('Every markdown note in the vault, except system folders, is referenced by two coverage shards.')
  $summary.Add('')
  $summary.Add('- [[_graph-network/graph-network-root|Graph Network]]')
  # Enumerate every hub so the guarantee anchor stays linked to the whole lane
  # ring and the generated network is a single connected component.
  foreach ($hub in $hubDefinitions) {
    $hubTarget = [System.IO.Path]::GetFileNameWithoutExtension($hub.FileName)
    $summary.Add(('- [[_graph-network/{0}|{1}]]' -f $hubTarget, $hub.Title))
  }
  $summary.Add(('- [[_graph-network/{0}-00|Coverage Shard Ring Entry]]' -f $ShardPrefix))
  if (Write-Utf8IfChanged -Path $summaryPath -Lines $summary) {
    $updatedFiles.Add('NETWORK-GUARANTEE.md')
  }

  $rootPath = Join-Path $Network 'graph-network-root.md'
  $rootLines = [System.Collections.Generic.List[string]]::new()
  $rootLines.Add('---')
  $rootLines.Add('network_generated: true')
  $rootLines.Add('network_role: network_root')
  $rootLines.Add(('bucket_count: {0}' -f $bucketCountUsed))
  $rootLines.Add(('covered_notes: {0}' -f $noteCount))
  $rootLines.Add('---')
  $rootLines.Add('')
  $rootLines.Add('# Graph Network')
  $rootLines.Add('')
  $rootLines.Add('Root anchor for generated graph connectivity.')
  $rootLines.Add('')
  $rootLines.Add('## Anchors')
  $rootLines.Add('- [[_graph-network/NETWORK-GUARANTEE|Network Guarantee]]')
  $rootLines.Add(('- [[_graph-network/{0}-00|Coverage Shard Ring Entry]]' -f $ShardPrefix))
  $rootLines.Add('')
  $rootLines.Add('## Lane Hubs')
  foreach ($hub in $hubDefinitions) {
    $hubTarget = [System.IO.Path]::GetFileNameWithoutExtension($hub.FileName)
    $rootLines.Add(('- [[_graph-network/{0}|{1}]]' -f $hubTarget, $hub.Title))
  }
  if (Write-Utf8IfChanged -Path $rootPath -Lines $rootLines) {
    $updatedFiles.Add('graph-network-root.md')
  }

  foreach ($hub in $hubDefinitions) {
    $hubTarget = [System.IO.Path]::GetFileNameWithoutExtension($hub.FileName)
    $hubPath = Join-Path $Network $hub.FileName
    $hubLines = @(
      '---',
      'network_generated: true',
      'network_role: lane_hub',
      ('hub: {0}' -f $hubTarget),
      '---',
      '',
      ('# {0}' -f $hub.Title),
      '',
      'Generated lane hub for graph connectivity.',
      '',
      '- [[_graph-network/graph-network-root|Graph Network]]',
      '- [[_graph-network/NETWORK-GUARANTEE|Network Guarantee]]'
    )
    if (Write-Utf8IfChanged -Path $hubPath -Lines $hubLines) {
      $updatedFiles.Add($hub.FileName)
    }
  }

  $staleFiles = @()
  if ($PruneStale) {
    # Sweep every leftover from a previous layout, not just the current prefix:
    # the shared stale detector also archives old-prefix shards, the retired
    # root anchor, and obsolete hubs (all carrying the network_generated marker),
    # plus the historical 'bridge-*' shards.
    $expectedFiles = Get-GraphNetExpectedGeneratedFiles -BucketCountUsed $bucketCountUsed -ShardPrefix $ShardPrefix -LaneDefinitions $LaneDefinitions
    $staleFiles = @(Get-GraphNetStaleGeneratedFiles -NetworkPath $Network -ExpectedFiles $expectedFiles -ShardPrefix $ShardPrefix)

    if ($staleFiles) {
      New-Item -ItemType Directory -Force -Path $Archive | Out-Null
      $oldDir = Join-Path $Archive 'stale-bridges'
      New-Item -ItemType Directory -Force -Path $oldDir | Out-Null
      foreach ($file in $staleFiles) {
        Move-Item -LiteralPath $file.FullName -Destination (Join-Path $oldDir $file.Name) -Force
      }
    }
  }

  return [pscustomobject]@{
    UpdatedFiles = $updatedFiles
    TargetEdgeCounts = $targetEdgeCounts
    StaleMovedCount = ($staleFiles | Measure-Object).Count
  }
}

function Test-GraphNetNetworkGuarantee {
  # Validate phase: recompute the guarantee from the files on disk plus this
  # run's edge counts, then throw when any invariant is violated. On success it
  # returns every statistic the final report surfaces.
  param(
    [string]$Vault,
    [string]$Network,
    [pscustomobject]$Build,
    [hashtable]$TargetEdgeCounts,
    [string]$ShardPrefix,
    [object[]]$LaneDefinitions = @(),
    [string]$GraphConfigPath
  )

  $notes = $Build.Notes
  $bucketCountUsed = $Build.BucketCountUsed

  $expectedTargets = @{}
  foreach ($note in $notes) {
    $expectedTargets[(ConvertTo-GraphNetWikiTarget -Path $note.FullName -Vault $Vault)] = $true
  }

  # The guarantee counters above come from this run's in-memory buckets only,
  # so leftover on-disk generated files (auto count shrink after note deletions,
  # a migration from the previous fixed 64-shard layout, or a migration from the
  # previous naming layout with an old shard prefix / root name / hubs) would
  # silently keep extra live edges. Detect them from the disk after optional
  # pruning with the same rule the sweep uses, and fail instead of reporting a
  # guarantee the vault no longer satisfies, so a plain run without -PruneStale
  # fails loudly on exactly what -PruneStale would archive.
  $expectedGeneratedFiles = Get-GraphNetExpectedGeneratedFiles -BucketCountUsed $bucketCountUsed -ShardPrefix $ShardPrefix -LaneDefinitions $LaneDefinitions
  $staleShardFiles = @(Get-GraphNetStaleGeneratedFiles -NetworkPath $Network -ExpectedFiles $expectedGeneratedFiles -ShardPrefix $ShardPrefix)

  # Connectivity invariant: with shard navigation reduced to prev/next/lane hub,
  # the generated files must still resolve to one undirected wikilink component
  # (shard ring -> lane hub -> root anchors). Recompute from the files on disk
  # so drift in any generated file is caught, not just this run's memory view.
  $networkComponents = Get-GraphNetNetworkConnectedComponentCount -NetworkPath $Network

  $edgeValues = @($TargetEdgeCounts.Values)
  $lessThanTwo = @($edgeValues | Where-Object { $_ -lt 2 }).Count
  $moreThanTwo = @($edgeValues | Where-Object { $_ -gt 2 }).Count
  $coveredTargets = $TargetEdgeCounts.Count
  $missingTargets = @($expectedTargets.Keys | Where-Object { -not $TargetEdgeCounts.ContainsKey($_) }).Count
  $unresolvedTargets = @($TargetEdgeCounts.Keys | Where-Object { -not $expectedTargets.ContainsKey($_) }).Count
  $trailingDotTargets = @($TargetEdgeCounts.Keys | Where-Object { $_.EndsWith('.') }).Count
  $utf8Failures = [System.Collections.Generic.List[string]]::new()
  $utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)

  Get-ChildItem -LiteralPath $Network -Filter '*.md' -File | ForEach-Object {
    try {
      $null = [System.IO.File]::ReadAllText($_.FullName, $utf8Strict)
    } catch {
      $utf8Failures.Add($_.FullName)
    }
  }

  $smartExcludesGraphNetwork = $false
  # Legacy Smart Connections layout: vault-root .smart-env\smart_env.json
  $smartConfigPath = Join-Path $Vault '.smart-env\smart_env.json'
  if (Test-Path -LiteralPath $smartConfigPath -PathType Leaf) {
    try {
      $smartConfig = Get-Content -LiteralPath $smartConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($smartConfig.smart_sources.folder_exclusions -match '_graph-network') {
        $smartExcludesGraphNetwork = $true
      }
    } catch {
      # Corrupt or non-JSON legacy smart_env.json; treat as no exclusion setting
      # (warn-worthy but non-fatal) and fall through to the plugin data.json scan,
      # matching the plugin loop below.
    }
  }
  # Current Smart Connections / Open Connections fork (>=3.x): settings persist in the
  # plugin's own data.json under settings.smart_sources.folder_exclusions. Scan every
  # installed plugin so the guarantee matches whichever Smart-style plugin is in use.
  if (-not $smartExcludesGraphNetwork) {
    $pluginsRoot = Join-Path $Vault '.obsidian\plugins'
    if (Test-Path -LiteralPath $pluginsRoot -PathType Container) {
      $pluginDataFiles = @(Get-ChildItem -LiteralPath $pluginsRoot -Filter 'data.json' -File -Recurse -ErrorAction SilentlyContinue)
      foreach ($pluginData in $pluginDataFiles) {
        try {
          $pluginConfig = Get-Content -LiteralPath $pluginData.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
          if ($pluginConfig.settings.smart_sources.folder_exclusions -match '_graph-network') {
            $smartExcludesGraphNetwork = $true
            break
          }
        } catch {
          # Non-JSON or unrelated plugin data.json; ignore and keep scanning.
        }
      }
    }
  }

  $graphSettingsOk = $false
  $missingGraphColorGroups = @()
  $graphColorGroupsCount = 0
  $requiredColorQueries = @(Get-RequiredGraphNetGraphColorQueries -LaneDefinitions $LaneDefinitions)
  if (Test-Path -LiteralPath $GraphConfigPath -PathType Leaf) {
    $graphConfig = Get-Content -LiteralPath $GraphConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $graphColorGroups = @($graphConfig.colorGroups)
    $graphColorGroupsCount = $graphColorGroups.Count
    $graphColorQueries = @($graphColorGroups | ForEach-Object { $_.query })
    $missingGraphColorGroups = @($requiredColorQueries | Where-Object { $graphColorQueries -notcontains $_ })
    $graphColorGroupsOk = (($graphColorGroups.Count -ge $requiredColorQueries.Count) -and ($missingGraphColorGroups.Count -eq 0))
    $graphSettingsOk = (($graphConfig.showOrphans -eq $false) -and ($graphConfig.hideUnresolved -eq $true) -and ($graphConfig.'collapse-color-groups' -eq $false) -and $graphColorGroupsOk)
  }

  $failures = [System.Collections.Generic.List[string]]::new()
  if ($coveredTargets -ne $notes.Count) {
    $failures.Add("Covered target count mismatch: covered=$coveredTargets notes=$($notes.Count)")
  }
  if ($missingTargets -ne 0) {
    $failures.Add("Some notes are missing from generated coverage shard links: $missingTargets")
  }
  if ($unresolvedTargets -ne 0) {
    $failures.Add("Generated coverage shard links include targets that do not match notes: $unresolvedTargets")
  }
  if ($trailingDotTargets -ne 0) {
    $failures.Add("Generated coverage shard links include trailing-dot targets: $trailingDotTargets")
  }
  if ($lessThanTwo -ne 0) {
    $failures.Add("Some notes have fewer than 2 coverage shard edges: $lessThanTwo")
  }
  if ($moreThanTwo -ne 0) {
    $failures.Add("Some notes have more than 2 coverage shard edges: $moreThanTwo")
  }
  if ($staleShardFiles.Count -ne 0) {
    $failures.Add("Stale generated network files from a previous shard count or naming layout remain on disk and break the 2-edge guarantee: $($staleShardFiles.Count). Rerun with -PruneStale to archive them.")
  }
  if ($networkComponents -ne 1) {
    $failures.Add("Generated network files do not form a single connected wikilink component: components=$networkComponents")
  }
  if ($utf8Failures.Count -ne 0) {
    $failures.Add("UTF-8 validation failed for generated network files: $($utf8Failures.Count)")
  }
  if (-not $smartExcludesGraphNetwork) {
    $failures.Add("Smart Connections does not exclude _graph-network.")
  }
  if (-not $graphSettingsOk) {
    $failures.Add("Obsidian graph settings are not guaranteed: require showOrphans=false, hideUnresolved=true, and full lane graph color groups. Missing color groups: $($missingGraphColorGroups -join ', ')")
  }

  if ($failures.Count -ne 0) {
    throw ($failures -join [Environment]::NewLine)
  }

  return [pscustomobject]@{
    CoveredTargets = $coveredTargets
    MissingTargets = $missingTargets
    UnresolvedTargets = $unresolvedTargets
    TrailingDotTargets = $trailingDotTargets
    LessThanTwo = $lessThanTwo
    MoreThanTwo = $moreThanTwo
    NetworkConnectedComponents = $networkComponents
    Utf8Failures = $utf8Failures.Count
    SmartExcludesGraphNetwork = $smartExcludesGraphNetwork
    GraphSettingsOk = $graphSettingsOk
    MissingGraphColorGroupsCount = $missingGraphColorGroups.Count
    GraphColorGroupsCount = $graphColorGroupsCount
  }
}

# ---- main flow: build -> write -> settings -> validate -> report ----

if ([string]::IsNullOrWhiteSpace($Vault)) {
  throw ("Vault path is required. Usage: update-obsidian-graph-network.ps1 -Vault <vault-directory> [-BucketCount <n, 0 = auto>] [-PruneStale] [-ArchiveRoot <directory>]")
}

if (-not (Test-Path -LiteralPath $Vault -PathType Container)) {
  throw "Vault directory does not exist: $Vault"
}

$Vault = (Resolve-Path -LiteralPath $Vault).Path

if (($BucketCount -ne 0) -and ($BucketCount -lt 2)) {
  # A single shard cannot give a note two distinct shard edges, so 1 is
  # rejected here even though Get-GraphNetStableBuckets tolerates Count=1.
  throw "BucketCount must be 0 (auto) or at least 2."
}

$network = Get-GraphNetGraphNetworkPath -Vault $Vault
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$archive = Join-Path $ArchiveRoot $stamp
$shardPrefix = $script:GraphNetCoverageShardPrefix

New-Item -ItemType Directory -Force -Path $network | Out-Null

$build = New-GraphNetCoverageBuckets -Vault $Vault -RequestedBucketCount $BucketCount
$laneDefinitions = @($build.LaneDefinitions)
$write = Write-GraphNetNetworkFiles -Network $network -Build $build -ShardPrefix $shardPrefix -LaneDefinitions $laneDefinitions -PruneStale:$PruneStale -Archive $archive

$graphConfigPath = Join-Path $Vault '.obsidian\graph.json'
$graphSettingsUpdated = Set-GraphNetGraphSettings -GraphConfigPath $graphConfigPath -LaneDefinitions $laneDefinitions

$appConfigPath = Join-Path $Vault '.obsidian\app.json'
$appSettingsUpdated = Set-GraphNetAppSettings -AppConfigPath $appConfigPath

$validation = Test-GraphNetNetworkGuarantee -Vault $Vault -Network $network -Build $build -TargetEdgeCounts $write.TargetEdgeCounts -ShardPrefix $shardPrefix -LaneDefinitions $laneDefinitions -GraphConfigPath $graphConfigPath

[pscustomobject]@{
  Vault = $Vault
  CoveredNotes = $build.Notes.Count
  BucketCount = $BucketCount
  BucketCountUsed = $build.BucketCountUsed
  GeneratedCoverageShardFiles = $build.BucketCountUsed
  LinksPerNote = 2
  NetworkFiles = (Get-ChildItem -LiteralPath $network -Filter '*.md' -File | Measure-Object).Count
  UpdatedFiles = $write.UpdatedFiles.Count
  StaleMoved = $write.StaleMovedCount
  CoveredTargets = $validation.CoveredTargets
  MissingTargets = $validation.MissingTargets
  UnresolvedTargets = $validation.UnresolvedTargets
  TrailingDotTargets = $validation.TrailingDotTargets
  LessThanTwo = $validation.LessThanTwo
  MoreThanTwo = $validation.MoreThanTwo
  NetworkConnectedComponents = $validation.NetworkConnectedComponents
  Utf8Failures = $validation.Utf8Failures
  SmartExcludesGraphNetwork = $validation.SmartExcludesGraphNetwork
  GraphSettingsOk = $validation.GraphSettingsOk
  GraphSettingsUpdated = $graphSettingsUpdated
  AppSettingsUpdated = $appSettingsUpdated
  GraphColorGroups = $validation.GraphColorGroupsCount
  MissingGraphColorGroups = $validation.MissingGraphColorGroupsCount
  GuaranteeOk = $true
  Archive = if ($write.StaleMovedCount -gt 0) { $archive } else { $null }
}
