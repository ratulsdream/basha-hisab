"""Read-only Firebase Rules export using an existing gcloud sign-in.

Never deploys rules or reads Firestore documents. Credentials stay in the
subprocess/HTTPS Authorization header, never logs or the exported metadata.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request


def export(project, output):
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,62}', project):
        raise ValueError('Use the Firebase project ID, not its display name.')
    if shutil.which('gcloud') is None:
        raise RuntimeError('No gcloud sign-in tool is available. Export the published rules from Firebase Console; see docs/v3/SECURITY_REVIEW_3_1.md.')
    result = subprocess.run(['gcloud', 'auth', 'print-access-token', '--quiet'], capture_output=True, text=True)
    if result.returncode or not result.stdout.strip():
        raise RuntimeError('No usable gcloud credentials. Use an existing account with Firebase Rules Viewer access; do not paste access tokens into chat.')
    token = result.stdout.strip()
    def read(name):
        request = urllib.request.Request('https://firebaserules.googleapis.com/v1/' + name,
            headers={'Authorization': 'Bearer ' + token})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f'Rules export returned HTTP {error.code}. Confirm Firebase Rules Viewer access and API/network availability.') from None
        except urllib.error.URLError:
            raise RuntimeError('Cannot reach the Firebase Rules API. No deployment or data change was attempted.') from None
    release = read(f'projects/{project}/releases/cloud.firestore')
    ruleset_name = release['rulesetName']
    if not ruleset_name.startswith(f'projects/{project}/rulesets/'):
        raise RuntimeError('Unexpected ruleset project; refusing export.')
    ruleset = read(ruleset_name)
    files = ruleset.get('source', {}).get('files', [])
    if len(files) != 1 or not isinstance(files[0].get('content'), str):
        raise RuntimeError('Unexpected multi-file ruleset. Obtain the complete source before comparison.')
    source = files[0]['content']
    # Exclusive writes never replace an earlier export or repository rules.
    if output.exists() or output.with_suffix('.metadata.json').exists():
        raise RuntimeError('Choose a new output path; existing exports are never overwritten.')
    metadata = {'project': project, 'release': release.get('name'), 'ruleset': ruleset_name,
        'release_updated_at': release.get('updateTime'),
        'sha256': hashlib.sha256(source.encode()).hexdigest(), 'source_file': files[0].get('name')}
    with output.open('x') as stream:
        stream.write(source)
    with output.with_suffix('.metadata.json').open('x') as stream:
        json.dump(metadata, stream, indent=2)
    return metadata


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(export(args.project, args.output), indent=2))
    except (RuntimeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(2)
