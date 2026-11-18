#!/usr/bin/env python3
"""Offline regression checks for source resolution and scheduled rebuilds."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('sources', ROOT / 'docker/resolve-sources.py')
sources = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(sources)
SHA = 'a' * 40


def metadata():
    return {'target': {f'runner-php-8-4-trixie-{variant}': {
        'target': variant, 'args': {'VERSION': '8.4-trixie', 'PHP_VERSION': '8.4.27',
            'FRANKENPHP_VERSION': 'v1.13.5', 'FRANKENPHP_REVISION': SHA},
        'tags': ['example:test'], 'platforms': ['linux/amd64', 'linux/arm64']}
        for variant in ('prod', 'dev')}}


class ResolverTests(unittest.TestCase):
    def fake(self, url):
        if 'php.net' in url:
            return json.dumps({'version': '8.4.27', 'source': [
                {'filename': 'php-8.4.27.tar.xz', 'sha256': 'b' * 64}]}).encode()
        if '/commits/' in url:
            return json.dumps({'sha': SHA}).encode()
        return json.dumps({'tag_name': 'v1.13.5', 'draft': False, 'prerelease': False}).encode()

    def test_resolves_once_and_shares_exact_versions(self):
        calls = []
        def fetch(url):
            calls.append(url)
            return self.fake(url)
        result = sources.resolve(metadata(), fetch)
        self.assertEqual(len(calls), 3)
        for target in result['target'].values():
            self.assertEqual(target['args']['PHP_SHA256'], 'b' * 64)
            self.assertEqual(target['args']['FRANKENPHP_REVISION'], SHA)

    def test_rejects_wrong_php_line(self):
        def fetch(url):
            return self.fake(url).replace(b'8.4.27', b'8.5.12')
        with self.assertRaises(ValueError):
            sources.resolve(metadata(), fetch)

    def test_rejects_prerelease(self):
        def fetch(url):
            if '/releases/latest' in url:
                return b'{"tag_name":"v1.13.5","prerelease":true}'
            return self.fake(url)
        with self.assertRaises(ValueError):
            sources.resolve(metadata(), fetch)


class PlannerTests(unittest.TestCase):
    def run_plan(self, case):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / 'metadata.json').write_text(json.dumps(metadata()))
            (path / 'date').write_text('#!/bin/sh\necho 2\n')
            (path / 'docker').write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
case = os.environ['CASE']
if '--raw' in args:
    print(json.dumps({'manifests': [{'platform': {'os':'linux','architecture':arch},'digest':'sha256:'+arch} for arch in ('amd64','arm64')]}))
elif '--format' in args:
    labels = {'org.opencontainers.image.php.version':'8.4.27','org.opencontainers.image.frankenphp.version':'v1.13.5','org.opencontainers.image.frankenphp.revision':'a'*40}
    if case == 'old-arm' and args[-1].endswith('arm64'):
        labels['org.opencontainers.image.php.version'] = '8.4.26'
    if case == 'missing': labels = {}
    print(json.dumps({'config':{'Labels':labels}}))
elif 'apt-get update' in args[-1]:
    if case == 'apt-error': sys.exit(1)
    print('1' if case == 'apt-update' else '0')
else:
    print('v26.0.0\\n11.0.0\\n4.0.0')
''')
            for name in ('date', 'docker'):
                (path / name).chmod(0o755)
            return subprocess.run(['bash', str(ROOT / '.github/scripts/plan-scheduled-build.sh'), str(path / 'metadata.json')],
                env={**os.environ, 'PATH': tmp + ':' + os.environ['PATH'], 'CASE': case}, capture_output=True, text=True)

    def test_unchanged_builds_only_dev(self):
        result = self.run_plan('same')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ['php-8-4-trixie-dev'])

    def test_source_change_and_missing_labels_rebuild(self):
        for case in ('old-arm', 'missing', 'apt-update'):
            with self.subTest(case=case):
                result = self.run_plan(case)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(json.loads(result.stdout)), 2)

    def test_apt_error_is_not_silently_treated_as_no_updates(self):
        self.assertNotEqual(self.run_plan('apt-error').returncode, 0)


if __name__ == '__main__':
    unittest.main()
