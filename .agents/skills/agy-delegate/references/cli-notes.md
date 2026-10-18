# CLI notes and sources

Researched 2026-10-04. Installed `agy.exe` reported language-server version 1.2.5 at startup; flags were checked with `agy --help`. Recheck help after upgrades. This is a local CLI workflow, not an MCP integration.

## Official sources

- [Headless mode](https://antigravity.google/docs/cli/headless/): print/streamed stdin, envelopes, status, and resumption.
- [Execution modes](https://antigravity.google/docs/cli/modes/): planning and file-edit behavior; shell permissions remain separate.
- [Permissions](https://antigravity.google/docs/permissions?tab=cli): rules and platform differences.
- [Terminal sandbox](https://antigravity.google/docs/sandbox?tab=cli): command isolation and platform-specific behavior.
- [Installation and authentication](https://antigravity.google/docs/cli/install/): cached sign-in and installation paths.
- [Conversations](https://antigravity.google/docs/cli/conversations/): history and the limits of conversation forks.
- [Projects](https://antigravity.google/docs/projects?tab=cli): optional project selection, distinct from cwd.
- [OpenAI skills](https://learn.chatgpt.com/docs/build-skills): manifest, resources, and discovery.

## Flags and parsing

`--print` / `-p` executes one prompt. JSON output has `conversation_id`, `status`, and `response`; failures may have `error`. Stream output uses `init`, `step_update`, and `result` events, with the final envelope in `result`. Init reports cwd.

For stdin streaming, pair `--input-format stream-json` with `--output-format stream-json`; send a `user` event containing `message.content`. Do not also pass `--print`. Close stdin after the single prompt. Persistent drivers wait for each result before another turn; this helper starts one process per turn and resumes explicitly.

`--json-schema` accepts a schema file; read `structured_output`. Keep stdout/stderr separate. Discover model IDs locally.

## Local observations

On 2026-10-04, `agy models` listed Gemini 3.8 Flash High/Medium/Low as `gemini-3.8-flash-high`, `gemini-3.8-flash-medium`, and `gemini-3.8-flash-low`. The user selected 3.8, replacing the earlier unavailable Sonnet 5.5 preference. The skill and helper default to `gemini-3.8-flash-high`; explicit model/effort requests take precedence. Re-query availability before dispatch and do not substitute another model without a user choice.

Installed help exposes `--disable-slash-commands` and `--log-file`. A real run warned: `--mode plan has no effect while slash command expansion is disabled`. The helper disables expansion only in accept-edits mode, preserving planning behavior. Default CLI log configuration is retained; stdout/stderr are captured separately.

Validation on this Windows installation: real file read, file write with Chinese and shell-literal text, explicit conversation resumption, invalid-model failure, and one-second timeout all passed. Independent mocked checks rejected wrong resumed IDs and missing responses, and reported failed process-tree cleanup. Skill manifest validation passed. No claim is made about untested platform isolation or optional schema/model/agent overrides.

## Permission implications

Headless tools can be soft-denied while the response succeeds. Inspect logs and deliverables. File-edit mode and terminal permission are separate controls.

Global configuration is `~/.gemini/antigravity-cli/settings.json`. Rules use `action(target)` in allow/ask/deny lists; Deny outranks Ask, which outranks Allow. Broad Ask rules can override narrow Allow rules. Do not modify these settings merely to make a handoff work.

Windows permission/sandbox behavior differs from macOS/Linux. `--sandbox` does not prove every tool is contained. Codex escalation lets the outer CLI use normal state, keyring, and network; it does not expand the delegated task's scope.

## Project-local validation (2026-10-14)

Moved the complete skill from the user's global `.agents/skills/agy-delegate` directory into ApocalypseRV's `.agents/skills/agy-delegate`; the global source directory is absent. Bundled relative links still resolve.

Current `agy models` returned Gemini 3.8 Flash High/Medium/Low, Claude Sonnet 4.6, Claude Opus 4.6 Thinking, and GPT-OSS 120B Medium. The existing default `gemini-3.8-flash-high` remains available. This is an account-specific availability check, not a claim about every publicly released model.

The relocated helper completed a tool-free synthetic test in an empty temporary workspace with explicit model `gemini-3.8-flash-high`. Init confirmed the requested model and cwd; the helper reported `SUCCESS`, exit 0, matching conversation IDs, and zero malformed events. Independent checks verified Traditional Chinese and shell-literal echoes, arithmetic, stable deduplication, and a Python truthiness correction. Event step types were only `user_input` and `agent_response`; no tool calls occurred. Run artifacts are retained under the gitignored `.godot/agy-model-test-20261014/` directory.

Codex automatic approval review rejected a proposed external read of the skill files because model testing did not authorize disclosure of repository contents. The replacement test used only synthetic prompt data. Repository file reads, writes, and conversation resumption were not tested in this run; the earlier validation above remains historical.
