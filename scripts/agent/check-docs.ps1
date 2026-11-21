# Checks project docs: broken relative Markdown links, and files under docs/ that sit
# outside the layout described in docs/README.md. With no arguments, checks every
# tracked or new Markdown file and the whole docs/ tree; with paths, only those files.
# -Root checks another checkout of this repository, such as a task worktree.
[CmdletBinding(PositionalBinding = $false)]
param([string]$Root, [Parameter(ValueFromRemainingArguments)][string[]]$Path)
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
$root = if ($Root) { $Root } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
function Get-GitList([string[]]$Arguments) { @(& git -C $root -c core.quotepath=false @Arguments 2>$null | Where-Object { $_ }) }

if ($Path) {
    $rootPrefix = $root.Replace('\', '/').TrimEnd('/') + '/'
    $files = @($Path | ForEach-Object {
        $file = $_.Replace('\', '/')
        if ($file.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { $file.Substring($rootPrefix.Length) } else { $file }
    })
} else {
    $files = @(Get-GitList @('ls-files', '--cached', '--others', '--exclude-standard', '--', '*.md', 'docs') | Sort-Object -Unique)
}

$problems = 0
$checked = 0
foreach ($file in $files) {
    $full = Join-Path $root $file
    if (-not (Test-Path -LiteralPath $full)) {
        # A tracked file deleted in the working tree is not a problem; a named path that never existed is.
        if ($Path) { Write-Output "MISSING FILE: $file"; $problems++ }
        continue
    }
    if ($file -match '^docs/') {
        $reason = $null
        if ($file -notmatch '^docs/(README\.md$|(systems|guides|plans|reference)/)') {
            $reason = 'docs/ holds only README.md, systems/, guides/, plans/ and reference/; delete documents that will not be used again'
        } elseif ($file -match '^docs/(systems|guides|plans)/' -and $file -notmatch '^docs/(systems|guides|plans)/[^/]+\.md$') {
            $reason = 'systems/, guides/ and plans/ hold Markdown files directly, with no subfolders or other file types'
        } elseif ($file -match '^docs/plans/\d{4}-') {
            $reason = 'name a plan by its topic, without a date'
        }
        if ($reason) { Write-Output "MISPLACED: $file ($reason; see docs/README.md)"; $problems++ }
    }
    if ($file -notmatch '\.md$') { continue }
    $checked++
    $text = [regex]::Replace([IO.File]::ReadAllText($full, $utf8), '(?ms)^\s*```.*?^\s*```', '')
    foreach ($match in [regex]::Matches($text, '\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)')) {
        $url = $match.Groups[1].Value
        if ($url -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $url.StartsWith('#')) { continue }
        $target = [Uri]::UnescapeDataString(($url -split '#')[0])
        if ($target -and -not (Test-Path -LiteralPath (Join-Path (Split-Path $full) $target))) {
            Write-Output "BROKEN: $file -> $url"
            $problems++
        }
    }
}
Write-Output "Checked $checked Markdown files: $problems problems."
exit [int]($problems -gt 0)
