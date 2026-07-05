#Requires -Version 5.1

param(
  [string]$ScriptPath = (Join-Path $PSScriptRoot 'update-obsidian-graph-network.ps1')
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'obsidian-graph-network-lib.ps1')

$tests = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-TestResult {
  param(
    [string]$Name,
    [bool]$Passed,
    [string]$Details = ''
  )

  $tests.Add([pscustomobject]@{
    Name = $Name
    Passed = $Passed
    Details = $Details
  })

  if (-not $Passed) {
    $failures.Add(("{0}: {1}" -f $Name, $Details))
  }
}

function Set-TestFileUtf8 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory, ValueFromPipeline)][string]$Content
  )

  process {
    # PS 5.1 Set-Content -Encoding UTF8 prepends a BOM. Fixtures are written
    # no-BOM so their bytes match how the updater and a real Obsidian vault
    # persist text, keeping the harness aligned with production output.
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
  }
}

function New-TestVault {
  $root = Join-Path ([System.IO.Path]::GetTempPath()) ('obsidian-graph-network-test-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $root | Out-Null

  $dirs = @('.obsidian', '.smart-env', 'inbox', 'work', 'nested\deep', 'unicode-folder', '.trash', '_graph-network', 'node_modules\pkg', '.pytest_cache', 'archive', 'work\.archive')
  foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root $dir) | Out-Null
  }

  @{
    showOrphans = $false
    hideUnresolved = $true
    showAttachments = $false
  } | ConvertTo-Json -Depth 8 | Set-TestFileUtf8 -Path (Join-Path $root '.obsidian\graph.json')

  @{
    smart_sources = @{
      folder_exclusions = '.obsidian,.smart-env,_graph-network'
    }
    smart_blocks = @{
      embed_blocks = $false
      min_chars = 1200
    }
  } | ConvertTo-Json -Depth 8 | Set-TestFileUtf8 -Path (Join-Path $root '.smart-env\smart_env.json')

  $notes = @(
    [pscustomobject]@{ Path = 'root-note.md'; Content = '# Root note' },
    [pscustomobject]@{ Path = 'inbox\capture one.md'; Content = '# Capture one' },
    [pscustomobject]@{ Path = 'work\project-alpha.md'; Content = '# Project alpha' },
    [pscustomobject]@{ Path = 'nested\deep\second-level.md'; Content = '# Second level' },
    [pscustomobject]@{ Path = 'unicode-folder\utf8-note.md'; Content = '# UTF8 note' },
    [pscustomobject]@{ Path = 'inbox\source [bracket] note.md'; Content = '# Bracket note' },
    [pscustomobject]@{ Path = '_graph-network\manual.md'; Content = '# excluded generated note' },
    [pscustomobject]@{ Path = '.trash\deleted.md'; Content = '# excluded trash note' },
    [pscustomobject]@{ Path = 'node_modules\pkg\README.md'; Content = '# excluded dependency readme' },
    [pscustomobject]@{ Path = '.pytest_cache\README.md'; Content = '# excluded cache readme' },
    [pscustomobject]@{ Path = 'archive\old.md'; Content = '# included history note' },
    [pscustomobject]@{ Path = 'work\.archive\old-case.md'; Content = '# included dotted archive note' }
  )

  foreach ($entry in $notes) {
    $path = Join-Path $root $entry.Path
    Set-TestFileUtf8 -Path $path -Content $entry.Content
  }

  return $root
}

function New-SmallTestVault {
  param([int]$NoteCount = 4)

  $root = Join-Path ([System.IO.Path]::GetTempPath()) ('obsidian-graph-network-small-test-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.obsidian') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.smart-env') | Out-Null

  @{
    showOrphans = $false
    hideUnresolved = $true
    showAttachments = $false
  } | ConvertTo-Json -Depth 8 | Set-TestFileUtf8 -Path (Join-Path $root '.obsidian\graph.json')

  @{
    smart_sources = @{
      folder_exclusions = '.obsidian,.smart-env,_graph-network'
    }
  } | ConvertTo-Json -Depth 8 | Set-TestFileUtf8 -Path (Join-Path $root '.smart-env\smart_env.json')

  for ($i = 1; $i -le $NoteCount; $i++) {
    Set-TestFileUtf8 -Path (Join-Path $root ('note-{0}.md' -f $i)) -Content ('# Note {0}' -f $i)
  }

  return $root
}

function New-FolderedTestVault {
  # Vault with a controlled number of distinct top-level folders, used to prove
  # the dynamic lane taxonomy derives one hub per top folder and keeps the
  # generated network a single connected component regardless of folder count.
  param(
    [int]$FolderCount = 1,
    [int]$NotesPerFolder = 2,
    [switch]$IncludeRootNote
  )

  $root = Join-Path ([System.IO.Path]::GetTempPath()) ('obsidian-graph-network-folders-test-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.obsidian') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.smart-env') | Out-Null

  @{
    showOrphans = $false
    hideUnresolved = $true
    showAttachments = $false
  } | ConvertTo-Json -Depth 8 | Set-TestFileUtf8 -Path (Join-Path $root '.obsidian\graph.json')

  @{
    smart_sources = @{
      folder_exclusions = '.obsidian,.smart-env,_graph-network'
    }
  } | ConvertTo-Json -Depth 8 | Set-TestFileUtf8 -Path (Join-Path $root '.smart-env\smart_env.json')

  for ($f = 1; $f -le $FolderCount; $f++) {
    $folder = 'folder-{0:D2}' -f $f
    New-Item -ItemType Directory -Force -Path (Join-Path $root $folder) | Out-Null
    for ($n = 1; $n -le $NotesPerFolder; $n++) {
      Set-TestFileUtf8 -Path (Join-Path $root ('{0}\note-{1}.md' -f $folder, $n)) -Content ('# {0} note {1}' -f $folder, $n)
    }
  }

  if ($IncludeRootNote) {
    Set-TestFileUtf8 -Path (Join-Path $root 'root-level-note.md') -Content '# Root level note'
  }

  return $root
}

function Invoke-NetworkScript {
  param(
    [string]$Vault,
    [int]$BucketCount = 8,
    [switch]$PruneStale
  )

  $archiveRoot = Join-Path $Vault '_archive-outside-network'
  if ($PruneStale) {
    return & $ScriptPath -Vault $Vault -BucketCount $BucketCount -ArchiveRoot $archiveRoot -PruneStale
  }

  return & $ScriptPath -Vault $Vault -BucketCount $BucketCount -ArchiveRoot $archiveRoot
}

function Get-LastResult {
  param([object[]]$Output)

  return @($Output | Where-Object { $_ -is [pscustomobject] } | Select-Object -Last 1)[0]
}

function Get-NoteEdgeCounts {
  param([string]$Vault)

  $network = Get-GraphNetGraphNetworkPath -Vault $Vault
  $counts = @{}

  Get-ChildItem -LiteralPath $network -Filter "$script:GraphNetCoverageShardPrefix-*.md" -File | ForEach-Object {
    Select-String -LiteralPath $_.FullName -Pattern '^- \[\[(.+?)(?:\|.*?)?\]\]$' | ForEach-Object {
      $target = $_.Matches[0].Groups[1].Value
      if ($target -notlike '_graph-network/*') {
        if (-not $counts.ContainsKey($target)) {
          $counts[$target] = 0
        }
        $counts[$target]++
      }
    }
  }

  return $counts
}

function Get-ExpectedNoteTargets {
  param([string]$Vault)

  $targets = [System.Collections.Generic.List[string]]::new()
  Get-ChildItem -LiteralPath $Vault -Recurse -Force -Filter '*.md' -File |
    Where-Object { Test-GraphNetCoveredNotePath -Path $_.FullName -Vault $Vault } |
    ForEach-Object {
      $targets.Add((ConvertTo-GraphNetWikiTarget -Path $_.FullName -Vault $Vault))
    }

  return @($targets | Sort-Object)
}

function Get-ExpectedLaneDefinitions {
  # Recompute the dynamic lane model the same way the updater does, so tests can
  # assert against the top-folder-derived hubs without hard-coding any lane name.
  param([string]$Vault)

  $resolved = (Resolve-Path -LiteralPath $Vault).Path
  $notes = @(Get-GraphNetCoveredNoteFiles -Vault $resolved)
  $tops = @($notes | ForEach-Object { Get-GraphNetTopFolder -Path $_.FullName -Vault $resolved })
  return @(Get-GraphNetLaneDefinitions -TopFolders $tops)
}

function Get-NoteHashes {
  param([string]$Vault)

  $hashes = @{}
  Get-ChildItem -LiteralPath $Vault -Recurse -Force -Filter '*.md' -File |
    Where-Object { $_.FullName -notmatch '\\_graph-network\\' } |
    ForEach-Object {
      $relative = $_.FullName.Substring($Vault.Length).TrimStart('\')
      $hashes[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }

  return $hashes
}

try {
  $vault = New-TestVault
  $beforeHashes = Get-NoteHashes -Vault $vault
  $first = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8)
  $second = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8)
  $afterHashes = Get-NoteHashes -Vault $vault
  $counts = Get-NoteEdgeCounts -Vault $vault
  $expectedTargets = Get-ExpectedNoteTargets -Vault $vault
  $actualTargets = @($counts.Keys | Sort-Object)
  $targetDiffs = @(Compare-Object $expectedTargets $actualTargets)
  $network = Get-GraphNetGraphNetworkPath -Vault $vault
  $expectedLanes = Get-ExpectedLaneDefinitions -Vault $vault

  Add-TestResult 'normal run reports guarantee ok' ($first.GuaranteeOk -eq $true) ($first | Out-String)
  Add-TestResult 'second run is idempotent' ($second.UpdatedFiles -eq 0) ($second | Out-String)
  Add-TestResult 'all expected notes are covered' ($counts.Count -eq 8) "covered=$($counts.Count)"
  Add-TestResult 'covered targets exactly match note paths' ($targetDiffs.Count -eq 0) ($targetDiffs | Out-String)
  Add-TestResult 'covered targets do not keep markdown trailing dots' (($counts.ContainsKey('root-note')) -and (-not $counts.ContainsKey('root-note.'))) (($counts.Keys | Sort-Object) -join ', ')
  Add-TestResult 'update output reports no unresolved targets' (($first.MissingTargets -eq 0) -and ($first.UnresolvedTargets -eq 0) -and ($first.TrailingDotTargets -eq 0)) ($first | Out-String)
  Add-TestResult 'explicit bucket count is honored' (($first.BucketCount -eq 8) -and ($first.BucketCountUsed -eq 8) -and ($first.GeneratedCoverageShardFiles -eq 8)) ($first | Out-String)
  $expectedShard00 = '{0}-00.md' -f $script:GraphNetCoverageShardPrefix
  # The retired project acronym, assembled from character codes so this test file
  # never contains it literally (keeping the whole tools tree grep-clean). Reused
  # for the legacy shard-name guard and the generated-output acronym scan below.
  $forbidden = -join [char[]](102, 100, 101)
  $legacyShard00 = '{0}-coverage-shard-00.md' -f $forbidden
  Add-TestResult 'coverage shards use neutral names' ((Test-Path -LiteralPath (Join-Path $network $expectedShard00)) -and (-not (Test-Path -LiteralPath (Join-Path $network $legacyShard00))) -and (-not (Test-Path -LiteralPath (Join-Path $network 'bridge-00.md')))) "expected $expectedShard00 and no legacy shard names"

  # Dynamic lane taxonomy: the generated hub-lane-- files must equal exactly one
  # per distinct top-level folder of the covered notes, and the intake hub plus
  # the two root anchors must exist.
  $expectedLaneHubFiles = @($expectedLanes | Where-Object { $_.Hub -like 'hub-lane--*' } | ForEach-Object { ('{0}.md' -f $_.Hub) } | Sort-Object)
  $actualLaneHubFiles = @(Get-ChildItem -LiteralPath $network -Filter 'hub-lane--*.md' -File | ForEach-Object { $_.Name } | Sort-Object)
  $laneHubDiffs = @(Compare-Object $expectedLaneHubFiles $actualLaneHubFiles)
  Add-TestResult 'generated lane hubs match the vault top-level folders exactly' ($laneHubDiffs.Count -eq 0) ("expected=" + ($expectedLaneHubFiles -join ', ') + " actual=" + ($actualLaneHubFiles -join ', '))

  $expectedFolderTops = @(Get-ExpectedNoteTargets -Vault $vault | Where-Object { $_ -like '*/*' } | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique)
  $laneHubTitles = @($expectedLanes | Where-Object { $_.Hub -like 'hub-lane--*' } | ForEach-Object { $_.Title } | Sort-Object -Unique)
  $titleDiffs = @(Compare-Object $expectedFolderTops $laneHubTitles)
  Add-TestResult 'lane hub titles are the raw top folder names' ($titleDiffs.Count -eq 0) ("folders=" + ($expectedFolderTops -join ', ') + " titles=" + ($laneHubTitles -join ', '))

  $requiredNetworkFiles = @('graph-network-root.md', 'NETWORK-GUARANTEE.md', 'hub-intake--unclassified.md') + $expectedLaneHubFiles
  $missingNetworkFiles = @($requiredNetworkFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $network $_)) })
  Add-TestResult 'required anchors, intake hub, and dynamic lane hubs exist' ($missingNetworkFiles.Count -eq 0) ($missingNetworkFiles -join ', ')

  # Vault-root notes are routed to the intake hub and stay part of the single
  # connected component.
  Add-TestResult 'vault-root notes route to intake hub inside the connected network' ((Test-Path -LiteralPath (Join-Path $network 'hub-intake--unclassified.md')) -and ($counts.ContainsKey('root-note')) -and ($first.NetworkConnectedComponents -eq 1)) ("intakeExists=" + (Test-Path -LiteralPath (Join-Path $network 'hub-intake--unclassified.md')) + " rootCovered=" + ($counts.ContainsKey('root-note')) + " components=" + $first.NetworkConnectedComponents)

  Add-TestResult 'every covered note has exactly two coverage shard edges' ((@($counts.Values | Where-Object { $_ -ne 2 }).Count) -eq 0) (($counts.GetEnumerator() | Sort-Object Name | Out-String))
  Add-TestResult 'system/cache/generated folders are excluded while archives stay covered' ((-not $counts.ContainsKey('_graph-network/manual')) -and (-not $counts.ContainsKey('.trash/deleted')) -and (-not $counts.ContainsKey('node_modules/pkg/README')) -and (-not $counts.ContainsKey('.pytest_cache/README')) -and ($counts.ContainsKey('archive/old')) -and ($counts.ContainsKey('work/.archive/old-case'))) (($counts.Keys | Sort-Object) -join ', ')
  Add-TestResult 'generated network stays flat' ((Get-ChildItem -LiteralPath (Join-Path $vault '_graph-network') -Directory -Force | Measure-Object).Count -eq 0) 'nested generated directories found'
  Add-TestResult 'note bodies are not mutated' ((Compare-Object ($beforeHashes.GetEnumerator() | Sort-Object Name) ($afterHashes.GetEnumerator() | Sort-Object Name) -Property Name,Value | Measure-Object).Count -eq 0) 'note hash changed'
  Add-TestResult 'utf8 validation is built into update output' ($first.Utf8Failures -eq 0) ($first | Out-String)
  Add-TestResult 'smart exclusion is enforced by update output' ($first.SmartExcludesGraphNetwork -eq $true) ($first | Out-String)
  Add-TestResult 'graph settings are enforced by update output' ($first.GraphSettingsOk -eq $true) ($first | Out-String)
  $graphConfig = Get-Content -LiteralPath (Join-Path $vault '.obsidian\graph.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $appConfig = Get-Content -LiteralPath (Join-Path $vault '.obsidian\app.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $requiredIgnoreFilters = @('**/node_modules/', '**/__pycache__/', '.pytest_cache/')
  $missingIgnoreFilters = @($requiredIgnoreFilters | Where-Object { @($appConfig.userIgnoreFilters) -notcontains $_ })
  Add-TestResult 'app ignore filters exclude cache surfaces but keep graph network visible' (($missingIgnoreFilters.Count -eq 0) -and (@($appConfig.userIgnoreFilters) -notcontains '**/archive/') -and (@($appConfig.userIgnoreFilters) -notcontains '_graph-network/')) (($appConfig | ConvertTo-Json -Depth 8) + [Environment]::NewLine + 'Missing: ' + ($missingIgnoreFilters -join ', '))
  Add-TestResult 'graph search filter excludes cache but not archive surfaces' (($graphConfig.search -match 'node_modules') -and ($graphConfig.search -match 'cache') -and ($graphConfig.search -notmatch 'archive')) $graphConfig.search
  $graphQueries = @($graphConfig.colorGroups | ForEach-Object { $_.query })
  $requiredQueries = @(Get-RequiredGraphNetGraphColorQueries -LaneDefinitions $expectedLanes)
  $missingGraphQueries = @($requiredQueries | Where-Object { $graphQueries -notcontains $_ })
  Add-TestResult 'graph color groups cover anchors, shards, and dynamic lanes' ((@($graphConfig.colorGroups).Count -ge $requiredQueries.Count) -and ($graphConfig.'collapse-color-groups' -eq $false) -and ($missingGraphQueries.Count -eq 0)) (($graphConfig | ConvertTo-Json -Depth 12) + [Environment]::NewLine + 'Missing: ' + ($missingGraphQueries -join ', '))
  $generatedNetworkTargets = [System.Collections.Generic.HashSet[string]]::new()
  Get-ChildItem -LiteralPath $network -Filter '*.md' -File | ForEach-Object {
    $target = '_graph-network/' + [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    $null = $generatedNetworkTargets.Add($target)
  }
  $missingGeneratedTargets = [System.Collections.Generic.List[string]]::new()
  Get-ChildItem -LiteralPath $network -Filter '*.md' -File | ForEach-Object {
    Select-String -LiteralPath $_.FullName -Pattern '\[\[(_graph-network/[^|\]]+)' | ForEach-Object {
      $target = $_.Matches[0].Groups[1].Value
      if (-not $generatedNetworkTargets.Contains($target)) {
        $missingGeneratedTargets.Add($target)
      }
    }
  }
  Add-TestResult 'generated network links resolve internally' (($missingGeneratedTargets | Select-Object -Unique).Count -eq 0) (($missingGeneratedTargets | Select-Object -Unique | Sort-Object) -join ', ')

  # Generated output must be free of the retired project acronym (reusing the
  # $forbidden substring built from character codes above).
  $acronymHits = @()
  Get-ChildItem -LiteralPath $network -Filter '*.md' -File | ForEach-Object {
    $text = [System.IO.File]::ReadAllText($_.FullName, [System.Text.UTF8Encoding]::new($false))
    if ($text -match ('(?i)' + $forbidden)) {
      $acronymHits += $_.Name
    }
  }
  Add-TestResult 'generated output has no retired acronym' ($acronymHits.Count -eq 0) ($acronymHits -join ', ')
} catch {
  Add-TestResult 'fixture normal/idempotent behavior' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  $vault = New-TestVault
  Set-TestFileUtf8 -Path (Join-Path $vault 'new-note.md') -Content '# New note'
  $initial = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8)
  Set-TestFileUtf8 -Path (Join-Path $vault 'late-added.md') -Content '# Late added'
  $incremental = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8)
  Add-TestResult 'incremental add touches only bounded generated files' (($incremental.UpdatedFiles -gt 0) -and ($incremental.UpdatedFiles -le 4)) ($incremental | Out-String)
} catch {
  Add-TestResult 'incremental add behavior' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  $vault = New-TestVault
  $network = Get-GraphNetGraphNetworkPath -Vault $vault
  $staleShard99 = '{0}-99.md' -f $script:GraphNetCoverageShardPrefix
  Set-TestFileUtf8 -Path (Join-Path $network 'bridge-99.md') -Content '# stale'
  Set-TestFileUtf8 -Path (Join-Path $network $staleShard99) -Content '# stale'
  $result = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8 -PruneStale)
  Add-TestResult 'prune stale legacy and shard files only when requested' (($result.StaleMoved -eq 2) -and (-not (Test-Path -LiteralPath (Join-Path $network 'bridge-99.md'))) -and (-not (Test-Path -LiteralPath (Join-Path $network $staleShard99)))) ($result | Out-String)
} catch {
  Add-TestResult 'prune stale behavior' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  # Migration from the previous naming layout: legacy generated files carry the
  # network_generated marker under retired names (an old coverage shard prefix,
  # the old root anchor, and a hub that no longer matches the derived lane
  # model). A plain rerun must fail loudly on them, and a single -PruneStale run
  # must archive every legacy file and restore the guarantee. The retired
  # acronym is assembled from character codes so this file stays grep-clean.
  $vault = New-TestVault
  $network = Get-GraphNetGraphNetworkPath -Vault $vault
  $forbidden = -join [char[]](102, 100, 101)
  $legacyMarker = @(
    '---',
    'network_generated: true',
    'network_role: coverage_shard',
    '---',
    '',
    '# legacy generated file'
  ) -join [Environment]::NewLine
  for ($i = 0; $i -lt 8; $i++) {
    Set-TestFileUtf8 -Path (Join-Path $network ('{0}-coverage-shard-{1:D2}.md' -f $forbidden, $i)) -Content $legacyMarker
  }
  Set-TestFileUtf8 -Path (Join-Path $network ('{0}-NETWORK.md' -f $forbidden.ToUpperInvariant())) -Content $legacyMarker
  Set-TestFileUtf8 -Path (Join-Path $network 'hub-lane--legacy-removed.md') -Content $legacyMarker

  $plainFailed = $false
  try {
    $null = Invoke-NetworkScript -Vault $vault -BucketCount 8
  } catch {
    $plainFailed = $_.Exception.Message -match 'Stale generated network files'
  }
  Add-TestResult 'legacy-named generated files fail a plain rerun without prune' $plainFailed 'plain rerun did not reject legacy-named generated files'

  $migrated = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8 -PruneStale)
  $legacyRemaining = @(Get-ChildItem -LiteralPath $network -Filter '*.md' -File | Where-Object { $_.Name -match ('(?i)' + $forbidden) })
  Add-TestResult 'prune archives legacy-named files and restores the guarantee' (($migrated.GuaranteeOk -eq $true) -and ($migrated.StaleMoved -eq 10) -and ($legacyRemaining.Count -eq 0)) ($migrated | Out-String)
} catch {
  Add-TestResult 'legacy layout migration path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  $vault = New-TestVault
  @{
    smart_sources = @{
      folder_exclusions = '.obsidian,.smart-env'
    }
  } | ConvertTo-Json -Depth 8 | Set-TestFileUtf8 -Path (Join-Path $vault '.smart-env\smart_env.json')
  $failed = $false
  try {
    $null = Invoke-NetworkScript -Vault $vault -BucketCount 8
  } catch {
    $failed = $_.Exception.Message -match 'does not exclude _graph-network'
  }
  Add-TestResult 'missing Smart _graph-network exclusion fails' $failed 'script did not reject missing Smart exclusion'
} catch {
  Add-TestResult 'missing Smart exclusion failure path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  $vault = New-TestVault
  # Drop the legacy Smart Connections config so this case only passes via the current
  # plugin layout (settings.smart_sources.folder_exclusions in the plugin's data.json).
  Remove-Item -LiteralPath (Join-Path $vault '.smart-env\smart_env.json') -Force
  $pluginDir = Join-Path $vault '.obsidian\plugins\open-connections'
  New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
  @{
    installed_at = 1
    last_version = '3.9.47'
    settings = @{
      smart_sources = @{
        folder_exclusions = '_graph-network,_workspace-config-archive,.smart-env'
      }
    }
  } | ConvertTo-Json -Depth 8 | Set-TestFileUtf8 -Path (Join-Path $pluginDir 'data.json')
  $result = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8)
  Add-TestResult 'smart exclusion honored via current plugin data.json' ($result.SmartExcludesGraphNetwork -eq $true) ($result | Out-String)
} catch {
  Add-TestResult 'plugin data.json smart exclusion path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  $vault = New-TestVault
  '{"showOrphans":true,"hideUnresolved":false,"colorGroups":[]}' | Set-TestFileUtf8 -Path (Join-Path $vault '.obsidian\graph.json')
  $expectedLanes = Get-ExpectedLaneDefinitions -Vault $vault
  $requiredCount = @(Get-RequiredGraphNetGraphColorQueries -LaneDefinitions $expectedLanes).Count
  $result = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8)
  $graphConfig = Get-Content -LiteralPath (Join-Path $vault '.obsidian\graph.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  Add-TestResult 'bad graph settings are repaired' (($result.GraphSettingsOk -eq $true) -and ($result.GraphSettingsUpdated -eq $true) -and ($graphConfig.showOrphans -eq $false) -and ($graphConfig.hideUnresolved -eq $true) -and (@($graphConfig.colorGroups).Count -ge $requiredCount) -and ($result.MissingGraphColorGroups -eq 0)) ($graphConfig | ConvertTo-Json -Depth 12)
} catch {
  Add-TestResult 'bad graph setting failure path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  $vault = New-TestVault
  [System.IO.File]::WriteAllText((Join-Path $vault '.obsidian\graph.json'), '', [System.Text.UTF8Encoding]::new($false))
  $expectedLanes = Get-ExpectedLaneDefinitions -Vault $vault
  $requiredCount = @(Get-RequiredGraphNetGraphColorQueries -LaneDefinitions $expectedLanes).Count
  $result = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8)
  $graphConfig = Get-Content -LiteralPath (Join-Path $vault '.obsidian\graph.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  Add-TestResult 'empty graph settings are repaired' (($result.GraphSettingsOk -eq $true) -and ($result.GraphSettingsUpdated -eq $true) -and ($graphConfig.showOrphans -eq $false) -and ($graphConfig.hideUnresolved -eq $true) -and (@($graphConfig.colorGroups).Count -ge $requiredCount)) ($graphConfig | ConvertTo-Json -Depth 12)
} catch {
  Add-TestResult 'empty graph setting failure path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  $failed = $false
  try {
    $null = Invoke-NetworkScript -Vault (Join-Path ([System.IO.Path]::GetTempPath()) 'definitely-missing-vault') -BucketCount 8
  } catch {
    $failed = $_.Exception.Message -match 'Vault directory does not exist'
  }
  Add-TestResult 'missing vault fails clearly' $failed 'script did not reject missing vault'
} catch {
  Add-TestResult 'missing vault failure path' $false $_.Exception.Message
}

try {
  $vault = New-TestVault
  $failed = $false
  try {
    $null = Invoke-NetworkScript -Vault $vault -BucketCount -1
  } catch {
    $failed = $_.Exception.Message -match 'BucketCount must be 0 \(auto\) or at least 2'
  }
  Add-TestResult 'invalid bucket count fails clearly' $failed 'script did not reject BucketCount=-1'
} catch {
  Add-TestResult 'invalid bucket count failure path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  $vault = New-TestVault
  $failed = $false
  try {
    $null = Invoke-NetworkScript -Vault $vault -BucketCount 1
  } catch {
    $failed = $_.Exception.Message -match 'BucketCount must be 0 \(auto\) or at least 2'
  }
  Add-TestResult 'single bucket count fails clearly' $failed 'script did not reject BucketCount=1'
} catch {
  Add-TestResult 'single bucket count failure path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  $tieForward = @(
    [pscustomobject]@{ Top = 'zeta' },
    [pscustomobject]@{ Top = 'alpha' },
    [pscustomobject]@{ Top = 'zeta' },
    [pscustomobject]@{ Top = 'alpha' }
  )
  $tieReversed = @($tieForward[3], $tieForward[2], $tieForward[1], $tieForward[0])
  $majority = @(
    [pscustomobject]@{ Top = 'zeta' },
    [pscustomobject]@{ Top = 'zeta' },
    [pscustomobject]@{ Top = 'alpha' }
  )
  $tieResultA = Get-GraphNetDominantTop -Items $tieForward
  $tieResultB = Get-GraphNetDominantTop -Items $tieReversed
  $majorityResult = Get-GraphNetDominantTop -Items $majority
  $emptyResult = Get-GraphNetDominantTop -Items @()
  Add-TestResult 'dominant top tie-break resolves by ascending name' (($tieResultA -eq 'alpha') -and ($tieResultB -eq 'alpha') -and ($majorityResult -eq 'zeta') -and ($emptyResult -eq '')) "tieA=$tieResultA tieB=$tieResultB majority=$majorityResult empty=$emptyResult"
} catch {
  Add-TestResult 'dominant top tie-break path' $false $_.Exception.Message
}

try {
  # Mixed-case tie must resolve by ordinal order, not culture collation. Ordinal
  # ranks 'Foo' (F = 0x46) before 'bar' (b = 0x62); a culture-sensitive sort
  # would case-insensitively pick 'bar' and diverge across machines.
  $mixedCaseTie = @(
    [pscustomobject]@{ Top = 'bar' },
    [pscustomobject]@{ Top = 'Foo' }
  )
  $mixedResult = Get-GraphNetDominantTop -Items $mixedCaseTie
  Add-TestResult 'dominant top tie-break is ordinal, not culture-sensitive' ($mixedResult -eq 'Foo') "result=$mixedResult (expected Foo)"
} catch {
  Add-TestResult 'dominant top ordinal tie-break path' $false $_.Exception.Message
}

try {
  $allDistinct = $true
  $collisionIndex = -1
  for ($i = 0; $i -lt 200; $i++) {
    $pair = Get-GraphNetStableBuckets -Target ('inbox/generated-note-{0}' -f $i) -Count 17
    if ($pair[0] -eq $pair[1]) {
      $allDistinct = $false
      $collisionIndex = $i
      break
    }
  }
  Add-TestResult 'stable buckets stay distinct for bucket count 17' $allDistinct "same bucket pair at index $collisionIndex"
  $repeatA = Get-GraphNetStableBuckets -Target 'work/stable-target' -Count 17
  $repeatB = Get-GraphNetStableBuckets -Target 'work/stable-target' -Count 17
  Add-TestResult 'stable buckets are deterministic' (($repeatA[0] -eq $repeatB[0]) -and ($repeatA[1] -eq $repeatB[1])) "repeatA=$($repeatA -join ',') repeatB=$($repeatB -join ',')"
} catch {
  Add-TestResult 'stable bucket collision path' $false $_.Exception.Message
}

try {
  $autoTiny = Get-GraphNetAutoBucketCount -CoveredNoteCount 4
  $autoZero = Get-GraphNetAutoBucketCount -CoveredNoteCount 0
  $autoMid = Get-GraphNetAutoBucketCount -CoveredNoteCount 200
  $autoLarge = Get-GraphNetAutoBucketCount -CoveredNoteCount 5000
  Add-TestResult 'auto bucket count clamps between 8 and 64' (($autoTiny -eq 8) -and ($autoZero -eq 8) -and ($autoMid -eq 13) -and ($autoLarge -eq 64)) "tiny=$autoTiny zero=$autoZero mid=$autoMid large=$autoLarge"
} catch {
  Add-TestResult 'auto bucket count formula path' $false $_.Exception.Message
}

try {
  # Slug derivation is deterministic, file-name safe, and resolves collisions in
  # favor of the alphabetically earlier original folder name.
  $slugPlain = ConvertTo-GraphNetHubSlug -Folder 'Dev-Log'
  $slugSpaces = ConvertTo-GraphNetHubSlug -Folder 'My Notes!!'
  $slugUnderscore = ConvertTo-GraphNetHubSlug -Folder 'nexus_ai'
  $collisionLanes = @(Get-GraphNetLaneDefinitions -TopFolders @('a-b', 'a.b'))
  $collisionHubs = @($collisionLanes | Where-Object { $_.Hub -like 'hub-lane--*' } | ForEach-Object { $_.Hub })
  Add-TestResult 'hub slug is deterministic, safe, and collision-resistant' (($slugPlain -eq 'dev-log') -and ($slugSpaces -eq 'my-notes') -and ($slugUnderscore -eq 'nexus-ai') -and ($collisionHubs -contains 'hub-lane--a-b') -and ($collisionHubs -contains 'hub-lane--a-b-2')) "plain=$slugPlain spaces=$slugSpaces underscore=$slugUnderscore collision=$($collisionHubs -join ',')"
} catch {
  Add-TestResult 'hub slug derivation path' $false $_.Exception.Message
}

try {
  $failed = $false
  try {
    $null = & $ScriptPath -BucketCount 8
  } catch {
    $failed = $_.Exception.Message -match 'Vault path is required'
  }
  Add-TestResult 'omitted vault fails clearly with usage' $failed 'script did not reject omitted -Vault'
} catch {
  Add-TestResult 'omitted vault failure path' $false $_.Exception.Message
}

try {
  $vault = New-SmallTestVault -NoteCount 4
  $archiveRoot = Join-Path $vault '_archive-outside-network'
  $auto = Get-LastResult -Output (& $ScriptPath -Vault $vault -ArchiveRoot $archiveRoot)
  $autoRerun = Get-LastResult -Output (& $ScriptPath -Vault $vault -ArchiveRoot $archiveRoot)
  $shardFiles = @(Get-ChildItem -LiteralPath (Get-GraphNetGraphNetworkPath -Vault $vault) -Filter ('{0}-*.md' -f $script:GraphNetCoverageShardPrefix) -File)
  Add-TestResult 'auto bucket count sizes small vault to 8 shards' (($auto.BucketCount -eq 0) -and ($auto.BucketCountUsed -eq 8) -and ($shardFiles.Count -eq 8) -and ($auto.CoveredNotes -eq 4) -and ($auto.GuaranteeOk -eq $true)) ($auto | Out-String)
  Add-TestResult 'auto bucket count rerun is idempotent' (($autoRerun.UpdatedFiles -eq 0) -and ($autoRerun.BucketCountUsed -eq 8)) ($autoRerun | Out-String)
} catch {
  Add-TestResult 'auto bucket count behavior' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  # Shard ring shrink: an explicit wide layout rerun under the auto default
  # must not report a guarantee while higher-numbered shards stay on disk.
  $vault = New-SmallTestVault -NoteCount 20
  $archiveRoot = Join-Path $vault '_archive-outside-network'
  $network = Get-GraphNetGraphNetworkPath -Vault $vault
  $wide = Get-LastResult -Output (& $ScriptPath -Vault $vault -BucketCount 13 -ArchiveRoot $archiveRoot)
  $shrinkFailed = $false
  try {
    $null = & $ScriptPath -Vault $vault -ArchiveRoot $archiveRoot
  } catch {
    $shrinkFailed = $_.Exception.Message -match 'Stale generated network files'
  }
  Add-TestResult 'auto shrink with stale shards on disk fails clearly' (($wide.BucketCountUsed -eq 13) -and $shrinkFailed) 'script did not reject stale on-disk coverage shards after auto shrink'
  $pruned = Get-LastResult -Output (& $ScriptPath -Vault $vault -ArchiveRoot $archiveRoot -PruneStale)
  $shardFiles = @(Get-ChildItem -LiteralPath $network -Filter ('{0}-*.md' -f $script:GraphNetCoverageShardPrefix) -File)
  Add-TestResult 'auto shrink with prune archives stale shards and restores guarantee' (($pruned.BucketCountUsed -eq 8) -and ($pruned.StaleMoved -eq 5) -and ($shardFiles.Count -eq 8) -and ($pruned.GuaranteeOk -eq $true)) ($pruned | Out-String)
} catch {
  Add-TestResult 'auto shrink stale shard behavior' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  # Connectivity invariant: every generated network file must stay reachable
  # from every other one through [[...]] wikilinks even though shards no
  # longer link the root anchors directly. Auto sizing on a small vault
  # resolves to the 8-shard ring.
  $vault = New-SmallTestVault -NoteCount 4
  $archiveRoot = Join-Path $vault '_archive-outside-network'
  $auto = Get-LastResult -Output (& $ScriptPath -Vault $vault -ArchiveRoot $archiveRoot)
  $components = Get-GraphNetNetworkConnectedComponentCount -NetworkPath (Get-GraphNetGraphNetworkPath -Vault $vault)
  Add-TestResult 'auto 8-shard network forms a single connected component' (($auto.BucketCountUsed -eq 8) -and ($components -eq 1) -and ($auto.NetworkConnectedComponents -eq 1)) "bucketCountUsed=$($auto.BucketCountUsed) components=$components reported=$($auto.NetworkConnectedComponents)"
} catch {
  Add-TestResult 'auto 8-shard connectivity path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  # Single top-folder vault: the taxonomy still yields one lane hub plus intake,
  # and the generated network stays a single connected component.
  $vault = New-FolderedTestVault -FolderCount 1 -NotesPerFolder 2
  $archiveRoot = Join-Path $vault '_archive-outside-network'
  $result = Get-LastResult -Output (& $ScriptPath -Vault $vault -ArchiveRoot $archiveRoot)
  $network = Get-GraphNetGraphNetworkPath -Vault $vault
  $components = Get-GraphNetNetworkConnectedComponentCount -NetworkPath $network
  $laneHubFiles = @(Get-ChildItem -LiteralPath $network -Filter 'hub-lane--*.md' -File)
  Add-TestResult 'single top-folder vault stays a single connected component' (($result.GuaranteeOk -eq $true) -and ($components -eq 1) -and ($result.NetworkConnectedComponents -eq 1) -and ($laneHubFiles.Count -eq 1)) "components=$components laneHubs=$($laneHubFiles.Count)"
} catch {
  Add-TestResult 'single top-folder connectivity path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  # Many top-folder vault (12 folders): one lane hub per folder and connectivity
  # is still a single component. Uses auto bucket sizing.
  $vault = New-FolderedTestVault -FolderCount 12 -NotesPerFolder 2 -IncludeRootNote
  $archiveRoot = Join-Path $vault '_archive-outside-network'
  $result = Get-LastResult -Output (& $ScriptPath -Vault $vault -ArchiveRoot $archiveRoot)
  $network = Get-GraphNetGraphNetworkPath -Vault $vault
  $components = Get-GraphNetNetworkConnectedComponentCount -NetworkPath $network
  $laneHubFiles = @(Get-ChildItem -LiteralPath $network -Filter 'hub-lane--*.md' -File)
  Add-TestResult 'twelve top-folder vault yields one hub per folder and one component' (($result.GuaranteeOk -eq $true) -and ($components -eq 1) -and ($result.NetworkConnectedComponents -eq 1) -and ($laneHubFiles.Count -eq 12) -and (Test-Path -LiteralPath (Join-Path $network 'hub-intake--unclassified.md'))) "components=$components laneHubs=$($laneHubFiles.Count)"
} catch {
  Add-TestResult 'twelve top-folder connectivity path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  # Same connectivity invariant under an explicit wide ring, plus the degree
  # reduction contract: no shard links a root anchor directly, and root
  # anchor degree stays bounded by the lane hub count instead of growing
  # with the 17 shards.
  $vault = New-TestVault
  $result = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 17)
  $network = Get-GraphNetGraphNetworkPath -Vault $vault
  $components = Get-GraphNetNetworkConnectedComponentCount -NetworkPath $network
  $adjacency = Get-GraphNetNetworkAdjacency -NetworkPath $network
  $rootDegree = $adjacency['_graph-network/graph-network-root'].Count
  $guaranteeDegree = $adjacency['_graph-network/NETWORK-GUARANTEE'].Count
  $shardsLinkingRoots = 0
  Get-ChildItem -LiteralPath $network -Filter ('{0}-*.md' -f $script:GraphNetCoverageShardPrefix) -File | ForEach-Object {
    $content = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    if (($content -match '\[\[_graph-network/graph-network-root') -or ($content -match '\[\[_graph-network/NETWORK-GUARANTEE')) {
      $shardsLinkingRoots++
    }
  }
  Add-TestResult 'bucket count 17 network forms a single connected component' (($result.BucketCountUsed -eq 17) -and ($components -eq 1) -and ($result.NetworkConnectedComponents -eq 1)) "bucketCountUsed=$($result.BucketCountUsed) components=$components reported=$($result.NetworkConnectedComponents)"
  Add-TestResult 'coverage shards do not link root anchors directly' ($shardsLinkingRoots -eq 0) "shards linking roots=$shardsLinkingRoots"
  Add-TestResult 'root anchor degree stays bounded by lane hub count' (($rootDegree -le 10) -and ($guaranteeDegree -le 10)) "rootDegree=$rootDegree guaranteeDegree=$guaranteeDegree"
} catch {
  Add-TestResult 'bucket count 17 connectivity path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  # Failure path: an isolated file carrying the network_generated marker
  # splits the generated wikilink graph, so the updater must refuse to
  # report a guarantee instead of shipping a disconnected island.
  $vault = New-TestVault
  $network = Get-GraphNetGraphNetworkPath -Vault $vault
  $islandLines = @(
    '---',
    'network_generated: true',
    'network_role: lane_hub',
    'hub: island',
    '---',
    '',
    '# Island',
    '',
    'Isolated generated-marker file used by the connectivity failure case.'
  )
  Set-TestFileUtf8 -Path (Join-Path $network 'hub-island-disconnected.md') -Content ($islandLines -join [Environment]::NewLine)
  $failed = $false
  try {
    $null = Invoke-NetworkScript -Vault $vault -BucketCount 8
  } catch {
    $failed = $_.Exception.Message -match 'single connected wikilink component'
  }
  Add-TestResult 'disconnected generated island fails the update' $failed 'script did not reject a disconnected generated network file'
} catch {
  Add-TestResult 'disconnected island failure path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  # Pruned traversal equivalence: planting notes deep inside excluded trees
  # (node_modules, .git, __pycache__, a cache folder, .obsidian) must leave
  # the covered note set unchanged, and the pruning walk must return exactly
  # the same files as a full recursive scan filtered by
  # Test-GraphNetCoveredNotePath.
  $vault = New-TestVault
  $plantedNotes = @(
    'node_modules\pkg\dist\docs\excluded-dependency-doc.md',
    '.git\info\excluded-git-note.md',
    'work\__pycache__\excluded-bytecode-note.md',
    'work\build-cache\notes\excluded-cache-note.md',
    '.obsidian\plugins\sample\excluded-plugin-note.md'
  )
  foreach ($note in $plantedNotes) {
    $notePath = Join-Path $vault $note
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $notePath) | Out-Null
    Set-TestFileUtf8 -Path $notePath -Content '# planted excluded note'
  }
  $resolvedVault = (Resolve-Path -LiteralPath $vault).Path
  $prunedPaths = @(Get-GraphNetCoveredNoteFiles -Vault $resolvedVault | ForEach-Object { $_.FullName })
  $fullScanPaths = @(Get-ChildItem -LiteralPath $resolvedVault -Recurse -Force -Filter '*.md' -File |
    Where-Object { Test-GraphNetCoveredNotePath -Path $_.FullName -Vault $resolvedVault } |
    Sort-Object FullName |
    ForEach-Object { $_.FullName })
  $walkDiffs = @(Compare-Object $prunedPaths $fullScanPaths)
  $plantedLeaks = @($prunedPaths | Where-Object { $_ -match 'excluded-' })
  Add-TestResult 'pruned walk matches full scan with planted excluded-directory notes' (($walkDiffs.Count -eq 0) -and ($prunedPaths.Count -eq 8) -and ($plantedLeaks.Count -eq 0)) ('diffs=' + ($walkDiffs | Out-String) + ' pruned=' + ($prunedPaths -join ', '))
} catch {
  Add-TestResult 'pruned walk equivalence path' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

$tests | Format-Table -AutoSize

if ($failures.Count -ne 0) {
  Write-Error ("Graph network tests failed:{0}{1}" -f [Environment]::NewLine, ($failures -join [Environment]::NewLine))
  exit 1
}

[pscustomobject]@{
  Tests = $tests.Count
  Failed = 0
  Passed = $tests.Count
}
