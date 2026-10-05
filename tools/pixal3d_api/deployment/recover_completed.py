"""After stopping the API, reconcile a failed job with an already completed prompt.

No uploads or GPU submission. Normal worker artifact checks still apply.
"""
import argparse
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from service import JobService

parser = argparse.ArgumentParser()
parser.add_argument('job_id')
args = parser.parse_args()
if any((ROOT / 'deployment').glob('api-*.pid')):
    raise SystemExit('Stop API instances with stop.ps1 before reconciling job files')
service = JobService(ROOT)
job = service.snapshot(args.job_id)
if job['state'] != 'failed' or not job.get('prompt_id'):
    raise SystemExit('Only a failed V2 job with a saved prompt can be reconciled')
history = service.backend.history(job['prompt_id'])
status = (history or {}).get('status', {})
if status.get('status_str') != 'success' or not status.get('completed'):
    raise SystemExit('Existing ComfyUI prompt has not completed successfully; no job change')
service._update(args.job_id, state='running', error=None, finished_at=None,
                recovery={'at': time.time(), 'previous_error': job.get('error'), 'same_prompt_id': job['prompt_id']})
print('Reconcile existing prompt on next API startup:', job['prompt_id'])
