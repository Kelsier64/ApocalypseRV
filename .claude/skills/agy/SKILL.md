---
name: agy
description: Delegate work to Google Antigravity CLI (agy) — a second coding agent running Gemini (and other) models. Use when the user asks to "use agy / Antigravity / Gemini", wants a second opinion or independent code review, wants a task run in parallel by another agent, or wants to compare answers across models. Not for controlling the Antigravity desktop IDE.
---

# Antigravity CLI (agy)

agy is a separate agent CLI already installed and signed in on this machine (Windows).
You drive it in **print mode**: one prompt in, one JSON result out. It runs as a separate agent: it can read and edit files and run commands in its own workspace, so give it scope on purpose.

## Locate the binary

Use `agy` if it is on PATH. Otherwise use the full path. In the PowerShell tool:

```powershell
$agy = (Get-Command agy -ErrorAction SilentlyContinue).Source
if (-not $agy) { $agy = "$env:LOCALAPPDATA\agy\bin\agy.exe" }
```

(The Claude desktop app on Windows may run in a packaged sandbox. If `Test-Path $agy` is false, check
`$env:LOCALAPPDATA\Packages\Claude_*\LocalCache\Local\agy\bin\agy.exe`.)

## Core call

Run from the directory agy should treat as its workspace.

Pass the prompt on **stdin**, never as `-p "<text>"`: Windows PowerShell 5.1 does not escape embedded double quotes, so a prompt with `"two words"` splits into several arguments and agy exits with code 2.

```powershell
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)  # 5.1 sends ASCII to stdin by default
$ro = Join-Path (git rev-parse --show-toplevel) '.claude\skills\agy\read-only-settings.json'
# write the brief to <scratchpad>\brief.md first
Push-Location "<project dir>"
$out = Get-Content -Raw -Encoding utf8 "<scratchpad>\brief.md" |
  & $agy --mode plan --settings $ro --output-format json --print-timeout 600s 2>$null | Out-String
$code = $LASTEXITCODE
Pop-Location
$r = $out | ConvertFrom-Json
```

`status` alone is not enough:
- `$code` non-zero: argument or startup error. Rerun without `2>$null` to see it.
- `response` empty or `denied_actions` non-empty: agy hit a blocked action and ended its turn, though `status` says SUCCESS.
- Keep `conversation_id` for `--conversation` follow-ups.

stderr carries progress noise ("Fetching ..."). Long tasks: run with `run_in_background` and wait for the notification. Don't poll.

## Read-only work

`--mode plan` blocks every shell command, and a denial tells agy not to try another route, so it stops with an empty answer. It can still read files by path, but cannot list or search on its own.

`read-only-settings.json` (next to this file) allows single plain `git grep|ls-files|log|show|diff|status` commands, with no pipes, `;`, redirects, line breaks or `$()`. It denies flags that write files, run programs or read outside the repo. Rules are full-string regex matches. This covers tracked files only. Start every read-only brief with:

> Read-only task. To list or search, run single plain git commands such as `git ls-files <dir>` and `git grep -n <pattern> -- <path>`; no pipes, `;` or redirects. Read files with your file-reading tool. Any other shell command will be denied.

## Choosing a mode (pick the least power that does the job)

| Goal | Flags |
|---|---|
| Question, research, review, second opinion (read-only) | `--mode plan --settings $ro` |
| Let it edit files, but ask before risky commands | `--mode accept-edits` |
| Fully autonomous in a throwaway dir or worktree | `--mode auto` (add `--sandbox` to restrict terminal) |

Never pass `--dangerously-skip-permissions` unless the user explicitly asks for it in this conversation.
In print mode there is no human to approve prompts, so if agy stalls or reports a permission refusal, tell the user rather than escalating flags on your own.

If agy will edit files in the user's repo, prefer pointing it at a separate git worktree or a copy, then review its diff yourself before anything is kept.

## Useful flags

- `--model <slug>`: list slugs with `& $agy models`. The default comes from `model` in `~/.gemini/antigravity-cli/settings.json` (currently `gemini-4-hydrogen-medium`).
- `--settings <json or path>`: settings for this run only, merged with the saved ones and never written back.
- `--effort low|medium|high|xhigh|max`
- `--add-dir <path>`: give it extra directories (repeatable).
- `--conversation <id>`: continue a previous print-mode conversation (follow-up questions).
- `--json-schema '<schema or path>'`: force a structured result, read from `structured_output`.
- `--output-format stream-json`: NDJSON events, for watching progress.

## Patterns

**Second opinion / review**
```powershell
"<read-only preamble> Review the uncommitted changes in this repo (run git diff). List real bugs only, with file:line and why. No style nits." |
  & $agy --mode plan --settings $ro --output-format json 2>$null
```

**Compare models**: run the same `--mode plan` prompt with two `--model` values and summarize differences.

**Delegate a self-contained task**: give a full brief (goal, files, constraints, what "done" looks like). agy does not see this conversation.

## Reporting back

- Treat agy's output as another agent's claims: verify key facts (open the files, run the tests) before telling the user something is true.
- Quote or summarize its `response`; mention which model and mode were used.
- If `status` isn't SUCCESS, or the call timed out, say so and show the error.

## Troubleshooting

- "Please sign in": the user must run `agy` interactively in their own terminal and finish Google sign-in. You can't do the sign-in for them.
- Update: `& $agy update`. Version: `& $agy --version`.
