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

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
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
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root '.obsidian\graph.json') -Encoding UTF8

  @{
    smart_sources = @{
      folder_exclusions = '.obsidian,.smart-env,_graph-network'
    }
    smart_blocks = @{
      embed_blocks = $false
      min_chars = 1200
    }
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root '.smart-env\smart_env.json') -Encoding UTF8

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
    Set-Content -LiteralPath $path -Value $entry.Content -Encoding UTF8
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

  $network = Get-FdeGraphNetworkPath -Vault $Vault
  $counts = @{}

  Get-ChildItem -LiteralPath $network -Filter "$script:FdeCoverageShardPrefix-*.md" -File | ForEach-Object {
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
    Where-Object { Test-FdeCoveredNotePath -Path $_.FullName -Vault $Vault } |
    ForEach-Object {
      $targets.Add((ConvertTo-FdeWikiTarget -Path $_.FullName -Vault $Vault))
    }

  return @($targets | Sort-Object)
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

  Add-TestResult 'normal run reports guarantee ok' ($first.GuaranteeOk -eq $true) ($first | Out-String)
  Add-TestResult 'second run is idempotent' ($second.UpdatedFiles -eq 0) ($second | Out-String)
  Add-TestResult 'all expected notes are covered' ($counts.Count -eq 8) "covered=$($counts.Count)"
  Add-TestResult 'covered targets exactly match note paths' ($targetDiffs.Count -eq 0) ($targetDiffs | Out-String)
  Add-TestResult 'covered targets do not keep markdown trailing dots' (($counts.ContainsKey('root-note')) -and (-not $counts.ContainsKey('root-note.'))) (($counts.Keys | Sort-Object) -join ', ')
  Add-TestResult 'update output reports no unresolved targets' (($first.MissingTargets -eq 0) -and ($first.UnresolvedTargets -eq 0) -and ($first.TrailingDotTargets -eq 0)) ($first | Out-String)
  $expectedShard00 = '{0}-00.md' -f $script:FdeCoverageShardPrefix
  Add-TestResult 'coverage shards use FDE names' ((Test-Path -LiteralPath (Join-Path (Get-FdeGraphNetworkPath -Vault $vault) $expectedShard00)) -and (-not (Test-Path -LiteralPath (Join-Path (Get-FdeGraphNetworkPath -Vault $vault) 'bridge-00.md')))) "expected $expectedShard00 and no bridge-00.md"
  $requiredNetworkFiles = @(
    'FDE-NETWORK.md',
    'NETWORK-GUARANTEE.md',
    'hub-intake--unclassified.md',
    'hub-lane--capture-log.md',
    'hub-lane--decision-system.md',
    'hub-lane--evidence-research.md',
    'hub-lane--execution.md',
    'hub-lane--identity-strategy.md',
    'hub-lane--other.md'
  )
  $missingNetworkFiles = @($requiredNetworkFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path (Get-FdeGraphNetworkPath -Vault $vault) $_)) })
  Add-TestResult 'required FDE anchors and lane hubs exist' ($missingNetworkFiles.Count -eq 0) ($missingNetworkFiles -join ', ')
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
  $missingGraphQueries = @(Get-RequiredFdeGraphColorQueries | Where-Object { $graphQueries -notcontains $_ })
  Add-TestResult 'graph color groups cover FDE and top-level lanes' ((@($graphConfig.colorGroups).Count -ge 30) -and ($graphConfig.'collapse-color-groups' -eq $false) -and ($missingGraphQueries.Count -eq 0)) (($graphConfig | ConvertTo-Json -Depth 12) + [Environment]::NewLine + 'Missing: ' + ($missingGraphQueries -join ', '))
  $generatedNetworkTargets = [System.Collections.Generic.HashSet[string]]::new()
  Get-ChildItem -LiteralPath (Get-FdeGraphNetworkPath -Vault $vault) -Filter '*.md' -File | ForEach-Object {
    $target = '_graph-network/' + [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    $null = $generatedNetworkTargets.Add($target)
  }
  $missingGeneratedTargets = [System.Collections.Generic.List[string]]::new()
  Get-ChildItem -LiteralPath (Get-FdeGraphNetworkPath -Vault $vault) -Filter '*.md' -File | ForEach-Object {
    Select-String -LiteralPath $_.FullName -Pattern '\[\[(_graph-network/[^|\]]+)' | ForEach-Object {
      $target = $_.Matches[0].Groups[1].Value
      if (-not $generatedNetworkTargets.Contains($target)) {
        $missingGeneratedTargets.Add($target)
      }
    }
  }
  Add-TestResult 'generated FDE network links resolve internally' (($missingGeneratedTargets | Select-Object -Unique).Count -eq 0) (($missingGeneratedTargets | Select-Object -Unique | Sort-Object) -join ', ')
} catch {
  Add-TestResult 'fixture normal/idempotent behavior' $false $_.Exception.Message
} finally {
  if ($vault -and (Test-Path -LiteralPath $vault)) {
    Remove-Item -LiteralPath $vault -Recurse -Force
  }
}

try {
  $vault = New-TestVault
  Set-Content -LiteralPath (Join-Path $vault 'new-note.md') -Value '# New note' -Encoding UTF8
  $initial = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8)
  Set-Content -LiteralPath (Join-Path $vault 'late-added.md') -Value '# Late added' -Encoding UTF8
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
  $network = Get-FdeGraphNetworkPath -Vault $vault
  $staleShard99 = '{0}-99.md' -f $script:FdeCoverageShardPrefix
  Set-Content -LiteralPath (Join-Path $network 'bridge-99.md') -Value '# stale' -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $network $staleShard99) -Value '# stale' -Encoding UTF8
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
  $vault = New-TestVault
  @{
    smart_sources = @{
      folder_exclusions = '.obsidian,.smart-env'
    }
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $vault '.smart-env\smart_env.json') -Encoding UTF8
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
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $pluginDir 'data.json') -Encoding UTF8
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
  '{"showOrphans":true,"hideUnresolved":false,"colorGroups":[]}' | Set-Content -LiteralPath (Join-Path $vault '.obsidian\graph.json') -Encoding UTF8
  $result = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8)
  $graphConfig = Get-Content -LiteralPath (Join-Path $vault '.obsidian\graph.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  Add-TestResult 'bad graph settings are repaired' (($result.GraphSettingsOk -eq $true) -and ($result.GraphSettingsUpdated -eq $true) -and ($graphConfig.showOrphans -eq $false) -and ($graphConfig.hideUnresolved -eq $true) -and (@($graphConfig.colorGroups).Count -ge 30) -and ($result.MissingGraphColorGroups -eq 0)) ($graphConfig | ConvertTo-Json -Depth 12)
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
  $result = Get-LastResult -Output (Invoke-NetworkScript -Vault $vault -BucketCount 8)
  $graphConfig = Get-Content -LiteralPath (Join-Path $vault '.obsidian\graph.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  Add-TestResult 'empty graph settings are repaired' (($result.GraphSettingsOk -eq $true) -and ($result.GraphSettingsUpdated -eq $true) -and ($graphConfig.showOrphans -eq $false) -and ($graphConfig.hideUnresolved -eq $true) -and (@($graphConfig.colorGroups).Count -ge 30)) ($graphConfig | ConvertTo-Json -Depth 12)
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
    $null = Invoke-NetworkScript -Vault $vault -BucketCount 1
  } catch {
    $failed = $_.Exception.Message -match 'BucketCount must be at least 2'
  }
  Add-TestResult 'invalid bucket count fails clearly' $failed 'script did not reject BucketCount=1'
} catch {
  Add-TestResult 'invalid bucket count failure path' $false $_.Exception.Message
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
