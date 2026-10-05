"""Stop only the API process belonging to this installation and port."""
import argparse
import pathlib
import psutil
import requests

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=8000)
parser.add_argument('--force', action='store_true')
args = parser.parse_args()
if not 1024 <= args.port <= 65535:
    raise SystemExit('Invalid API port')
pid_file = ROOT / 'deployment' / f'api-{args.port}.pid'
if not pid_file.exists():
    raise SystemExit('No API PID file; no process was stopped')
pid = int(pid_file.read_text(encoding='utf-8-sig').strip())
try:
    process = psutil.Process(pid)
    command = process.cmdline()
    expected = ['--port', str(args.port)]
    if pathlib.Path(process.cwd()).resolve() != ROOT or 'app:app' not in command or not any(command[i:i+2] == expected for i in range(len(command)-1)):
        raise SystemExit('PID does not belong to this API installation/port; no process was stopped')
    if not args.force:
        try:
            response = requests.get(f'http://127.0.0.1:{args.port}/health', timeout=5)
            health = response.json()
            if health.get('service') != 'pixal3d-api-v2':
                raise SystemExit('Port does not identify this API; no process was stopped')
            if health.get('active') or health.get('queued'):
                raise SystemExit('API has unfinished jobs. Wait or use -Force to resume recorded prompts after restart.')
        except requests.RequestException:
            # An unresponsive API still has persisted jobs; require explicit force.
            raise SystemExit('API health is unavailable. Inspect it or use -Force.')
    children = process.children(recursive=True)
    for child in reversed(children):
        try:
            child.terminate()
        except psutil.NoSuchProcess:
            pass
    process.terminate()
    _, alive = psutil.wait_procs([process, *children], timeout=10)
    for item in alive:
        item.kill()
    pid_file.unlink(missing_ok=True)
    print(f'Stopped API {args.port} (PID {pid}); ComfyUI remains running')
except psutil.NoSuchProcess:
    pid_file.unlink(missing_ok=True)
    print('API is already stopped')
