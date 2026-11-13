# Prints every named GDScript class in game code with its base class and first
# doc-comment line, straight from the source. Optional filter matches path or class.
[CmdletBinding()]
param([string]$Filter = '')
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$files = @(& git -C $root -c core.quotepath=false ls-files '*.gd' | Where-Object { $_ -notmatch '^(tests|scripts|art_source|docs|\.claude)/' })
$rows = foreach ($file in $files) {
    $lines = [IO.File]::ReadAllLines((Join-Path $root $file), $utf8)
    $class = ($lines | Select-String -Pattern '^class_name\s+(\w+)' | Select-Object -First 1)
    if (-not $class) { continue }
    $name = $class.Matches[0].Groups[1].Value
    if ($Filter -and $file -notlike "*$Filter*" -and $name -notlike "*$Filter*") { continue }
    $base = ($lines | Select-String -Pattern '^extends\s+(\S+)' | Select-Object -First 1)
    $doc = ($lines | Select-Object -First 15 | Select-String -Pattern '^##\s*(.+)$' | Select-Object -First 1)
    [PSCustomObject]@{
        Path = $file; Class = $name
        Base = if ($base) { $base.Matches[0].Groups[1].Value.Trim('"') } else { '' }
        Doc = if ($doc) { $doc.Matches[0].Groups[1].Value.Trim() } else { '' }
    }
}
$area = ''
foreach ($row in $rows | Sort-Object Path) {
    $top = ($row.Path -split '/')[0]
    if ($top -ne $area) { $area = $top; Write-Output "`n## $area" }
    $suffix = if ($row.Doc) { " - $($row.Doc)" } else { '' }
    Write-Output "$($row.Class) ($($row.Base)) $($row.Path)$suffix"
}
Write-Output "`n$(@($rows).Count) classes"
