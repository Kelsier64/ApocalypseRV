# Reports broken relative Markdown links. With no arguments, checks every tracked
# Markdown file except the historical folders docs/archive, docs/validation and docs/report.
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments)][string[]]$Path)
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $Path) {
    $Path = @(& git -C $root -c core.quotepath=false ls-files '*.md' | Where-Object { $_ -notmatch '^docs/(archive|validation|report)/' })
}
$broken = 0
foreach ($file in $Path) {
    $full = if ([IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $root $file }
    if (-not (Test-Path -LiteralPath $full)) { Write-Output "MISSING FILE: $file"; $broken++; continue }
    $text = [regex]::Replace([IO.File]::ReadAllText($full, $utf8), '(?ms)^\s*```.*?^\s*```', '')
    foreach ($match in [regex]::Matches($text, '\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)')) {
        $url = $match.Groups[1].Value
        if ($url -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $url.StartsWith('#')) { continue }
        $target = [Uri]::UnescapeDataString(($url -split '#')[0])
        if ($target -and -not (Test-Path -LiteralPath (Join-Path (Split-Path $full) $target))) {
            Write-Output "BROKEN: $file -> $url"
            $broken++
        }
    }
}
Write-Output "Checked $(@($Path).Count) files: $broken broken links."
exit [int]($broken -gt 0)
