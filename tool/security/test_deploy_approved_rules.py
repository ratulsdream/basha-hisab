"""Offline tests of the narrowly approved rules publication procedure.

The sources below are synthetic. Every credential, HTTP operation and live
release is mocked; these tests never contact a Firebase project.
"""
import contextlib
import hashlib
import http.client
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.error
import zipfile

import deploy_approved_rules as deploy


BEFORE = 'rules_version = "2"; // synthetic previous policy\n'
APPROVED = 'rules_version = "2"; // synthetic reviewed policy\n'
OTHER = 'rules_version = "2"; // somebody else changed the policy\n'
NEW_RULESET = deploy.RULESETS + '/synthetic-reviewed-version'
TEST_TOKEN = 'test-only-credential-never-export-this'


def digest(source):
    return hashlib.sha256(source.encode('utf-8')).hexdigest()


def release(ruleset=None, updated=None, **changes):
    result = {
        'name': deploy.RELEASE,
        'rulesetName': ruleset or deploy.BASELINE_RULESET,
        'updateTime': updated or deploy.BASELINE_UPDATED,
    }
    result.update(changes)
    return result


def snapshot_calls(source=BEFORE, live=None, final_live=None):
    live = live or release()
    return [
        ('GET', deploy.RELEASE, None, live),
        ('GET', live['rulesetName'], None, {
            'name': live['rulesetName'],
            'source': {'files': [{'name': 'firestore.rules', 'content': source}]},
        }),
        ('GET', deploy.RELEASE, None, final_live or live),
    ]


class ScriptedApi:
    """Enforce the exact ordered API contract, including mutation payloads."""

    def __init__(self, test, expected):
        self.test = test
        self.expected = list(expected)
        self.calls = []

    def call(self, method, resource, payload=None):
        self.calls.append((method, resource, payload))
        self.test.assertTrue(self.expected, 'Unexpected API operation')
        want_method, want_resource, want_payload, response = self.expected.pop(0)
        self.test.assertEqual((method, resource, payload),
                              (want_method, want_resource, want_payload))
        if isinstance(response, BaseException):
            raise response
        return response


class ApprovedPublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.approved_hash = digest(APPROVED)
        self.before_hash = digest(BEFORE)
        for name, value in [('APPROVED_SHA', self.approved_hash),
                            ('BASELINE_SHA', self.before_hash)]:
            patcher = patch.object(deploy, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        # An accidental unmocked network request fails immediately.
        self.network_guard = patch('urllib.request.OpenerDirector.open',
                                   side_effect=AssertionError('Network forbidden in tests'))
        self.network_guard.start()
        self.addCleanup(self.network_guard.stop)

    def api(self, expected):
        return ScriptedApi(self, expected)

    def staged_calls(self):
        return snapshot_calls() + [
            ('POST', deploy.RULESETS, {
                'source': {'files': [{'name': 'firestore.rules', 'content': APPROVED}]},
            }, {'name': NEW_RULESET}),
            ('GET', NEW_RULESET, None, {
                'name': NEW_RULESET,
                'source': {'files': [{'name': 'firestore.rules', 'content': APPROVED}]},
            }),
        ]

    def publication_calls(self, *, after_source=APPROVED, patch_error=None,
                          after_ruleset=NEW_RULESET):
        return self.staged_calls() + snapshot_calls() + [
            ('PATCH', deploy.RELEASE, {
                'release': {'name': deploy.RELEASE, 'rulesetName': NEW_RULESET},
                'updateMask': 'rulesetName',
            }, patch_error or {'name': deploy.RELEASE, 'rulesetName': NEW_RULESET}),
        ] + snapshot_calls(after_source, release(
            ruleset=after_ruleset, updated='2026-10-20T12:00:00Z'))

    def run_main(self, api=None, *, authorization=None, credential_error=None):
        args = ['deploy_approved_rules.py', '--output-dir', str(self.folder)]
        if authorization is not None:
            args += ['--deploy-approved-sha256', authorization]
        output = io.StringIO()
        with patch.object(deploy.sys, 'argv', args), \
                patch.object(deploy, 'candidate_source', return_value=APPROVED) as candidate, \
                patch.object(deploy, 'sign_in_token', return_value=TEST_TOKEN,
                             side_effect=credential_error) as credentials, \
                patch.object(deploy, 'RulesApi', return_value=api) as factory, \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            result = deploy.main()
        return result, output.getvalue(), candidate, credentials, factory

    def test_default_is_read_only_preflight_and_preserves_backup(self):
        api = self.api(snapshot_calls())
        result, _, _, _, _ = self.run_main(api)
        self.assertEqual(result, 0)
        self.assertEqual(api.expected, [])
        self.assertTrue(all(method == 'GET' for method, _, _ in api.calls))
        report = json.loads((self.folder / 'result.json').read_text())
        self.assertEqual(report['status'], 'PREFLIGHT_MATCH_NO_DEPLOYMENT')
        self.assertEqual((self.folder / 'before.rules').read_text(), BEFORE)
        self.assertFalse((self.folder / 'after.rules').exists())

    def test_wrong_candidate_hash_stops_before_any_api_call(self):
        api = self.api([])
        with self.assertRaisesRegex(deploy.Stop, 'Candidate or authorization hash'):
            deploy.publish(api, OTHER, self.folder, self.approved_hash, {})
        self.assertEqual(api.calls, [])

    def test_wrong_authorization_hash_stops_before_download_or_sign_in(self):
        result, _, candidate, credentials, factory = self.run_main(
            authorization='0' * 64)
        self.assertEqual(result, 2)
        candidate.assert_not_called()
        credentials.assert_not_called()
        factory.assert_not_called()

    def test_live_hash_ruleset_or_update_time_change_stops_without_any_mutation(self):
        cases = [
            (OTHER, release()),
            (BEFORE, release(ruleset=deploy.RULESETS + '/unreviewed-version')),
            (BEFORE, release(updated='2026-10-20T12:00:00Z')),
        ]
        for index, (source, live) in enumerate(cases):
            with self.subTest(source=source, live=live):
                folder = self.folder / str(index)
                folder.mkdir()
                api = self.api(snapshot_calls(source, live))
                with self.assertRaisesRegex(deploy.Stop, 'Live rules differ'):
                    deploy.publish(api, APPROVED, folder, self.approved_hash, {})
                self.assertEqual(api.expected, [])
                self.assertTrue(all(method == 'GET' for method, _, _ in api.calls))
                self.assertEqual((folder / 'before.rules').read_text(), source)

    def test_changed_release_during_export_stops_before_mutation(self):
        api = self.api(snapshot_calls(final_live=release(updated='changed')))
        with self.assertRaisesRegex(deploy.Stop, 'changed during export'):
            deploy.publish(api, APPROVED, self.folder, self.approved_hash, {})
        self.assertTrue(all(method == 'GET' for method, _, _ in api.calls))

    def test_invalid_release_identity_cannot_select_another_project_or_service(self):
        invalid_releases = [
            release(name='projects/another-project/releases/cloud.firestore'),
            release(ruleset='projects/another-project/rulesets/source'),
            release(name=deploy.RELEASE.replace('cloud.firestore', 'firebase.storage')),
            release(updateTime=None),
        ]
        for live in invalid_releases:
            with self.subTest(live=live):
                api = self.api([('GET', deploy.RELEASE, None, live)])
                with self.assertRaisesRegex(deploy.Stop, 'Unexpected release identity'):
                    deploy.publish(api, APPROVED, self.folder, self.approved_hash, {})
                self.assertEqual(api.expected, [])

    def test_malformed_ruleset_source_requires_manual_review_before_any_mutation(self):
        for source in [None, {'files': None}, {'files': []}, {'files': [None]},
                       {'files': [{'name': 'storage.rules', 'content': BEFORE}]},
                       {'files': [{'name': 'firestore.rules', 'content': 123}]}]:
            with self.subTest(source=source):
                api = self.api([
                    ('GET', deploy.RELEASE, None, release()),
                    ('GET', deploy.BASELINE_RULESET, None, {
                        'name': deploy.BASELINE_RULESET, 'source': source,
                    }),
                ])
                with self.assertRaisesRegex(deploy.Stop, 'Unexpected ruleset source'):
                    deploy.publish(api, APPROVED, self.folder, self.approved_hash, {})
                self.assertEqual(api.expected, [])

    def test_second_check_change_stops_before_patch_but_keeps_evidence(self):
        api = self.api(self.staged_calls() + snapshot_calls(OTHER))
        with self.assertRaisesRegex(deploy.Stop, 'changed before publication'):
            deploy.publish(api, APPROVED, self.folder, self.approved_hash, {})
        self.assertEqual(api.expected, [])
        self.assertEqual([method for method, _, _ in api.calls if method != 'GET'], ['POST'])
        self.assertEqual((self.folder / 'before.rules').read_text(), BEFORE)
        self.assertEqual((self.folder / 'recheck.rules').read_text(), OTHER)

    def test_corrupted_staged_source_never_reaches_publication(self):
        calls = self.staged_calls()
        calls[-1] = ('GET', NEW_RULESET, None, {
            'name': NEW_RULESET,
            'source': {'files': [{'name': 'firestore.rules', 'content': OTHER}]},
        })
        api = self.api(calls)
        with self.assertRaisesRegex(deploy.Stop, 'staged ruleset|created ruleset|Staged ruleset'):
            deploy.publish(api, APPROVED, self.folder, self.approved_hash, {})
        self.assertEqual(api.expected, [])
        self.assertEqual([method for method, _, _ in api.calls if method != 'GET'], ['POST'])
        self.assertEqual((self.folder / 'before.rules').read_text(), BEFORE)

    def test_failed_creation_is_not_retried_and_keeps_previous_policy_backup(self):
        calls = self.staged_calls()[:-1]
        method, resource, payload, _ = calls[-1]
        calls[-1] = (method, resource, payload, deploy.Stop('POST response lost'))
        api = self.api(calls)
        result, output, _, _, _ = self.run_main(api, authorization=self.approved_hash)
        self.assertEqual(result, 2)
        self.assertIn('POST response lost', output)
        self.assertEqual(api.expected, [])
        self.assertEqual([method for method, _, _ in api.calls if method != 'GET'], ['POST'])
        self.assertEqual((self.folder / 'before.rules').read_text(), BEFORE)

    def test_created_ruleset_outside_project_or_equal_to_baseline_cannot_publish(self):
        for index, created in enumerate([
            'projects/another-project/rulesets/version', deploy.BASELINE_RULESET, None,
        ]):
            with self.subTest(created=created):
                folder = self.folder / str(index)
                folder.mkdir()
                calls = self.staged_calls()[:-1]
                method, resource, payload, _ = calls[-1]
                calls[-1] = (method, resource, payload, {'name': created})
                api = self.api(calls)
                with self.assertRaisesRegex(deploy.Stop, 'Unexpected created ruleset identity'):
                    deploy.publish(api, APPROVED, folder, self.approved_hash, {})
                self.assertEqual(api.expected, [])
                self.assertEqual([method for method, _, _ in api.calls if method != 'GET'], ['POST'])

    def test_success_uses_only_exact_post_patch_payload_and_exports_verified_hash(self):
        api = self.api(self.publication_calls())
        result, output, _, _, factory = self.run_main(api, authorization=self.approved_hash)
        self.assertEqual(result, 0)
        self.assertEqual(api.expected, [])
        factory.assert_called_once_with(TEST_TOKEN)
        self.assertEqual([method for method, _, _ in api.calls if method != 'GET'], ['POST', 'PATCH'])
        report = json.loads((self.folder / 'result.json').read_text())
        self.assertEqual(report['status'], 'VERIFIED')
        self.assertEqual(report['after']['sha256'], self.approved_hash)
        self.assertEqual(report['after']['ruleset'], NEW_RULESET)
        self.assertEqual((self.folder / 'after.rules').read_text(), APPROVED)
        self.assertEqual((self.folder / 'before.rules').read_text(), BEFORE)
        self.assertIn(self.approved_hash, output)

    def test_post_publish_wrong_source_or_ruleset_blocks_activation_without_rollback(self):
        for index, (source, ruleset) in enumerate([
            (OTHER, NEW_RULESET),
            (APPROVED, deploy.RULESETS + '/unexpected-published-version'),
        ]):
            with self.subTest(source=source, ruleset=ruleset):
                folder = self.folder / str(index)
                folder.mkdir()
                api = self.api(self.publication_calls(after_source=source, after_ruleset=ruleset))
                report = {'status': 'STOPPED'}
                with self.assertRaisesRegex(deploy.Stop, 'Post-deployment verification did not match'):
                    deploy.publish(api, APPROVED, folder, self.approved_hash, report)
                self.assertEqual(report['status'], 'STOPPED')
                self.assertEqual(api.expected, [])
                self.assertEqual(sum(method == 'PATCH' for method, _, _ in api.calls), 1)
                self.assertEqual((folder / 'after.rules').read_text(), source)

    def test_uncertain_patch_is_not_retried_and_reads_confirm_committed_policy(self):
        api = self.api(self.publication_calls(patch_error=deploy.Stop('PATCH response lost')))
        result, _, _, _, _ = self.run_main(api, authorization=self.approved_hash)
        self.assertEqual(result, 0)
        report = json.loads((self.folder / 'result.json').read_text())
        self.assertEqual(report['status'], 'VERIFIED')
        self.assertIn('PATCH response lost', report['publication_response_warning'])
        patch_index = next(i for i, call in enumerate(api.calls) if call[0] == 'PATCH')
        self.assertTrue(all(method == 'GET' for method, _, _ in api.calls[patch_index + 1:]))
        self.assertEqual(api.expected, [])

    def test_uncertain_patch_stops_if_old_policy_is_still_live_without_retry(self):
        api = self.api(self.publication_calls(
            patch_error=deploy.Stop('PATCH response lost'),
            after_source=BEFORE, after_ruleset=deploy.BASELINE_RULESET))
        result, output, _, _, _ = self.run_main(api, authorization=self.approved_hash)
        self.assertEqual(result, 2)
        self.assertIn('Keep app features closed', output)
        self.assertEqual(sum(method == 'PATCH' for method, _, _ in api.calls), 1)
        self.assertEqual(api.expected, [])

    def test_archive_contains_only_fixed_evidence_and_no_credentials(self):
        (self.folder / 'private-token.txt').write_text(TEST_TOKEN)
        (self.folder / 'config.json').write_text(TEST_TOKEN)
        api = self.api(self.publication_calls())
        result, output, _, _, _ = self.run_main(api, authorization=self.approved_hash)
        self.assertEqual(result, 0)
        with zipfile.ZipFile(self.folder / deploy.ARCHIVE) as archive:
            self.assertEqual(set(archive.namelist()), {
                'result.json', 'before.rules', 'before.metadata.json',
                'recheck.rules', 'recheck.metadata.json',
                'after.rules', 'after.metadata.json',
            })
            for name in archive.namelist():
                self.assertNotIn(TEST_TOKEN, archive.read(name).decode('utf-8'))
        self.assertNotIn(TEST_TOKEN, output)

    def test_credential_subprocess_exception_is_not_printed_or_archived(self):
        for index, error in enumerate([
            subprocess.CalledProcessError(1, ['gcloud', TEST_TOKEN],
                                          output=TEST_TOKEN, stderr=TEST_TOKEN),
            subprocess.TimeoutExpired(['gcloud', TEST_TOKEN], 60,
                                      output=TEST_TOKEN, stderr=TEST_TOKEN),
        ]):
            with self.subTest(error=type(error).__name__):
                self.folder = Path(self.temporary.name) / str(index)
                result, output, _, _, factory = self.run_main(credential_error=error)
                self.assertEqual(result, 2)
                factory.assert_not_called()
                self.assertNotIn(TEST_TOKEN, output)
                with zipfile.ZipFile(self.folder / deploy.ARCHIVE) as archive:
                    for name in archive.namelist():
                        self.assertNotIn(TEST_TOKEN, archive.read(name).decode('utf-8'))

    def test_any_existing_evidence_stops_early_without_overwriting_backup(self):
        names = ['result.json', deploy.ARCHIVE, 'before.rules', 'before.metadata.json',
                 'recheck.rules', 'recheck.metadata.json', 'after.rules', 'after.metadata.json']
        for index, name in enumerate(names):
            with self.subTest(name=name):
                self.folder = Path(self.temporary.name) / str(index)
                self.folder.mkdir()
                target = self.folder / name
                target.write_text('Original backup must survive')
                result, _, candidate, credentials, factory = self.run_main(
                    authorization=self.approved_hash)
                self.assertEqual(result, 2)
                candidate.assert_not_called()
                credentials.assert_not_called()
                factory.assert_not_called()
                self.assertEqual(target.read_text(), 'Original backup must survive')
                self.assertEqual(list(self.folder.iterdir()), [target])

    def test_pinned_candidate_download_requires_approved_content(self):
        with patch.object(deploy.urllib.request, 'urlopen',
                          return_value=io.BytesIO(OTHER.encode())) as fetch:
            with self.assertRaisesRegex(deploy.Stop, 'do not match the approved SHA'):
                deploy.candidate_source()
        fetch.assert_called_once_with(deploy.SOURCE_URL, timeout=30)


class ApiScopeTests(unittest.TestCase):
    def test_malformed_or_lost_api_response_is_sanitized_and_never_retried(self):
        for response in ['null', '[]', TEST_TOKEN,
                         http.client.RemoteDisconnected(TEST_TOKEN)]:
            with self.subTest(response_type=type(response).__name__):
                opener = Mock()
                if isinstance(response, BaseException):
                    opener.open.side_effect = response
                else:
                    opener.open.return_value = io.StringIO(response)
                with patch.object(deploy.urllib.request, 'build_opener', return_value=opener):
                    api = deploy.RulesApi(TEST_TOKEN)
                    with self.assertRaises(deploy.Stop) as caught:
                        api.call('GET', deploy.RELEASE)
                self.assertNotIn(TEST_TOKEN, str(caught.exception))
                self.assertIn('No automatic retry', str(caught.exception))
                self.assertEqual(opener.open.call_count, 1)

    def test_api_refuses_other_projects_releases_services_methods_and_queries(self):
        opener = Mock()
        with patch.object(deploy.urllib.request, 'build_opener', return_value=opener):
            api = deploy.RulesApi(TEST_TOKEN)
        disallowed = [
            ('DELETE', deploy.RELEASE),
            ('POST', deploy.RELEASE),
            ('PATCH', deploy.RULESETS + '/version'),
            ('GET', deploy.RULESETS),
            ('GET', 'projects/another-project/releases/cloud.firestore'),
            ('GET', 'projects/another-project/rulesets/version'),
            ('PATCH', deploy.RELEASE.replace('cloud.firestore', 'firebase.storage')),
            ('GET', deploy.RELEASE + '?unexpected=true'),
            ('GET', deploy.RULESETS + '/../releases/cloud.firestore'),
            ('POST', 'https://example.com/collect'),
        ]
        for method, resource in disallowed:
            with self.subTest(method=method, resource=resource):
                with self.assertRaisesRegex(deploy.Stop, 'outside the approved rules scope'):
                    api.call(method, resource)
        opener.open.assert_not_called()

    def test_allowed_request_uses_rules_api_and_keeps_token_only_in_auth_header(self):
        opener = Mock()
        opener.open.return_value = io.StringIO('{"name":"ok"}')
        with patch.object(deploy.urllib.request, 'build_opener', return_value=opener) as builder:
            api = deploy.RulesApi(TEST_TOKEN)
            self.assertEqual(api.call('GET', deploy.RELEASE), {'name': 'ok'})
        self.assertIsInstance(builder.call_args.args[0], deploy.NoRedirect)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url,
                         'https://firebaserules.googleapis.com/v1/' + deploy.RELEASE)
        self.assertEqual(request.get_method(), 'GET')
        self.assertEqual(request.get_header('Authorization'), 'Bearer ' + TEST_TOKEN)
        self.assertIsNone(request.data)

    def test_redirect_is_not_followed_and_error_does_not_echo_secret(self):
        self.assertIsNone(deploy.NoRedirect().redirect_request(
            None, None, 302, 'redirect', {}, 'https://example.com/collect'))
        opener = Mock()
        opener.open.side_effect = urllib.error.HTTPError(
            'https://example.com/' + TEST_TOKEN, 302, TEST_TOKEN, {}, None)
        with patch.object(deploy.urllib.request, 'build_opener', return_value=opener):
            api = deploy.RulesApi(TEST_TOKEN)
            with self.assertRaises(deploy.Stop) as caught:
                api.call('GET', deploy.RELEASE)
        self.assertIn('HTTP 302', str(caught.exception))
        self.assertNotIn(TEST_TOKEN, str(caught.exception))
        self.assertEqual(opener.open.call_count, 1)


if __name__ == '__main__':
    unittest.main()
