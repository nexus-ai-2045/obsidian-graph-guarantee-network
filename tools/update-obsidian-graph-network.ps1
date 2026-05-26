param(
  [string]$Vault = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path,
  [int]$BucketCount = 64,
  [switch]$PruneStale,
  [string]$ArchiveRoot = (Join-Path ([System.IO.Path]::GetTempPath()) 'graph-network-runs')
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'obsidian-graph-network-lib.ps1')

if (-not (Test-Path -LiteralPath $Vault -PathType Container)) {
  throw "Vault directory does not exist: $Vault"
}

$Vault = (Resolve-Path -LiteralPath $Vault).Path

if ($BucketCount -lt 2) {
  throw "BucketCount must be at least 2."
}

$network = Get-FdeGraphNetworkPath -Vault $Vault
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$archive = Join-Path $ArchiveRoot $stamp
$shardPrefix = $script:FdeCoverageShardPrefix

New-Item -ItemType Directory -Force -Path $network | Out-Null

function Get-StableBuckets {
  param(
    [string]$Target,
    [int]$Count
  )

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Target.ToLowerInvariant())
    $hash = $sha.ComputeHash($bytes)
  } finally {
    $sha.Dispose()
  }

  $first = [System.BitConverter]::ToUInt32($hash, 0) % $Count
  $second = [System.BitConverter]::ToUInt32($hash, 4) % $Count
  if ($second -eq $first) {
    $second = ($second + 17) % $Count
  }

  return @([int]$first, [int]$second)
}

function Write-Utf8IfChanged {
  param(
    [string]$Path,
    [string[]]$Lines
  )

  $content = ($Lines -join [Environment]::NewLine) + [Environment]::NewLine
  $encoding = [System.Text.UTF8Encoding]::new($false)

  if (Test-Path -LiteralPath $Path) {
    $existing = [System.IO.File]::ReadAllText($Path, $encoding)
    if ($existing -eq $content) {
      return $false
    }
  }

  [System.IO.File]::WriteAllText($Path, $content, $encoding)
  return $true
}

function Ensure-GraphSettings {
  param([string]$GraphConfigPath)

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
  $graphConfig['search'] = Get-FdeGraphSearchFilter
  $graphConfig['showTags'] = $false
  $graphConfig['showAttachments'] = $false
  $graphConfig['collapse-color-groups'] = $false
  $graphConfig['colorGroups'] = @(Get-FdeGraphColorGroups)

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $GraphConfigPath) | Out-Null
  $json = ($graphConfig | ConvertTo-Json -Depth 12)
  $encoding = [System.Text.UTF8Encoding]::new($false)
  if (Test-Path -LiteralPath $GraphConfigPath -PathType Leaf) {
    $existingContent = [System.IO.File]::ReadAllText($GraphConfigPath, $encoding)
    if ($existingContent.TrimEnd() -eq $json.TrimEnd()) {
      return $false
    }
  }
  [System.IO.File]::WriteAllText($GraphConfigPath, $json + [Environment]::NewLine, $encoding)
  return $true
}

$notes = Get-ChildItem -LiteralPath $Vault -Recurse -Force -Filter '*.md' -File |
  Where-Object { Test-FdeCoveredNotePath -Path $_.FullName -Vault $Vault } |
  Sort-Object FullName

$buckets = @()
for ($i = 0; $i -lt $BucketCount; $i++) {
  $buckets += ,([System.Collections.Generic.List[object]]::new())
}

for ($i = 0; $i -lt $notes.Count; $i++) {
  $target = ConvertTo-FdeWikiTarget -Path $notes[$i].FullName -Vault $Vault
  $noteBuckets = Get-StableBuckets -Target $target -Count $BucketCount
  $item = [pscustomobject]@{
    Target = $target
    Name = $notes[$i].BaseName
    Top = (($notes[$i].FullName.Substring($Vault.Length).TrimStart('\')) -split '\\')[0]
  }
  $buckets[$noteBuckets[0]].Add($item)
  $buckets[$noteBuckets[1]].Add($item)
}

$hubMap = @{
  'decisions' = 'hub-lane--decision-system'
  'designs' = 'hub-lane--decision-system'
  'research' = 'hub-lane--evidence-research'
  'research-digest' = 'hub-lane--evidence-research'
  'references' = 'hub-lane--evidence-research'
  'work' = 'hub-lane--execution'
  'handoffs' = 'hub-lane--execution'
  'projects' = 'hub-lane--execution'
  'inbox' = 'hub-intake--unclassified'
  'drafts' = 'hub-intake--unclassified'
  'dev' = 'hub-lane--capture-log'
  'dev-log' = 'hub-lane--capture-log'
  'brain' = 'hub-lane--identity-strategy'
  'lifeops' = 'hub-lane--identity-strategy'
}

$hubDefinitions = @(
  [pscustomobject]@{ FileName = 'hub-intake--unclassified.md'; Title = 'Intake / Unclassified' },
  [pscustomobject]@{ FileName = 'hub-lane--capture-log.md'; Title = 'Capture Log Lane' },
  [pscustomobject]@{ FileName = 'hub-lane--decision-system.md'; Title = 'Decision System Lane' },
  [pscustomobject]@{ FileName = 'hub-lane--evidence-research.md'; Title = 'Evidence / Research Lane' },
  [pscustomobject]@{ FileName = 'hub-lane--execution.md'; Title = 'Execution Lane' },
  [pscustomobject]@{ FileName = 'hub-lane--identity-strategy.md'; Title = 'Identity / Strategy Lane' },
  [pscustomobject]@{ FileName = 'hub-lane--other.md'; Title = 'Other Lane' }
)

$updatedFiles = [System.Collections.Generic.List[string]]::new()
$targetEdgeCounts = @{}
$expectedTargets = @{}

foreach ($note in $notes) {
  $expectedTargets[(ConvertTo-FdeWikiTarget -Path $note.FullName -Vault $Vault)] = $true
}

for ($i = 0; $i -lt $BucketCount; $i++) {
  $fileName = '{0}-{1:D2}.md' -f $shardPrefix, $i
  $path = Join-Path $network $fileName
  $prev = '{0}-{1:D2}' -f $shardPrefix, (($i + $BucketCount - 1) % $BucketCount)
  $next = '{0}-{1:D2}' -f $shardPrefix, (($i + 1) % $BucketCount)

  $topCounts = $buckets[$i] | Group-Object Top | Sort-Object Count -Descending
  $dominantTop = if ($topCounts.Count -gt 0) { $topCounts[0].Name } else { '' }
  $laneHub = if ($hubMap.ContainsKey($dominantTop)) { $hubMap[$dominantTop] } else { 'hub-lane--other' }

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add('---')
  $lines.Add('network_generated: true')
  $lines.Add('network_role: fde_coverage_shard')
  $lines.Add(('bucket: {0}' -f $i))
  $lines.Add(('dominant_lane: {0}' -f $dominantTop))
  $lines.Add(('note_links: {0}' -f $buckets[$i].Count))
  $lines.Add('---')
  $lines.Add('')
  $lines.Add(('# FDE Coverage Shard {0:D2}' -f $i))
  $lines.Add('')
  $lines.Add('This generated shard preserves FDE graph connectivity without editing note bodies.')
  $lines.Add('')
  $lines.Add('## FDE Network Links')
  $lines.Add('- [[_graph-network/FDE-NETWORK|FDE Network]]')
  $lines.Add('- [[_graph-network/NETWORK-GUARANTEE|Network Guarantee]]')
  $lines.Add(('- [[_graph-network/{0}|Previous Coverage Shard]]' -f $prev))
  $lines.Add(('- [[_graph-network/{0}|Next Coverage Shard]]' -f $next))
  $lines.Add(('- [[_graph-network/{0}|Lane Hub]]' -f $laneHub))
  $lines.Add('')
  $lines.Add('## Covered Notes')

  foreach ($item in ($buckets[$i] | Sort-Object Target)) {
    $lines.Add(('- [[{0}|{1}]]' -f $item.Target, $item.Name))
    if (-not $targetEdgeCounts.ContainsKey($item.Target)) {
      $targetEdgeCounts[$item.Target] = 0
    }
    $targetEdgeCounts[$item.Target]++
  }

  if (Write-Utf8IfChanged -Path $path -Lines $lines) {
    $updatedFiles += $fileName
  }
}

$summaryPath = Join-Path $network 'NETWORK-GUARANTEE.md'
$summary = @(
  '---',
  'network_generated: true',
  'network_role: guarantee_root',
  ('bucket_count: {0}' -f $BucketCount),
  ('covered_notes: {0}' -f $notes.Count),
  'minimum_network_edges_per_note: 2',
  '---',
  '',
  '# Network Guarantee',
  '',
  'Every markdown note in the vault, except system folders, is referenced by two FDE coverage shards.',
  '',
  '- [[_graph-network/FDE-NETWORK|FDE Network]]',
  '- [[_graph-network/hub-intake--unclassified|Intake / Unclassified]]',
  ('- [[_graph-network/{0}-00|Coverage Shard Ring Entry]]' -f $shardPrefix)
)
if (Write-Utf8IfChanged -Path $summaryPath -Lines $summary) {
  $updatedFiles += 'NETWORK-GUARANTEE.md'
}

$rootPath = Join-Path $network 'FDE-NETWORK.md'
$rootLines = [System.Collections.Generic.List[string]]::new()
$rootLines.Add('---')
$rootLines.Add('network_generated: true')
$rootLines.Add('network_role: fde_network_root')
$rootLines.Add(('bucket_count: {0}' -f $BucketCount))
$rootLines.Add(('covered_notes: {0}' -f $notes.Count))
$rootLines.Add('---')
$rootLines.Add('')
$rootLines.Add('# FDE Network')
$rootLines.Add('')
$rootLines.Add('Root anchor for generated FDE graph connectivity.')
$rootLines.Add('')
$rootLines.Add('## Anchors')
$rootLines.Add('- [[_graph-network/NETWORK-GUARANTEE|Network Guarantee]]')
$rootLines.Add(('- [[_graph-network/{0}-00|Coverage Shard Ring Entry]]' -f $shardPrefix))
$rootLines.Add('')
$rootLines.Add('## Lane Hubs')
foreach ($hub in $hubDefinitions) {
  $hubTarget = [System.IO.Path]::GetFileNameWithoutExtension($hub.FileName)
  $rootLines.Add(('- [[_graph-network/{0}|{1}]]' -f $hubTarget, $hub.Title))
}
if (Write-Utf8IfChanged -Path $rootPath -Lines $rootLines) {
  $updatedFiles += 'FDE-NETWORK.md'
}

foreach ($hub in $hubDefinitions) {
  $hubTarget = [System.IO.Path]::GetFileNameWithoutExtension($hub.FileName)
  $hubPath = Join-Path $network $hub.FileName
  $hubLines = @(
    '---',
    'network_generated: true',
    'network_role: fde_lane_hub',
    ('hub: {0}' -f $hubTarget),
    '---',
    '',
    ('# {0}' -f $hub.Title),
    '',
    'Generated lane hub for FDE graph connectivity.',
    '',
    '- [[_graph-network/FDE-NETWORK|FDE Network]]',
    '- [[_graph-network/NETWORK-GUARANTEE|Network Guarantee]]'
  )
  if (Write-Utf8IfChanged -Path $hubPath -Lines $hubLines) {
    $updatedFiles += $hub.FileName
  }
}

$staleFiles = @()
if ($PruneStale) {
  $expected = @{}
  for ($i = 0; $i -lt $BucketCount; $i++) {
    $expected[('{0}-{1:D2}.md' -f $shardPrefix, $i)] = $true
  }

  $staleFiles = Get-ChildItem -LiteralPath $network -Force -File |
    Where-Object { ($_.Name -like 'bridge-*.md') -or (($_.Name -like "$shardPrefix-*.md") -and (-not $expected.ContainsKey($_.Name))) }

  if ($staleFiles) {
    New-Item -ItemType Directory -Force -Path $archive | Out-Null
    $oldDir = Join-Path $archive 'stale-bridges'
    New-Item -ItemType Directory -Force -Path $oldDir | Out-Null
    foreach ($file in $staleFiles) {
      Move-Item -LiteralPath $file.FullName -Destination (Join-Path $oldDir $file.Name) -Force
    }
  }
}

$edgeValues = @($targetEdgeCounts.Values)
$lessThanTwo = @($edgeValues | Where-Object { $_ -lt 2 }).Count
$moreThanTwo = @($edgeValues | Where-Object { $_ -gt 2 }).Count
$coveredTargets = $targetEdgeCounts.Count
$missingTargets = @($expectedTargets.Keys | Where-Object { -not $targetEdgeCounts.ContainsKey($_) }).Count
$unresolvedTargets = @($targetEdgeCounts.Keys | Where-Object { -not $expectedTargets.ContainsKey($_) }).Count
$trailingDotTargets = @($targetEdgeCounts.Keys | Where-Object { $_.EndsWith('.') }).Count
$utf8Failures = [System.Collections.Generic.List[string]]::new()
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)

Get-ChildItem -LiteralPath $network -Filter '*.md' -File | ForEach-Object {
  try {
    $null = [System.IO.File]::ReadAllText($_.FullName, $utf8Strict)
  } catch {
    $utf8Failures.Add($_.FullName)
  }
}

$smartConfigPath = Join-Path $Vault '.smart-env\smart_env.json'
$smartExcludesGraphNetwork = $false
if (Test-Path -LiteralPath $smartConfigPath -PathType Leaf) {
  $smartConfig = Get-Content -LiteralPath $smartConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $smartExcludesGraphNetwork = ($smartConfig.smart_sources.folder_exclusions -match '_graph-network')
}

$graphConfigPath = Join-Path $Vault '.obsidian\graph.json'
$graphSettingsUpdated = Ensure-GraphSettings -GraphConfigPath $graphConfigPath
$graphSettingsOk = $false
$missingGraphColorGroups = @()
if (Test-Path -LiteralPath $graphConfigPath -PathType Leaf) {
  $graphConfig = Get-Content -LiteralPath $graphConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $graphColorGroups = @($graphConfig.colorGroups)
  $graphColorQueries = @($graphColorGroups | ForEach-Object { $_.query })
  $missingGraphColorGroups = @(Get-RequiredFdeGraphColorQueries | Where-Object { $graphColorQueries -notcontains $_ })
  $graphColorGroupsOk = (($graphColorGroups.Count -ge 30) -and ($missingGraphColorGroups.Count -eq 0))
  $graphSettingsOk = (($graphConfig.showOrphans -eq $false) -and ($graphConfig.hideUnresolved -eq $true) -and ($graphConfig.'collapse-color-groups' -eq $false) -and $graphColorGroupsOk)
}

$appConfigPath = Join-Path $Vault '.obsidian\app.json'
$appConfig = [ordered]@{}
if (Test-Path -LiteralPath $appConfigPath -PathType Leaf) {
  $rawAppConfig = Get-Content -LiteralPath $appConfigPath -Raw -Encoding UTF8
  if ($null -ne $rawAppConfig -and $rawAppConfig.Trim().Length -gt 0) {
    $existingAppConfig = $rawAppConfig | ConvertFrom-Json
    foreach ($property in $existingAppConfig.PSObject.Properties) {
      $appConfig[$property.Name] = $property.Value
    }
  }
}
$appConfig['userIgnoreFilters'] = @(Get-FdeGraphIgnoreFilters)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $appConfigPath) | Out-Null
$appJson = $appConfig | ConvertTo-Json -Depth 8
$encoding = [System.Text.UTF8Encoding]::new($false)
$appSettingsUpdated = $true
if (Test-Path -LiteralPath $appConfigPath -PathType Leaf) {
  $existingAppContent = [System.IO.File]::ReadAllText($appConfigPath, $encoding)
  $appSettingsUpdated = ($existingAppContent.TrimEnd() -ne $appJson.TrimEnd())
}
if ($appSettingsUpdated) {
  [System.IO.File]::WriteAllText($appConfigPath, $appJson + [Environment]::NewLine, $encoding)
}

$failures = [System.Collections.Generic.List[string]]::new()
if ($coveredTargets -ne $notes.Count) {
  $failures.Add("Covered target count mismatch: covered=$coveredTargets notes=$($notes.Count)")
}
if ($missingTargets -ne 0) {
  $failures.Add("Some notes are missing from generated FDE coverage shard links: $missingTargets")
}
if ($unresolvedTargets -ne 0) {
  $failures.Add("Generated FDE coverage shard links include targets that do not match notes: $unresolvedTargets")
}
if ($trailingDotTargets -ne 0) {
  $failures.Add("Generated FDE coverage shard links include trailing-dot targets: $trailingDotTargets")
}
if ($lessThanTwo -ne 0) {
  $failures.Add("Some notes have fewer than 2 FDE coverage shard edges: $lessThanTwo")
}
if ($moreThanTwo -ne 0) {
  $failures.Add("Some notes have more than 2 FDE coverage shard edges: $moreThanTwo")
}
if ($utf8Failures.Count -ne 0) {
  $failures.Add("UTF-8 validation failed for generated network files: $($utf8Failures.Count)")
}
if (-not $smartExcludesGraphNetwork) {
  $failures.Add("Smart Connections does not exclude _graph-network.")
}
if (-not $graphSettingsOk) {
  $failures.Add("Obsidian graph settings are not guaranteed: require showOrphans=false, hideUnresolved=true, and full FDE/lane graph color groups. Missing color groups: $($missingGraphColorGroups -join ', ')")
}

if ($failures.Count -ne 0) {
  throw ($failures -join [Environment]::NewLine)
}

[pscustomobject]@{
  Vault = $Vault
  CoveredNotes = $notes.Count
  BucketCount = $BucketCount
  GeneratedCoverageShardFiles = $BucketCount
  LinksPerNote = 2
  NetworkFiles = (Get-ChildItem -LiteralPath $network -Filter '*.md' -File | Measure-Object).Count
  UpdatedFiles = $updatedFiles.Count
  StaleMoved = ($staleFiles | Measure-Object).Count
  CoveredTargets = $coveredTargets
  MissingTargets = $missingTargets
  UnresolvedTargets = $unresolvedTargets
  TrailingDotTargets = $trailingDotTargets
  LessThanTwo = $lessThanTwo
  MoreThanTwo = $moreThanTwo
  Utf8Failures = $utf8Failures.Count
  SmartExcludesGraphNetwork = $smartExcludesGraphNetwork
  GraphSettingsOk = $graphSettingsOk
  GraphSettingsUpdated = $graphSettingsUpdated
  AppSettingsUpdated = $appSettingsUpdated
  GraphColorGroups = @($graphConfig.colorGroups).Count
  MissingGraphColorGroups = $missingGraphColorGroups.Count
  GuaranteeOk = $true
  Archive = if (($staleFiles | Measure-Object).Count -gt 0) { $archive } else { $null }
}
