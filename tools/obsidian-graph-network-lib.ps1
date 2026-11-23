#Requires -Version 5.1

# Shared helper module for the audit, the updater and the test harness.
# The functions live in tools/lib/ by concern; this file keeps the single
# dot-source entry point that every script already uses.

foreach ($graphNetLibPart in @('config', 'vault-walk', 'graph', 'links', 'generated', 'report')) {
  . (Join-Path (Join-Path $PSScriptRoot 'lib') ($graphNetLibPart + '.ps1'))
}
Remove-Variable -Name graphNetLibPart -ErrorAction SilentlyContinue
