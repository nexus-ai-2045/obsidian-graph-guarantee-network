#Requires -Version 5.1

# Graph math shared by the audit and the updater: buckets, adjacency and connected components.
# Loaded by obsidian-graph-network-lib.ps1. Do not dot-source this file on its own.

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
