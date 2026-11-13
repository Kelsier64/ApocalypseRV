# PreToolUse guard for file edits: keeps world-space text nodes out of game code
# (CLAUDE.md, In-Game Text). Reads the hook payload from stdin; prints a deny
# decision when needed and otherwise stays silent.
param()
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
$root = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -replace '\\', '/'
try { $tool = ([Console]::In.ReadToEnd().TrimStart([char]0xFEFF) | ConvertFrom-Json).tool_input } catch { exit 0 }
if ($null -eq $tool) { exit 0 }

$path = "$($tool.file_path)" -replace '\\', '/'
if (-not $path.StartsWith("$root/", [StringComparison]::OrdinalIgnoreCase)) { exit 0 }
$relative = $path.Substring($root.Length + 1)
if ($relative -notmatch '\.(gd|tscn|tres|scn)$') { exit 0 }
if ($relative -match '^(tests|art_source|docs|scripts|\.claude)/') { exit 0 }

$text = (@($tool.content, $tool.new_string) + @($tool.edits | ForEach-Object { $_.new_string })) -join "`n"
if ($text -cnotmatch '\b(Label3D|TextMesh)\b') { exit 0 }

$reason = "Blocked by the CLAUDE.md In-Game Text rule: this edit adds Label3D/TextMesh to $relative. " +
    'Put prompts and status in screen-space UI; world text must be integrated texture, decal, or device-screen art. ' +
    'If the user explicitly wants an exception, ask them to make this edit themselves.'
@{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } } |
    ConvertTo-Json -Compress -Depth 4
exit 0
