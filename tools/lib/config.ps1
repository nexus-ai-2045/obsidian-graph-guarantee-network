#Requires -Version 5.1

# Shared constants: generated folder name, exclusion lists, path separators and graph colors.
# Loaded by obsidian-graph-network-lib.ps1. Do not dot-source this file on its own.

$script:GraphNetGraphNetworkFolder = '_graph-network'
$script:GraphNetCoverageShardPrefix = 'coverage-shard'
# Linux file systems are case-sensitive, Windows and default macOS volumes are
# not. Folder comparisons follow the file system. Windows PowerShell 5.1 has no
# $IsLinux, which reads as false there.
$script:GraphNetPathComparison = if ((Get-Variable -Name IsLinux -ValueOnly -ErrorAction SilentlyContinue) -eq $true) {
  [System.StringComparison]::Ordinal
} else {
  [System.StringComparison]::OrdinalIgnoreCase
}
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
$script:GraphNetPathSeparators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
$script:GraphNetWikilinkUnsafeChars = [char[]]@('#', '|', '^', '[', ']')

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
