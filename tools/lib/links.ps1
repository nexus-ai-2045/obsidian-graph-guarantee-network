#Requires -Version 5.1

# Native wikilink parsing and the native graph used by the read-only audit.
# Loaded by obsidian-graph-network-lib.ps1. Do not dot-source this file on its own.

function Get-GraphNetWikilinkTargets {
  param([string]$Content)

  # Pull the link targets out of every [[...]] wikilink in a note body. For each
  # link the alias (target|alias), heading (target#heading), and block reference
  # (target^block) are stripped so only the note-identifying target remains.
  # Embeds (![[...]]) are treated as links too. Whitespace-only targets are
  # dropped. This is the shared wikilink parse for the native connectivity audit.
  $targets = [System.Collections.Generic.List[string]]::new()
  $withoutFences = [regex]::Replace([string]$Content, '(?ms)^[ \t]{0,3}(?:(`{3,})(?=[^`\r\n]*\r?$)|(~{3,}))[^\r\n]*(?:\r?\n.*?^[ \t]{0,3}(?(1)\1`*|\2~*)[ \t]*\r?$|.*\z)', '')
  $linkSource = [regex]::Replace($withoutFences, '(?s)(?<!`)(?<!(?<!\\)\\(?:\\\\)*)(`+)(?!`)(?:(?!\r?\n[ \t]*\r?\n).)+?(?<!`)\1(?!`)', '')
  foreach ($match in [regex]::Matches($linkSource, '\[\[([^\[\]]+)\]\]')) {
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
