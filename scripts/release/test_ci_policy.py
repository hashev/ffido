from pathlib import Path
import unittest
import json
import os
import subprocess
import sys
import textwrap

ROOT = Path(__file__).resolve().parents[2]


def workflow(name):
    return (ROOT/'.github/workflows'/name).read_text()


class CIPolicyTest(unittest.TestCase):
    def test_only_old_same_pr_is_cancelled(self):
        text = workflow('ci.yml')
        self.assertIn('github.event.pull_request.number || github.run_id', text)
        self.assertIn("cancel-in-progress: ${{ github.event_name == 'pull_request' }}", text)
        self.assertNotIn('cancel-in-progress: true', workflow('release.yml'))
        self.assertNotIn('cancel-in-progress: true', workflow('native-dependencies.yml'))

    def test_sign_parallel_but_publication_requires_entire_matrix(self):
        text = workflow('release.yml')
        sign = text.split('  android-sign:\n')[1].split('  publish:\n')[0]
        publish = text.split('  publish:\n')[1]
        self.assertIn('needs: identity\n', sign)
        self.assertNotIn('needs: [identity, verify]', sign)
        self.assertIn("github.ref == 'refs/heads/master'", sign)
        self.assertIn("startsWith(github.ref, 'refs/tags/v')", sign)
        self.assertIn('needs: [identity, verify, android-sign]', publish)
        self.assertNotIn('always()', publish)
        self.assertNotIn('continue-on-error', publish)
        self.assertIn('contents: read', text)
        self.assertNotIn('contents: write', sign)
        self.assertIn('--check-only', publish)
        self.assertIn('actions/download-artifact@', publish)
        self.assertNotIn('run-id:', publish)
        self.assertNotIn('repository:', publish)

    def test_sdk_archives_do_not_evict_native_or_analysis_caches(self):
        for name in ('build.yml', 'release.yml'):
            blocks = workflow(name).split('      - uses: subosito/flutter-action@')[1:]
            self.assertTrue(blocks)
            for block in blocks:
                setup = block.split('      - ', 1)[0]
                self.assertIn('cache: false', setup)
                self.assertIn('pub-cache: true', setup)

    def test_backend_smoke_uses_locked_python_after_brew(self):
        backend = workflow('build.yml').split('  backend:\n')[1].split('  container:\n')[0]
        self.assertIn('python-version: ${{ steps.dependency-lock.outputs.python }}', backend)
        self.assertIn('cache: pip', backend)
        self.assertIn('-DPython3_EXECUTABLE="$(command -v python3)"', backend)
        self.assertIn('cache-dependency-path: scripts/update/requirements.txt', backend)
        self.assertLess(backend.index('name: macOS tools'), backend.index('name: Pinned backend Python'))
        self.assertLess(backend.index('name: Pinned backend Python'), backend.index('uses: ./.github/actions/native-dependencies'))

    def test_portable_checks_once_platform_tests_preserved(self):
        text = workflow('build.yml')
        self.assertEqual(text.count('flutter analyze --no-pub'), 1)
        self.assertEqual(text.count('scripts/check_dart.py --check'), 1)
        self.assertIn('flutter test --no-pub', text.split('  client:\n')[1])
        self.assertIn('check_ctest.py build/backend', text)
        self.assertIn('tools/proto/generate.sh --check', text)
        self.assertIn('needs: [release-tools, portable-checks, client, android-fixtures, android-qa, backend, container, metrics]', text.split('  build-required:')[1])
        self.assertIn("all(job['result'] == 'success'", text)
        self.assertIn('if: always()', text)

    def test_required_gate_executes_and_rejects_each_non_success(self):
        block = workflow('build.yml').split('  build-required:')[1]
        script = textwrap.dedent(block.split("python3 - <<'PY'\n")[1].split('          PY')[0])
        names = ['release-tools', 'portable-checks', 'client', 'android-fixtures',
                 'android-qa', 'backend', 'container', 'metrics']
        results = {name: {'result': 'success'} for name in names}
        good = subprocess.run([sys.executable, '-c', script], env={**os.environ, 'RESULTS': json.dumps(results)}, capture_output=True)
        self.assertEqual(good.returncode, 0)
        for name in names:
            for status in ('failure', 'cancelled', 'skipped'):
                changed = {**results, name: {'result': status}}
                bad = subprocess.run([sys.executable, '-c', script], env={**os.environ, 'RESULTS': json.dumps(changed)}, capture_output=True)
                self.assertNotEqual(bad.returncode, 0, (name, status))

    def test_docker_component_caches_survive_new_builders(self):
        action = (ROOT/'.github/actions/docker-native-cache/action.yml').read_text()
        self.assertNotIn('restore-keys:', action)
        self.assertIn('--target native-profile', action)
        self.assertIn('--target native-cache-import', action)
        self.assertIn('--target native-cache-snapshot', action)
        for name in ('abseil', 'protobuf', 'grpc', 'huskylib', 'smapi', 'fidoconf', 'areafix', 'hpt'):
            self.assertEqual(action.count(f'path: build/docker-native-cache/{name}'), 2)
        self.assertIn('docker-native:', workflow('native-dependencies.yml'))
        self.assertIn("if: github.ref == 'refs/heads/master'", workflow('native-dependencies.yml'))
        self.assertIn('MACOSX_DEPLOYMENT_TARGET=15.0', workflow('build.yml'))

    def test_cpp_check_modes_cannot_bypass_all_checks(self):
        invalid = subprocess.run([sys.executable, str(ROOT/'scripts/check_cpp.py'),
                                  '--format-check', '--skip-format'], capture_output=True)
        self.assertEqual(invalid.returncode, 2)

    def test_container_tests_are_not_reused_from_another_run(self):
        text = workflow('build.yml')
        self.assertIn('FFIDO_TEST_RUN=${{ github.run_id }}.${{ github.run_attempt }}', text)
        docker = (ROOT/'Dockerfile').read_text()
        self.assertLess(docker.index('cmake --build build/backend'), docker.index('ARG FFIDO_TEST_RUN'))
        self.assertLess(docker.index('ARG FFIDO_TEST_RUN'), docker.index('check_ctest.py build/backend'))
        self.assertIn('test -n "$FFIDO_TEST_RUN"', docker)

    def test_component_cache_is_exact_and_never_saves_partial(self):
        text = (ROOT/'.github/actions/native-dependencies/action.yml').read_text()
        self.assertNotIn('restore-keys:', text)
        self.assertIn('from native_cache import verify', text)
        self.assertNotIn('contents: write', text)
        for name in ('abseil', 'protobuf', 'grpc', 'huskylib', 'smapi', 'fidoconf', 'areafix', 'hpt'):
            self.assertIn(f"steps.complete.outputs.{name} == 'true'", text)
            self.assertIn(f'native-v2-{name}-${{{{ steps.profile.outputs.{name} }}}}', text)
