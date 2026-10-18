import io
import json
from pathlib import Path
from subprocess import CompletedProcess
import tempfile
import unittest
from unittest.mock import patch
from export_deployed_rules import export

class ExportTests(unittest.TestCase):
    def test_only_release_and_ruleset_gets_and_no_credentials_exported(self):
        responses = [
            {'name': 'projects/demo-test/releases/cloud.firestore', 'rulesetName': 'projects/demo-test/rulesets/reviewed', 'updateTime': '2026-10-18T00:00:00Z'},
            {'source': {'files': [{'name': 'firestore.rules', 'content': 'rules_version = "2";'}]}},
        ]
        requests = []
        def read(request, timeout):
            requests.append(request)
            return io.StringIO(json.dumps(responses.pop(0)))
        with tempfile.TemporaryDirectory() as folder, patch('export_deployed_rules.shutil.which', return_value='/gcloud'), patch('export_deployed_rules.subprocess.run', return_value=CompletedProcess([],0,'test-only-token\n','')), patch('export_deployed_rules.urllib.request.urlopen', side_effect=read):
            target = Path(folder)/'published.rules'
            export('demo-test',target)
            self.assertEqual(target.read_text(),'rules_version = "2";')
            self.assertNotIn('test-only-token',target.with_suffix('.metadata.json').read_text())
        self.assertEqual(len(requests),2)
        self.assertTrue(all(r.get_method()=='GET' for r in requests))
        self.assertTrue(all(r.full_url.startswith('https://firebaserules.googleapis.com/v1/projects/demo-test/') for r in requests))

    def test_missing_credentials_are_reported_without_token_output(self):
        with patch('export_deployed_rules.shutil.which',return_value=None):
            with self.assertRaisesRegex(RuntimeError,'No gcloud'):
                export('demo-test',Path('/unused.rules'))

    def test_project_validation_prevents_arbitrary_api_urls(self):
        with self.assertRaises(ValueError):
            export('../another-project',Path('/unused.rules'))
