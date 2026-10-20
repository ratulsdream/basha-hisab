"""Publish the one owner-approved BashaHisab policy using Cloud Shell sign-in.

Default is preflight only. A mutation requires the explicit approved SHA argument.
Only Firebase Rules API calls are allowed; no database, index, IAM, Storage or
Functions APIs. Credentials are held in memory and never included in evidence.
"""
import argparse
import hashlib
import http.client
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import zipfile


PROJECT = 'bashahisab-a6dd6'
RELEASE = f'projects/{PROJECT}/releases/cloud.firestore'
RULESETS = f'projects/{PROJECT}/rulesets'
APPROVED_SHA = 'c0ece12ebca45c856fb3d053be07ab10a96be3ce6389cbae7dc035167e35d579'
BASELINE_SHA = '8f92d9c6e9fdb9ff292ec3e803b266e7e87859f0d2e1deb15ae99052eb053a7d'
BASELINE_RULESET = f'{RULESETS}/69a9477e-5c94-4c44-a0c0-d5abc2c26759'
BASELINE_UPDATED = '2026-10-16T08:37:42.586308Z'
SOURCE_COMMIT = '7c6ffd859c2cf8a1592d832d1eb5bb67cbb76470'
SOURCE_URL = f'https://raw.githubusercontent.com/ratulsdream/basha-hisab/{SOURCE_COMMIT}/firestore.rules'
ARCHIVE = 'BashaHisab-deployment-verification.zip'


class Stop(RuntimeError):
    """A failed guard or uncertain remote operation; never retry a mutation."""


def sha(source):
    return hashlib.sha256(source.encode('utf-8')).hexdigest()


def ruleset_name(value):
    return isinstance(value, str) and re.fullmatch(
        re.escape(RULESETS) + r'/[A-Za-z0-9_-]+', value) is not None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward an Authorization header to a redirected destination.
        return None


class RulesApi:
    def __init__(self, token):
        self._token = token
        self._opener = urllib.request.build_opener(NoRedirect())

    def call(self, method, resource, payload=None):
        allowed = (
            method == 'GET' and (resource == RELEASE or ruleset_name(resource))
            or method == 'POST' and resource == RULESETS
            or method == 'PATCH' and resource == RELEASE
        )
        if not allowed:
            raise Stop('Refusing an API operation outside the approved rules scope.')
        request = urllib.request.Request(
            'https://firebaserules.googleapis.com/v1/' + resource,
            data=None if payload is None else json.dumps(payload).encode('utf-8'),
            headers={'Authorization': 'Bearer ' + self._token,
                     'Content-Type': 'application/json'}, method=method)
        try:
            with self._opener.open(request, timeout=45) as response:
                result = json.load(response)
            if not isinstance(result, dict):
                raise Stop(f'Firebase Rules {method} returned an unexpected response. No automatic retry was made.')
            return result
        except urllib.error.HTTPError as error:
            raise Stop(f'Firebase Rules {method} returned HTTP {error.code}. No automatic retry was made.') from None
        except (urllib.error.URLError, TimeoutError, OSError, ValueError, http.client.HTTPException):
            raise Stop(f'Firebase Rules {method} did not return a usable response. No automatic retry was made.') from None


def sign_in_token():
    if shutil.which('gcloud') is None:
        raise Stop('Run this helper in your signed-in Google Cloud Shell.')
    result = subprocess.run(['gcloud', 'auth', 'print-access-token', '--quiet'],
                            capture_output=True, text=True, timeout=60)
    if result.returncode or not result.stdout.strip():
        raise Stop('Google sign-in is unavailable. Authorize Cloud Shell through Google; do not share tokens.')
    return result.stdout.strip()


def candidate_source():
    try:
        with urllib.request.urlopen(SOURCE_URL, timeout=30) as response:
            source = response.read(300000).decode('utf-8')
    except (urllib.error.URLError, TimeoutError, OSError, ValueError, http.client.HTTPException):
        raise Stop('Cannot download the pinned reviewed rules. No deployment was attempted.') from None
    if sha(source) != APPROVED_SHA:
        raise Stop('The downloaded rules do not match the approved SHA-256. No deployment was attempted.')
    return source


def checked_release(api):
    release = api.call('GET', RELEASE)
    if (release.get('name') != RELEASE or not ruleset_name(release.get('rulesetName'))
            or not isinstance(release.get('updateTime'), str)):
        raise Stop('Unexpected release identity or version. Stopping without publication.')
    return release


def version(release):
    return release['name'], release['rulesetName'], release['updateTime']


def source_for_ruleset(api, name):
    ruleset = api.call('GET', name)
    source = ruleset.get('source')
    files = source.get('files') if isinstance(source, dict) else None
    if (ruleset.get('name') != name or not isinstance(files, list) or len(files) != 1
            or not isinstance(files[0], dict)
            or files[0].get('name') != 'firestore.rules'
            or not isinstance(files[0].get('content'), str)):
        raise Stop('Unexpected ruleset source; complete manual review is required.')
    return files[0]['content']


def snapshot(api):
    release = checked_release(api)
    source = source_for_ruleset(api, release['rulesetName'])
    if version(checked_release(api)) != version(release):
        raise Stop('Live rules changed during export. Stop and ask for another review.')
    metadata = {'project': PROJECT, 'release': release['name'],
                'ruleset': release['rulesetName'],
                'release_updated_at': release['updateTime'],
                'sha256': sha(source), 'source_file': 'firestore.rules'}
    return source, metadata


def baseline(metadata):
    return (metadata['project'] == PROJECT and metadata['release'] == RELEASE
            and metadata['ruleset'] == BASELINE_RULESET
            and metadata['release_updated_at'] == BASELINE_UPDATED
            and metadata['sha256'] == BASELINE_SHA)


def save_snapshot(folder, label, source, metadata):
    # Exclusive writes preserve every prior backup, even on a repeated run.
    with (folder / f'{label}.rules').open('x', encoding='utf-8', newline='') as stream:
        stream.write(source)
    with (folder / f'{label}.metadata.json').open('x', encoding='utf-8') as stream:
        json.dump(metadata, stream, indent=2)


def publish(api, source, folder, approved_sha, report):
    if sha(source) != APPROVED_SHA or approved_sha not in (None, APPROVED_SHA):
        raise Stop('Candidate or authorization hash differs from the reviewed policy.')
    before_source, before = snapshot(api)
    save_snapshot(folder, 'before', before_source, before)
    report['before'] = before
    if not baseline(before):
        raise Stop('Live rules differ from the reviewed export. STOP: ask the owner before changing anything.')
    if approved_sha is None:
        report['status'] = 'PREFLIGHT_MATCH_NO_DEPLOYMENT'
        return

    report['stage'] = 'create_immutable_ruleset'
    created = api.call('POST', RULESETS, {
        'source': {'files': [{'name': 'firestore.rules', 'content': source}]}})
    created_name = created.get('name')
    if not ruleset_name(created_name) or created_name == BASELINE_RULESET:
        raise Stop('Unexpected created ruleset identity. Nothing was published by this helper.')
    report['created_ruleset'] = created_name
    if sha(source_for_ruleset(api, created_name)) != APPROVED_SHA:
        raise Stop('The staged ruleset does not match the approved hash. No release update was sent.')

    # Re-export immediately before the one publish request. A staged ruleset
    # never changes live permissions. The API has no conditional-update/etag.
    report['stage'] = 'recheck_before_publish'
    recheck_source, recheck = snapshot(api)
    save_snapshot(folder, 'recheck', recheck_source, recheck)
    if not baseline(recheck):
        raise Stop('Live rules changed before publication. STOP: ask the owner; no release update was sent.')

    report['stage'] = 'publish_request'
    publish_error = None
    try:
        api.call('PATCH', RELEASE, {'release': {'name': RELEASE,
                 'rulesetName': created_name}, 'updateMask': 'rulesetName'})
    except Stop as error:
        # A lost response may still mean the server committed the request.
        # Never retry or automatically roll back; inspect live state instead.
        publish_error = str(error)
        report['publication_response_warning'] = publish_error

    report['stage'] = 'verify_published_source'
    after_source, after = snapshot(api)
    save_snapshot(folder, 'after', after_source, after)
    report['after'] = after
    if after['sha256'] != APPROVED_SHA or after['ruleset'] != created_name:
        raise Stop('Post-deployment verification did not match. Keep app features closed; send the evidence ZIP. Do not rerun.')
    report['stage'] = 'complete'
    report['status'] = 'VERIFIED'


def finish(folder, report):
    with (folder / 'result.json').open('x', encoding='utf-8') as stream:
        json.dump(report, stream, indent=2)
    # Fixed allowlist: no scripts, auth files, environment or unrelated files.
    names = ['result.json'] + [f'{label}{suffix}'
        for label in ('before', 'recheck', 'after')
        for suffix in ('.rules', '.metadata.json')]
    with zipfile.ZipFile(folder / ARCHIVE, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for name in names:
            if (folder / name).is_file():
                archive.write(folder / name, arcname=name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--deploy-approved-sha256')
    args = parser.parse_args()
    folder = args.output_dir
    folder.mkdir(parents=True, exist_ok=True)
    reserved = ['result.json', ARCHIVE] + [f'{label}{suffix}'
        for label in ('before', 'recheck', 'after')
        for suffix in ('.rules', '.metadata.json')]
    if any((folder / name).exists() for name in reserved):
        print('Existing evidence found. Use a new output directory; no files or rules were changed.', file=sys.stderr)
        return 2
    report = {'project': PROJECT, 'approved_sha256': APPROVED_SHA,
              'baseline_sha256': BASELINE_SHA, 'source_commit': SOURCE_COMMIT,
              'status': 'STOPPED', 'stage': 'preflight'}
    try:
        if args.deploy_approved_sha256 not in (None, APPROVED_SHA):
            raise Stop('The authorization hash differs from the approved policy.')
        source = candidate_source()
        api = RulesApi(sign_in_token())
        publish(api, source, folder, args.deploy_approved_sha256, report)
    except (Stop, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        # Subprocess failures may contain captured credential stdout: never
        # stringify those exceptions or dump tracebacks in shareable evidence.
        report['reason'] = str(error) if isinstance(error, Stop) else 'Local preparation or response processing failed. Stop and send the evidence ZIP.'
    finish(folder, report)
    print(report['status'])
    if report.get('reason'):
        print(report['reason'])
    if report['status'] == 'VERIFIED':
        print('Published source SHA-256:', report['after']['sha256'])
    print('Backup and verification evidence:', folder / ARCHIVE)
    return 0 if report['status'] in ('VERIFIED', 'PREFLIGHT_MATCH_NO_DEPLOYMENT') else 2


if __name__ == '__main__':
    raise SystemExit(main())
