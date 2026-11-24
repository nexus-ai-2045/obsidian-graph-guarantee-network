#Requires -Version 5.1

# Native wikilink parsing and the native graph used by the read-only audit.
# Loaded by obsidian-graph-network-lib.ps1. Do not dot-source this file on its own.

function Remove-GraphNetCodeFromMarkdown {
  param([string]$Content)

  # Strip fenced code blocks (``` or ~~~, unclosed fences run to the end) and
  # inline code spans so link examples written as code are not counted. Shared by
  # the wikilink and the Markdown-link parsers.
  $withoutFences = [regex]::Replace([string]$Content, '(?ms)^[ \t]{0,3}(?:(`{3,})(?=[^`\r\n]*\r?$)|(~{3,}))[^\r\n]*(?:\r?\n.*?^[ \t]{0,3}(?(1)\1`*|\2~*)[ \t]*\r?$|.*\z)', '')
  return [regex]::Replace($withoutFences, '(?s)(?<!`)(?<!(?<!\\)\\(?:\\\\)*)(`+)(?!`)(?:(?!\r?\n[ \t]*\r?\n).)+?(?<!`)\1(?!`)', '')
}

function Get-GraphNetMarkdownLinkTargets {
  param([string]$Content)

  # Pull note targets out of Markdown-style links, [text](target) and embeds
  # ![alt](target), which Obsidian resolves like wikilinks. URLs with a scheme
  # (https:, mailto:, obsidian: ...), same-note anchors (#heading), and targets
  # with a non-.md extension (attachments) are skipped. The fragment is cut,
  # the destination is URL-decoded, and a trailing .md is kept for the resolver.
  # A bare destination may hold one level of balanced parentheses, as in
  # Plan(draft).md, which CommonMark allows. An optional title may be
  # wrapped in double quotes, single quotes or parentheses.
  $targets = [System.Collections.Generic.List[string]]::new()
  $linkSource = Remove-GraphNetCodeFromMarkdown -Content $Content
  $pattern = '\[(?:[^\[\]\r\n]|\[[^\[\]\r\n]*\])*\]\(\s*(<[^>\r\n]+>|(?:[^()\s]|\([^()\s]*\))+)(?:\s+(?:"[^"\r\n]*"|''[^''\r\n]*''|\([^()\r\n]*\)))?\s*\)'
  foreach ($match in [regex]::Matches($linkSource, $pattern)) {
    $raw = $match.Groups[1].Value
    if ($raw.StartsWith('<') -and $raw.EndsWith('>')) {
      $raw = $raw.Substring(1, $raw.Length - 2)
    }
    if ($raw -match '^[A-Za-z][A-Za-z0-9+.-]*:') {
      continue
    }
    $hash = $raw.IndexOf('#')
    if ($hash -ge 0) {
      $raw = $raw.Substring(0, $hash)
    }
    try {
      $decoded = [System.Uri]::UnescapeDataString($raw)
    } catch {
      $decoded = $raw
    }
    $decoded = $decoded.Trim()
    if ($decoded.Length -eq 0) {
      continue
    }
    $leaf = $decoded
    $slash = $decoded.LastIndexOfAny([char[]]@('/', '\'))
    if ($slash -ge 0) {
      $leaf = $decoded.Substring($slash + 1)
    }
    $dot = $leaf.LastIndexOf('.')
    if (($dot -gt 0) -and (-not $leaf.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase))) {
      continue
    }
    $targets.Add($decoded)
  }
  return @($targets)
}

function Resolve-GraphNetRelativeTarget {
  param(
    [string]$FromNode,
    [string]$Target
  )

  # Join a Markdown-link target with the linking note's folder and fold . and ..
  # segments. Returns $null when the path climbs above the vault root.
  $folder = ''
  $slash = $FromNode.LastIndexOf('/')
  if ($slash -ge 0) {
    $folder = $FromNode.Substring(0, $slash)
  }
  $joined = if ($folder.Length -gt 0) { $folder + '/' + $Target } else { $Target }
  $parts = [System.Collections.Generic.List[string]]::new()
  foreach ($part in $joined.Split([char[]]@('/'), [System.StringSplitOptions]::RemoveEmptyEntries)) {
    if ($part -eq '.') {
      continue
    }
    if ($part -eq '..') {
      if ($parts.Count -eq 0) {
        return $null
      }
      $parts.RemoveAt($parts.Count - 1)
      continue
    }
    $parts.Add($part)
  }
  return ($parts -join '/')
}

function Get-GraphNetWikilinkTargets {
  param([string]$Content)

  # Pull the link targets out of every [[...]] wikilink in a note body. For each
  # link the alias (target|alias), heading (target#heading), and block reference
  # (target^block) are stripped so only the note-identifying target remains.
  # Embeds (![[...]]) are treated as links too. Whitespace-only targets are
  # dropped. This is the shared wikilink parse for the native connectivity audit.
  $targets = [System.Collections.Generic.List[string]]::new()
  $linkSource = Remove-GraphNetCodeFromMarkdown -Content $Content
  foreach ($match in [regex]::Matches($linkSource, '\[\[([^\[\]]+)\]\]')) {
    $inner = $match.Groups[1].Value
    $pipe = $inner.IndexOf('|')
    if ($pipe -ge 0) {
      $inner = $inner.Substring(0, $pipe)
      # Inside a Markdown table the alias pipe is written escaped, [[note\|alias]].
      if ($inner.EndsWith('\')) {
        $inner = $inner.Substring(0, $inner.Length - 1)
      }
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

function New-GraphNetLinkIndex {
  param(
    [string]$Vault,
    [object[]]$Notes = @()
  )

  # Everything link resolution needs, built once per audit. Paths and basenames
  # are looked up without case, as Obsidian does. Two notes that differ only in
  # case make that path ambiguous instead of silently binding to one of them.
  # Generated notes are indexed only so links to them can be recognized and
  # dropped; they never become nodes.
  $index = [pscustomobject]@{
    Nodes = [System.Collections.Generic.List[string]]::new()
    ByPath = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    AmbiguousPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    ByBasename = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    GeneratedBasenames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    GeneratedPrefix = $script:GraphNetGraphNetworkFolder + '/'
  }

  foreach ($note in $Notes) {
    $node = ConvertTo-GraphNetWikiTarget -Path $note.FullName -Vault $Vault
    $index.Nodes.Add($node)
    if ($index.ByPath.ContainsKey($node)) {
      $null = $index.AmbiguousPaths.Add($node)
    } else {
      $index.ByPath[$node] = $node
    }
    if (-not $index.ByBasename.ContainsKey($note.BaseName)) {
      $index.ByBasename[$note.BaseName] = [System.Collections.Generic.List[string]]::new()
    }
    $index.ByBasename[$note.BaseName].Add($node)
  }

  $network = Get-GraphNetGraphNetworkPath -Vault $Vault
  if (Test-Path -LiteralPath $network -PathType Container) {
    foreach ($generated in @(Get-ChildItem -LiteralPath $network -Filter '*.md' -File)) {
      $null = $index.GeneratedBasenames.Add($generated.BaseName)
    }
  }
  return $index
}

function Resolve-GraphNetLinkTarget {
  param(
    [pscustomobject]$Index,
    [string]$FromNode,
    [string]$Target
  )

  # Resolve one link target the way Obsidian does: relative to the linking
  # note, then as a vault path, then by unique basename. The outcome is one of
  # note, generated, attachment, missing or ambiguous. Only note becomes an
  # edge. generated and attachment are dropped. missing and ambiguous are
  # reported as unresolved. $null means there is nothing to resolve.
  $normalized = ($Target -replace '\\', '/')
  $fromRoot = $normalized.StartsWith('/')
  $normalized = $normalized.TrimStart('/')
  $leafDot = $normalized.LastIndexOf('.')
  if (($leafDot -gt $normalized.LastIndexOf('/')) -and ($script:GraphNetAttachmentExtensions -contains $normalized.Substring($leafDot).ToLowerInvariant())) {
    return [pscustomobject]@{ Outcome = 'attachment'; Node = $null; Target = $normalized }
  }
  if ($normalized.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
    $normalized = $normalized.Substring(0, $normalized.Length - 3)
  }
  if ($normalized.Length -eq 0) {
    return $null
  }

  $candidates = [System.Collections.Generic.List[string]]::new()
  if (-not $fromRoot) {
    $relative = Resolve-GraphNetRelativeTarget -FromNode $FromNode -Target $normalized
    if ($null -ne $relative) {
      $candidates.Add($relative)
    }
  }
  $candidates.Add($normalized)
  foreach ($candidate in $candidates) {
    if ($candidate.StartsWith($Index.GeneratedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      return [pscustomobject]@{ Outcome = 'generated'; Node = $null; Target = $normalized }
    }
    if ($Index.ByPath.ContainsKey($candidate) -and (-not $Index.AmbiguousPaths.Contains($candidate))) {
      return [pscustomobject]@{ Outcome = 'note'; Node = $Index.ByPath[$candidate]; Target = $normalized }
    }
  }

  $base = $normalized.Substring($normalized.LastIndexOf('/') + 1)
  $outcome = 'missing'
  $node = $null
  if ($Index.ByBasename.ContainsKey($base)) {
    if ($Index.ByBasename[$base].Count -eq 1) {
      $outcome = 'note'
      $node = $Index.ByBasename[$base][0]
    } else {
      $outcome = 'ambiguous'
    }
  } elseif ($Index.AmbiguousPaths.Contains($normalized)) {
    $outcome = 'ambiguous'
  } elseif (($normalized.IndexOf('/') -lt 0) -and $Index.GeneratedBasenames.Contains($base)) {
    $outcome = 'generated'
  }
  return [pscustomobject]@{ Outcome = $outcome; Node = $node; Target = $normalized }
}

function Get-GraphNetNativeGraph {
  param(
    [string]$Vault,
    [object[]]$Notes = @()
  )

  # The vault's own undirected link graph over the covered notes, from
  # wikilinks and Markdown links. Links into the generated _graph-network
  # folder are left out, so the machine-added coverage edges never hide the
  # vault's real connectivity. Every covered note is a node even with no
  # edges, so orphans show up. Nodes are file paths, so on a case-sensitive
  # file system Alpha and alpha stay two nodes.
  $encoding = [System.Text.UTF8Encoding]::new($false)
  $index = New-GraphNetLinkIndex -Vault $Vault -Notes $Notes
  $adjacency = [hashtable]::new([System.StringComparer]::Ordinal)
  foreach ($node in $index.Nodes) {
    $adjacency[$node] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  }

  $unresolvedDetails = [System.Collections.Generic.List[object]]::new()
  for ($i = 0; $i -lt $Notes.Count; $i++) {
    $node = $index.Nodes[$i]
    $content = [System.IO.File]::ReadAllText($Notes[$i].FullName, $encoding)
    $targets = @(Get-GraphNetWikilinkTargets -Content $content) + @(Get-GraphNetMarkdownLinkTargets -Content $content)
    foreach ($target in $targets) {
      $resolution = Resolve-GraphNetLinkTarget -Index $index -FromNode $node -Target $target
      if ($null -eq $resolution) {
        continue
      }
      switch ($resolution.Outcome) {
        'note' {
          if ($resolution.Node -cne $node) {
            $null = $adjacency[$node].Add($resolution.Node)
            $null = $adjacency[$resolution.Node].Add($node)
          }
        }
        { $_ -in @('missing', 'ambiguous') } {
          $unresolvedDetails.Add([pscustomobject]@{
            Source = $node
            Target = $resolution.Target
            Reason = $resolution.Outcome
          })
        }
      }
    }
  }

  return [pscustomobject]@{
    Adjacency = $adjacency
    Nodes = @($index.Nodes)
    UnresolvedLinks = $unresolvedDetails.Count
    UnresolvedLinkDetails = @($unresolvedDetails)
  }
}
