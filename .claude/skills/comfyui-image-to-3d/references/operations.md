# Operations

Run everything from the repository root with the `$skill`, `$py` and `$work` variables from [SKILL.md](../SKILL.md#setup).

## Start the service

If `preflight` is refused, check whether the service is running. When the user has asked for generation, start it with the existing local launcher (no reinstall, no weight downloads):

```powershell
& "$env:USERPROFILE/Apps/Pixal3D-API-v2/start.ps1"
```

It starts ComfyUI (8188) and the API (8000) in the background and returns immediately if they already run. Wait until `/health` reports `backend.available=true`, then run preflight. If it is still not ready after about two minutes, read `deployment/comfy.stderr.log` and `deployment/api-8000.stderr.log` next to the launcher. If the API is up but the backend is down, investigate the backend; do not keep restarting the shared service. On another machine use whatever launcher is installed; with plain ComfyUI only, add `--backend http://127.0.0.1:8188` to preflight/submit/run.

## Step-by-step commands

```powershell
$job = "$work/generation"
& $py "$skill/scripts/generate.py" preflight                        # nodes, weights, idle queue
& $py "$skill/scripts/generate.py" submit --image '<ref.png>' --asset-id '<asset>' --output $job
& $py "$skill/scripts/generate.py" status --output $job             # check once
& $py "$skill/scripts/generate.py" wait --output $job --timeout 900  # poll until done, then collect
& $py "$skill/scripts/generate.py" collect --output $job            # collect once
& $py "$skill/scripts/generate.py" inspect --glb "$job/raw.glb"      # GLB technical check only
```

Run `run` and `wait` with `run_in_background`; they can outlast the tool timeout.

| Exit | Meaning |
|---|---|
| 0 | Done (`READY`, `SUBMITTED`, `ART_REVIEW_REQUIRED`, …) |
| 1 | `STOPPED`; read `error` |
| 2 | Backend does not know this prompt (`UNKNOWN`) |
| 3 | Still `RUNNING` / `QUEUED` |

Guarantees:

- `submit`/`run` check that both the API and the ComfyUI queue are idle, and POST at most once per output folder. There is no cross-process lock, so never submit in parallel.
- `status`/`wait`/`collect`/`reconcile` only read the backend and are safe to repeat. Collection verifies the saved reference, graph and client ID; identical files (same SHA) are reused, and a mismatch stops without touching the old files.
- The scripts never start or stop services, download weights or edit the graph; `inspect` never modifies files. Topology (duplicate faces, non-manifold edges) is not checked here.

## Unknown submission

On `SUBMISSION_INTENT` / `SUBMISSION_UNKNOWN` (for example a POST timeout): **do not delete the folder and do not resubmit.** Query the same backend's `/queue` or `/history?max_items=100`, find the prompt ID matching `client_id` in `job.json` and `prompt.json`, then:

```powershell
& $py "$skill/scripts/generate.py" reconcile --output $job --prompt-id '<prompt-id>'
& $py "$skill/scripts/generate.py" wait --output $job
```

`reconcile` verifies the graph and client ID and never submits new work. If no match exists, leave the job `UNKNOWN` and tell the user. `NOT_SUBMITTED` (failure after upload, before POST) also stops the batch and gets reported.

## Environment problems

- If `python` on PATH is the Windows Store stub, use the full `$py` path.
- Missing Pillow/numpy and no venv: `python -m pip install --target "$work/deps/python" Pillow numpy`, then set `$env:PYTHONPATH = "$work/deps/python"` in the same command.
- If the Windows temp directory refuses writes, point this process's `TEMP`/`TMP` at an ignored folder under `.godot/` before running tests or reviews.
- Godot not on PATH: `review.py --godot 'C:/Program Files/godot/godot.exe'`.
