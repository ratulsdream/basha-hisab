"""Publish an existing verified APK through the repository delivery workflow.
Only creates a temporary delivery branch; never rebuilds or deploys Firebase.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apk', type=Path, required=True)
parser.add_argument('--phase', choices=['0', '1', '2', '3'], required=True)
args = parser.parse_args()
repository = Path(__file__).resolve().parents[1]
source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repository, text=True).strip()
branch = f'delivery/phase-{args.phase}-{source[:8]}'
checkout = Path(tempfile.mkdtemp(prefix='bashahisab-delivery-')) / 'checkout'
subprocess.run(['git', 'worktree', 'add', '-b', branch, str(checkout), source], cwd=repository, check=True)
packet = checkout / '.v2-apk-delivery'
packet.mkdir()
manifest = {'name': f'BashaHisab-v3-phase-{args.phase}-debug.apk', 'source_commit': source,
            'bytes': args.apk.stat().st_size, 'sha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(), 'parts': []}
with args.apk.open('rb') as stream:
    index = 0
    while data := stream.read(48 * 1024 * 1024):
        name = f'debug.part-{index:03}'
        (packet / name).write_bytes(data)
        manifest['parts'].append({'name': name, 'sha256': hashlib.sha256(data).hexdigest()})
        index += 1
(packet / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
subprocess.run(['git', 'add', '.v2-apk-delivery'], cwd=checkout, check=True)
subprocess.run(['git', 'commit', '-m', f'[deliver-v2] Deliver tested v3 Phase {args.phase} APK'], cwd=checkout, check=True)
subprocess.run(['git', 'push', 'origin', 'HEAD:delivery/v2-apk'], cwd=checkout, check=True)
print(json.dumps({'checkout': str(checkout), 'branch': branch, 'source': source, 'sha256': manifest['sha256']}))
