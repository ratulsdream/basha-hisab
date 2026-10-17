"""Compare a Console/admin-exported deployed rules file with tested repository rules.
No authentication, deployment, or production data access is performed.
"""
import argparse
import difflib
import hashlib
from pathlib import Path
import re


def audit(repository: str, deployed: str) -> dict:
    broad = re.compile(r'allow\s+(?:read\s*,\s*write|write\s*,\s*read)\s*:\s*if\s+request\.auth\s*!=\s*null\s*;', re.S)
    return {
        'repository_sha256': hashlib.sha256(repository.encode()).hexdigest(),
        'deployed_sha256': hashlib.sha256(deployed.encode()).hexdigest(),
        'exact_match': repository == deployed,
        'broad_authenticated_access_detected': bool(broad.search(deployed)),
    }


if __name__ == '__main__':
    import json
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deployed-rules', type=Path, required=True)
    args = parser.parse_args()
    repository = (Path(__file__).resolve().parents[2] / 'firestore.rules').read_text()
    deployed = args.deployed_rules.read_text()
    result = audit(repository, deployed)
    print(json.dumps(result, indent=2))
    if not result['exact_match']:
        print(''.join(difflib.unified_diff(repository.splitlines(True), deployed.splitlines(True), fromfile='tested-repository', tofile='deployed')))
    raise SystemExit(0 if result['exact_match'] and not result['broad_authenticated_access_detected'] else 1)
