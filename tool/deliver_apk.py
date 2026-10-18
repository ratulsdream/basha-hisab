"""Publish an already-built verified APK without changing the working checkout.

A temporary Git index makes an isolated delivery commit; no worktree or source
checkout is created. The workflow verifies APK digests and records a download URL.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apk', type=Path, required=True)
names = parser.add_mutually_exclusive_group(required=True)
names.add_argument('--phase', choices=['0', '1', '2', '3'])
names.add_argument('--name', help='BashaHisab-v3.1-dashboard-debug.apk')
parser.add_argument('--dry-run', action='store_true', help='Create/review the local delivery commit without pushing.')
args = parser.parse_args()
name = args.name or f'BashaHisab-v3-phase-{args.phase}-debug.apk'
if not re.fullmatch(r'BashaHisab-(?:v3-phase-[0-3]|v3\.1-dashboard)-debug\.apk', name):
    parser.error('Choose a supported verified APK name.')
if not args.apk.is_file():
    parser.error('The already-built APK file is missing.')
repository = Path(__file__).resolve().parents[1]

def git(*arguments, data=None, environment=None):
    return subprocess.check_output(['git', *arguments], cwd=repository, input=data,
        env=environment).decode().strip()

source = git('rev-parse', 'HEAD')
if not args.dry_run and git('ls-remote', 'origin', 'refs/heads/delivery/v2-apk'):
    raise SystemExit('A previous delivery branch exists. Verify its artifact before publishing a new delivery; do not force-push it.')
manifest = {'name': name, 'source_commit': source, 'bytes': args.apk.stat().st_size, 'sha256': '', 'parts': []}
digest = hashlib.sha256()
with tempfile.TemporaryDirectory(prefix='bashahisab-apk-index-') as folder:
    environment = {**os.environ, 'GIT_INDEX_FILE': str(Path(folder) / 'index')}
    git('read-tree', source, environment=environment)
    def add(path, data):
        blob = git('hash-object', '-w', '--stdin', data=data)
        git('update-index', '--add', '--cacheinfo', '100644', blob, path, environment=environment)
    with args.apk.open('rb') as stream:
        index = 0
        while data := stream.read(48 * 1024 * 1024):
            part = f'debug.part-{index:03}'
            digest.update(data)
            manifest['parts'].append({'name': part, 'sha256': hashlib.sha256(data).hexdigest()})
            add('.v2-apk-delivery/' + part, data)
            index += 1
    manifest['sha256'] = digest.hexdigest()
    add('.v2-apk-delivery/manifest.json', (json.dumps(manifest, indent=2) + '\n').encode())
    tree = git('write-tree', environment=environment)
    message = '[deliver-v2] Deliver dashboard APK' if 'dashboard' in name else f'[deliver-v2] Deliver tested v3 Phase {args.phase} APK'
    commit = git('commit-tree', tree, '-p', source, '-m', message)
if not args.dry_run:
    subprocess.run(['git', 'push', 'origin', f'{commit}:refs/heads/delivery/v2-apk'], cwd=repository, check=True)
print(json.dumps({'delivery_commit': commit, 'source': source, 'sha256': manifest['sha256'], 'name': name, 'pushed': not args.dry_run}))
