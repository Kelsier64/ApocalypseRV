---
name: agy-delegate
description: Delegate scoped research, code review, implementation, or validation tasks to Google Antigravity CLI (agy), collect results, and verify the work. Use when the user asks to give work to agy/Antigravity or the project explicitly permits external-agent delegation.
---

# Delegate to agy

Use agy as a worker; Codex owns integration and the final answer. Explicit user instructions take precedence. Delegation does not expand task permissions or scope. Honor project limits, including tasks the primary agent must do itself.

## Prepare the handoff

- Inspect `Get-Command agy` and `agy --help` on Windows (or `command -v agy` elsewhere). Installed help takes precedence over examples from another version. Read [references/cli-notes.md](references/cli-notes.md) for advanced flags or permission troubleshooting.
- Set an explicit absolute cwd. For repository work, inspect applicable instructions and current diff/status. For overlapping changes, use an available isolated checkout or assign disjoint file ownership. A new agy conversation does not isolate files.
- Write a UTF-8 prompt file with file tools. Include the objective, permitted inputs, ownership, relevant repository instructions, acceptance criteria, requested checks, and expected report. agy does not inherit this chat. Include only task-relevant context; do not include credentials.
- For research/review use `--mode plan` and explicitly prohibit modifications. For already-authorized implementation use `--mode accept-edits`. Planning mode requests an outline; it is not an access-control guarantee. The helper requests agy's terminal sandbox, which is separate from Codex's sandbox and does not limit every agent tool.

Useful handoff shape (adapt to the task):

```text
Objective: ...
Workspace and inputs: ...
Ownership: You may change only ... . Other agents may be working here;
preserve their edits. Do not commit, push, publish, or change global settings.
Instructions: Follow these relevant repository requirements: ...
Acceptance criteria: ...
Validation: Run ... if permitted; otherwise state which checks were blocked.
Report: Findings/changes with file locations, checks actually run and their
results, limitations, and any action still needed. Do not delegate again.
```

## Run and observe

Use [scripts/delegate.py](scripts/delegate.py) for file-based prompts, Unicode, and reliable capture. It passes an argument array with no shell interpolation and sends one NDJSON stdin message. It creates a fresh output directory and never overwrites an earlier run. Python 3 is required; locate an installed runtime, or use the app's `load_workspace_dependencies` tool when available. If Python is unavailable, use a direct CLI call rather than automatically installing a runtime.

PowerShell example, with actual absolute paths substituted:

```powershell
& $pythonExe $delegateScript --workdir $workspacePath --prompt-file $promptPath --output-dir $newRunPath --mode plan --model gemini-3.8-flash-high --timeout 600
```

Use `--mode accept-edits` for implementation. The helper accepts `--model`, `--agent`, and `--effort low|medium|high`; `--schema-file` accepts a local JSON schema for a structured final answer. Discover agent IDs with `agy agents` before setting them.

### Model preference

The user's default model choice for delegated tasks is **Gemini 3.8 Flash**, using the High variant `gemini-3.8-flash-high` for coding tasks. The standalone helper pins this ID by default, so it does not silently inherit agy's configured model. A later explicit user model or effort choice overrides this default. Before dispatching, confirm the selected ID with `agy models` in the authorized environment; pass the actual ID with `--model` when overriding the helper. Never invent a model slug or substitute a nearby version.

If the selected model is absent, report that it is unavailable and do not start the delegated task. Available alternatives may be reported, but require a user choice before using one. The helper relies on agy to reject an unavailable model; it never falls back automatically.

Short tool-free connectivity check (only when needed):

```powershell
agy --print 'Do not use tools or access files. Reply exactly AGY_OK.' --output-format json --sandbox --print-timeout 45s
```

If Codex's sandbox prevents keyring access, agy state/log writes, or model network access, request normal shell escalation for the specific authorized run. On this machine the same connectivity test failed in Codex's sandbox and succeeded outside it. A sandbox login error does not establish that the user's account is signed out. Do not read or export credential stores. If the authorized environment still needs login, let the user authenticate interactively.

Use a yielding execution call for long runs and keep the user informed. The helper timeout bounds the whole run; tool waits should remain short enough for updates. Read `events.ndjson` for progress and `stderr.log` for diagnostics. A tool session ID is not an agy conversation ID. Avoid concurrent writers to the same files or concurrent turns against one agy conversation.

## Collect, continue, and verify

The helper saves `request.json`, `prompt.txt`, `events.ndjson`, `stderr.log`, `result.json`, `response.txt`, and `report.json`, and prints a compact report with paths and conversation ID.

- `transport_success` requires exit 0, one valid terminal `SUCCESS` result, valid event JSON, matching cwd, and matching init/result/requested conversation IDs. It establishes a response, not task completion.
- Read `response.txt` and `stderr.log`. Inspect denied/error tool events and actual deliverables. Headless tool approval can be denied while the overall run succeeds; requested tests may never have run.
- For code, inspect the diff, preserve unrelated edits, and run appropriate checks yourself when agy could not. For research, verify material claims against cited sources. Report observed checks separately from claimed or untested behavior.
- Resume with saved `conversation_id` using `--conversation ID`, the same cwd, a follow-up prompt file, and a fresh output directory. Recover cwd from `request.json` if needed. Prefer a bounded corrective follow-up over repeating implementation blindly. Never use `--continue` in orchestration: another run may have become the most recent conversation.
- On timeout/interruption, inspect existing changes and artifacts before retrying. The helper attempts process-tree termination; if cleanup is reported unverified, resolve any remaining task processes before retrying. Partial work may remain. Stop retries when the failure needs user input or an external change.

Keep permission handling scoped. Do not add `--dangerously-skip-permissions`, weaken global settings, or use agy to perform an action Codex was denied. If agy cannot run a shell check, Codex can run that already-authorized check through its own tools. Separate commits, pushes, publication, or external messages need authorization from the user task.

Finish with the actual outcome, evidence, checks run, and remaining limitations. Review agy's work before forwarding its success claim.
