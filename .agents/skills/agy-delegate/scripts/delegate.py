#!/usr/bin/env python3
"""Run one agy turn with UTF-8 stdin, retained events, and explicit resumption."""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def stop_tree(proc):
    cleanup_error = None
    if os.name == "nt":
        try:
            killed = subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                    timeout=15, check=False)
            if killed.returncode != 0:
                cleanup_error = f"Process-tree cleanup unverified (taskkill exit {killed.returncode})"
        except (OSError, subprocess.SubprocessError) as exc:
            cleanup_error = f"Process-tree cleanup unverified: {exc}"
    else:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if proc.poll() is None:
        proc.kill()
    proc.wait(timeout=15)
    if cleanup_error:
        raise RuntimeError(cleanup_error)


def collect_events(path):
    results, working_dirs, init_ids, malformed = [], [], [], 0
    with path.open(encoding="utf-8-sig", errors="replace") as stream:
        for line in stream:
            if not line.strip():
                continue
            try:
                event = json.loads(line)
                if not isinstance(event, dict):
                    raise ValueError("Event must be an object")
                if event.get("event") == "result":
                    result = event.get("result")
                    if not isinstance(result, dict):
                        raise ValueError("Result must be an object")
                    results.append(result)
                elif event.get("event") == "init":
                    working_dirs.append(event.get("init", {}).get("cwd"))
                    init_ids.append(event.get("conversation_id"))
            except (ValueError, TypeError, AttributeError):
                malformed += 1
    return results, working_dirs, init_ids, malformed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workdir", required=True, type=Path)
    parser.add_argument("--prompt-file", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--mode", choices=("plan", "accept-edits"), default="plan")
    parser.add_argument("--timeout", type=int, default=600, help="Whole-run ceiling in seconds")
    parser.add_argument("--conversation", help="Explicit saved agy conversation ID")
    parser.add_argument("--model", default="gemini-3.8-flash-high",
                        help="agy model ID (default: gemini-3.8-flash-high)")
    parser.add_argument("--agent")
    parser.add_argument("--effort", choices=("low", "medium", "high"))
    parser.add_argument("--schema-file", type=Path)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    try:
        cwd = args.workdir.resolve(strict=True)
        if not cwd.is_dir():
            raise ValueError("--workdir must be a directory")
        prompt = args.prompt_file.read_text(encoding="utf-8-sig")
        if not prompt.strip():
            raise ValueError("Prompt file is empty")
        schema = args.schema_file.resolve(strict=True) if args.schema_file else None
        if schema:
            json.loads(schema.read_text(encoding="utf-8-sig"))
        binary = shutil.which("agy")
        if not binary:
            raise ValueError("agy is not on PATH")
        if os.name == "nt" and Path(binary).suffix.lower() != ".exe":
            raise ValueError("On Windows resolve native agy.exe, not a shell wrapper")
        output = args.output_dir.resolve()
        output.mkdir(parents=True, exist_ok=False)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))

    command = [binary, "--input-format", "stream-json", "--output-format", "stream-json",
               "--mode", args.mode, "--sandbox", "--print-timeout", f"{args.timeout}s"]
    if args.mode == "accept-edits":
        command.append("--disable-slash-commands")
    for flag, value in (("--conversation", args.conversation), ("--model", args.model),
                        ("--agent", args.agent), ("--effort", args.effort),
                        ("--json-schema", str(schema) if schema else None)):
        if value:
            command.extend((flag, value))
    write_json(output / "request.json", {"cwd": str(cwd), "command": command,
               "prompt_source": str(args.prompt_file.resolve()), "timeout_seconds": args.timeout})
    (output / "prompt.txt").write_text(prompt, encoding="utf-8")

    started = time.monotonic()
    proc, error, timed_out, interrupted = None, None, False, False
    with (output / "events.ndjson").open("wb") as stdout, (output / "stderr.log").open("wb") as stderr:
        try:
            proc = subprocess.Popen(command, cwd=cwd, stdin=subprocess.PIPE,
                                    stdout=stdout, stderr=stderr, start_new_session=(os.name != "nt"))
            payload = json.dumps({"event": "user", "message": {"content": prompt}},
                                 ensure_ascii=False).encode("utf-8") + b"\n"
            proc.communicate(payload, timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            error = "Whole-run timeout; inspect partial changes before retrying"
        except KeyboardInterrupt:
            interrupted = True
            error = "Interrupted; inspect partial changes before retrying"
        except OSError as exc:
            error = str(exc)
        finally:
            if proc is not None and (timed_out or interrupted or proc.poll() is None):
                try:
                    stop_tree(proc)
                except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
                    error = f"{error or 'Failed to stop process'}; cleanup: {exc}"

    results, working_dirs, init_ids, malformed = collect_events(output / "events.ndjson")
    result = results[-1] if results else None
    write_json(output / "result.json", result)
    response = result.get("response", "") if result else ""
    (output / "response.txt").write_text(response if isinstance(response, str) else "", encoding="utf-8")
    cwd_matches = bool(working_dirs) and all(
        isinstance(value, str) and os.path.normcase(os.path.abspath(value)) == os.path.normcase(str(cwd))
        for value in working_dirs
    )
    conversation_id = result.get("conversation_id") if result else None
    conversation_matches = (isinstance(conversation_id, str) and bool(conversation_id.strip())
                            and len(init_ids) == 1 and init_ids[0] == conversation_id
                            and (not args.conversation or conversation_id == args.conversation))
    protocol_errors = []
    if len(results) != 1:
        protocol_errors.append(f"Expected one terminal result, got {len(results)}")
    if malformed:
        protocol_errors.append(f"Malformed events: {malformed}")
    if not cwd_matches:
        protocol_errors.append("Missing or mismatched init cwd")
    if not conversation_matches:
        protocol_errors.append("Missing or mismatched conversation ID")
    if not result or not isinstance(result.get("response"), str):
        protocol_errors.append("Missing or non-string response")
    success = (not error and not protocol_errors and proc is not None
               and proc.returncode == 0 and result.get("status") == "SUCCESS")
    report = {"transport_success": bool(success), "returncode": proc.returncode if proc else None,
              "status": result.get("status") if result else None,
              "conversation_id": conversation_id, "conversation_matches": bool(conversation_matches),
              "cwd_matches": cwd_matches, "timed_out": timed_out, "interrupted": interrupted,
              "result_count": len(results), "malformed_event_count": malformed,
              "protocol_errors": protocol_errors,
              "duration_seconds": round(time.monotonic() - started, 2),
              "error": error or (result.get("error") if result else "No terminal result"),
              "output_dir": str(output), "response_file": str(output / "response.txt"),
              "result_file": str(output / "result.json"), "stderr_file": str(output / "stderr.log")}
    write_json(output / "report.json", report)
    print(json.dumps(report, ensure_ascii=True))
    return 0 if success else (124 if timed_out else 130 if interrupted else 1)


if __name__ == "__main__":
    sys.exit(main())
