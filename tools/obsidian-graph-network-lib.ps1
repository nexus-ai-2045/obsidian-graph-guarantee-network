$script:FdeGraphNetworkFolder = '_graph-network'
$script:FdeCoverageShardPrefix = 'fde-coverage-shard'
$script:FdeGraphExcludedTopFolders = @('.obsidian', '.smart-env', '.trash', $script:FdeGraphNetworkFolder)

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
  $top = ($relative -split '\\')[0]
  return ($script:FdeGraphExcludedTopFolders -notcontains $top)
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
