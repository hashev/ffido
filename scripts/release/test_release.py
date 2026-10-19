import importlib.util
import json
import pathlib
import os
import subprocess
import shutil
import tempfile
import unittest
from unittest.mock import patch

HERE = pathlib.Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE/(name+'.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


exporter, versions, publisher = load('export'), load('version'), load('publish')


class ExportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.source = self.root/'source'
        self.source.mkdir()
        (self.source/'LICENSE').write_text('MIT')
        (self.source/'apps/backend').mkdir(parents=True)
        (self.source/'apps/backend/main.cpp').write_text('source')

    def test_exports_uncommitted_code_without_history_or_runtime(self):
        for name in ['config.json', 'messages.jhr', 'metadata.db', 'metadata.db-wal']:
            (self.source/'apps/backend'/name).write_text('private')
        for name in ['Flutter/Flutter.podspec', 'Runner/GeneratedPluginRegistrant.h',
                     'Runner/GeneratedPluginRegistrant.m']:
            generated = self.source/'apps/frontend/ios'/name
            generated.parent.mkdir(parents=True, exist_ok=True)
            generated.write_text('generated cache')
        (self.source/'.git').mkdir()
        (self.source/'.git/config').write_text('old history')
        out = self.root/'output'
        report = exporter.export(self.source, out)
        self.assertEqual(set(report['files']), {'LICENSE', 'apps/backend/main.cpp'})
        self.assertFalse((out/'.git').exists())
        self.assertTrue((self.source/'apps/backend/config.json').exists())
        self.assertEqual((out/'apps/backend/main.cpp').read_text(), 'source')

    def test_rejects_overwrite_inside_source_and_symlinks(self):
        for path in [self.source/'nested', self.root]:
            with self.assertRaises(ValueError):
                exporter.export(self.source, path)
        (self.source/'apps/backend/leak').symlink_to(self.root)
        with self.assertRaises(ValueError):
            exporter.export(self.source, self.root/'output')

    def test_nested_checkout_and_large_files(self):
        checkout = self.source/'apps/backend/tmp/vendor'
        checkout.mkdir(parents=True)
        (checkout/'secret').write_text('ghp_'+'a'*40)
        exporter.export(self.source, self.root/'clean')
        (self.source/'apps/backend/large.bin').write_bytes(b'0'*(11*1024*1024))
        with self.assertRaises(ValueError):
            exporter.export(self.source, self.root/'large')

    def test_structured_password_requires_explicit_review(self):
        (self.source/'apps/backend/credentials.json').write_text('{"password": "private-password-value"}')
        with self.assertRaises(ValueError) as found:
            exporter.export(self.source, self.root/'output')
        self.assertNotIn('private-password-value', str(found.exception))

    def test_finding_does_not_expose_secret(self):
        token = 'ghp_'+'b'*40
        (self.source/'apps/backend/accidental.txt').write_text(token)
        with self.assertRaises(ValueError) as found:
            exporter.export(self.source, self.root/'output')
        self.assertNotIn(token, str(found.exception))
        self.assertFalse((self.root/'output').exists())


class VersionTest(unittest.TestCase):
    def test_master_stable_retry_and_monotonic_builds(self):
        a = versions.identity('1.0.0', 'a'*40, 1001, 'refs/heads/master', 'push', True)
        self.assertFalse(a['stable'])
        self.assertEqual(a, versions.identity('1.0.0', 'a'*40, 1001, 'refs/heads/master', 'push', True))
        b = versions.identity('1.0.0', 'a'*40, 1002, 'refs/tags/v1.0.0', 'push', True)
        self.assertTrue(b['stable'])
        self.assertGreater(b['build_number'], a['build_number'])

    def test_rejects_unmerged_closed_pr_bad_tag_and_version(self):
        for ref, event, reachable in [('refs/heads/feature', 'push', True),
                ('refs/heads/master', 'pull_request', True), ('refs/heads/master', 'push', False),
                ('refs/tags/v2.0.0', 'push', True), ('refs/tags/v1.0.0-rc1', 'push', True)]:
            with self.assertRaises(ValueError):
                versions.identity('1.0.0', 'a'*40, 1001, ref, event, reachable)


class FakeGitHub:
    def __init__(self):
        self.current = None
        self.assets = {}
        self.fail_upload = False
        self.edited = False

    def view(self, tag):
        return self.current

    def run(self, *args):
        command = args[1]
        if command == 'create':
            self.current = {'isDraft': True, 'body': args[args.index('--notes')+1]}
        elif command == 'upload':
            if self.fail_upload:
                raise RuntimeError('upload interrupted')
            for name in args[3:-1]:
                self.assets[pathlib.Path(name).name] = pathlib.Path(name).read_bytes()
        elif command == 'download':
            target = pathlib.Path(args[args.index('--dir')+1])
            for name, data in self.assets.items():
                if '--pattern' not in args or name == args[args.index('--pattern')+1]:
                    (target/name).write_bytes(data)
        elif command == 'edit':
            self.edited = True
            self.current['isDraft'] = False


class PublicationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.identity = versions.identity('1.0.0', 'a'*40, 1001, 'refs/heads/master', 'push', True)
        self.file = self.root/'client.apk'
        self.file.write_bytes(b'apk fixture')
        self.row = dict(self.identity, id='client-android-universal', file=self.file.name,
                        signing='release', sha256=publisher.digest(self.file))
        self.sidecar = self.root/'client.package.json'
        self.sidecar.write_text(json.dumps(self.row))

    def test_incomplete_unsigned_mixed_and_corrupted(self):
        for updates, expected in [({}, ['missing']), ({'signing': 'unsigned'}, [self.row['id']]),
                                  ({'sha': 'b'*40}, [self.row['id']]),
                                  ({'sha256': 'broken'}, [self.row['id']])]:
            self.sidecar.write_text(json.dumps(dict(self.row, **updates)))
            with self.assertRaises(ValueError):
                publisher.inventory(self.root, self.identity, expected)

    def test_draft_resume_public_retry_and_no_replacement(self):
        api = FakeGitHub()
        api.fail_upload = True
        with self.assertRaises(RuntimeError):
            publisher.publish(api, self.root, self.identity, [self.row])
        self.assertTrue(api.current['isDraft'])
        self.assertFalse(api.edited)
        api.fail_upload = False
        publisher.publish(api, self.root, self.identity, [self.row])
        self.assertFalse(api.current['isDraft'])
        publisher.publish(api, self.root, self.identity, [self.row])
        with self.assertRaises(ValueError):
            publisher.publish(api, self.root, self.identity, [dict(self.row, signing='different')])

    def test_mismatched_existing_release_is_untouched(self):
        api = FakeGitHub()
        api.current = {'isDraft': False, 'body': 'Other commit'}
        with self.assertRaises(ValueError):
            publisher.publish(api, self.root, self.identity, [self.row])
        self.assertFalse(api.edited)
        self.assertEqual(api.assets, {})

class GovernanceTest(unittest.TestCase):
    def test_bypass_ci_permissions_and_access(self):
        audit = load('audit_github')
        repository = {'private': False, 'default_branch': 'master', 'pull_request_creation_policy': 'collaborators_only'}
        rule = {'enforcement': 'active', 'bypass_actors': [],
                'conditions': {'ref_name': {'include': ['refs/heads/master']}},
                'rules': [{'type': 'deletion'}, {'type': 'non_fast_forward'},
                          {'type': 'pull_request', 'parameters': {'required_approving_review_count': 0,
                           'required_review_thread_resolution': True}},
                          {'type': 'required_status_checks', 'parameters': {
                              'strict_required_status_checks_policy': True,
                              'required_status_checks': [{'context': 'ci-required', 'integration_id': 15368}]}}]}
        workflow = {'default_workflow_permissions': 'read', 'can_approve_pull_request_reviews': False}
        self.assertEqual(audit.check(repository, [rule], workflow), [])
        for modified in [dict(rule, bypass_actors=[{'actor_id': 1}]),
                         dict(rule, rules=rule['rules'][:-1]), dict(rule, enforcement='disabled')]:
            self.assertTrue(audit.check(repository, [modified], workflow))
        self.assertTrue(audit.check(dict(repository, pull_request_creation_policy='all'), [rule], workflow))
        self.assertTrue(audit.check(repository, [rule], dict(workflow, default_workflow_permissions='write')))


class PackagingGateTest(unittest.TestCase):
    def test_signed_mode_never_falls_back_to_unsigned(self):
        module = load('package')
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root/'scripts/release').mkdir(parents=True)
            (root/'scripts/release/settings.json').write_text(json.dumps({'desktop_signing': 'signed'}))
            with patch.object(module, 'ROOT', root), self.assertRaisesRegex(ValueError, 'no unsigned fallback'):
                module.package('client', 'macos', 'arm64', {}, root/'out', root/'build', root/'deps')

    def test_public_apk_requires_complete_abis_and_matching_permanent_certificate(self):
        import zipfile
        module = load('package')
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root/'scripts/release').mkdir(parents=True)
            (root/'scripts/release/settings.json').write_text(json.dumps({'desktop_signing': 'unsigned'}))
            for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md']:
                (root/name).write_text('fixture')
            apk = root/'apps/frontend/build/app/outputs/flutter-apk/app-release.apk'
            apk.parent.mkdir(parents=True)
            with zipfile.ZipFile(apk, 'w') as out:
                out.writestr('lib/arm64-v8a/libapp.so', b'fixture')
            with patch.object(module, 'ROOT', root), self.assertRaisesRegex(ValueError, 'three supported ABIs'):
                module.package('client', 'android', 'universal', {'tag': 'test'}, root/'out', root/'build', root/'deps', True)
            with zipfile.ZipFile(apk, 'w') as out:
                for abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']:
                    out.writestr(f'lib/{abi}/libapp.so', b'fixture')
            verifier = root/'sdk/build-tools/34/apksigner'
            verifier.parent.mkdir(parents=True)
            verifier.touch()
            environment = {'ANDROID_HOME': str(root/'sdk'), 'ANDROID_CERT_SHA256': 'abcdef'}
            for certificate, message in [('Signer Android Debug abcdef', 'Debug APK'),
                                          ('Release signer 123456', 'does not match')]:
                with patch.object(module, 'ROOT', root), patch.object(module, 'run', return_value=certificate), patch.dict(os.environ, environment), self.assertRaisesRegex(ValueError, message):
                    module.package('client', 'android', 'universal', {'tag': 'test'}, root/'out', root/'build', root/'deps', True)


class LicenseTest(unittest.TestCase):
    def test_android_embeds_the_authoritative_mit_notice(self):
        root = HERE.parent.parent
        self.assertEqual((root/'LICENSE').read_bytes(),
                         (root/'apps/frontend/assets/legal/LICENSE').read_bytes())
        self.assertIn('    - assets/legal/LICENSE', (root/'apps/frontend/pubspec.yaml').read_text())


class RelinkRegressionTest(unittest.TestCase):
    def test_read_only_library_preserves_link_order_and_runtime_alias(self):
        module = load('package')
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            source = root/'source'
            (source/'scripts/release').mkdir(parents=True)
            (source/'LICENSE').write_text('MIT fixture')
            shutil.copy2(HERE/'export.py', source/'scripts/release/export.py')
            shutil.copy2(HERE/'RELINK.md', source/'scripts/release/RELINK.md')
            archive = root/'read-only.2.4.dylib'
            archive.write_bytes(b'archive fixture')
            archive.chmod(0o444)
            build = root/'build'
            for name in ['fidoback', 'ffido-admin', 'ffido-hpt-auth']:
                command = build/f'apps/backend/CMakeFiles/{name}.dir/link.txt'
                command.parent.mkdir(parents=True)
                command.write_text(f'c++ {archive} {archive} -o {name}')
            for name in ['spdlog', 'nlohmann_json', 'sqlite3']:
                (build/f'_deps/{name}-src').mkdir(parents=True)
            legal = root/'deps/prefix/share/ffido/legal'
            legal.mkdir(parents=True)
            (legal/'revisions.json').write_text('{}')
            stage = root/'stage'
            stage.mkdir()
            with patch.object(module, 'ROOT', source), patch.object(module.platform, 'system', return_value='Darwin'), patch.object(module, 'run', return_value='fixture:\n/opt/fixture/lib/read-only.2.dylib\n'):
                module.relink(stage, build, root/'deps')
            relink = stage/'share/ffido/relink'
            self.assertEqual(len(list(relink.glob('*.dylib'))), 1)
            self.assertEqual((relink/'relink.sh').read_text().count('read-only.2.4.dylib'), 6)
            self.assertIn('@loader_path/../../../../lib/read-only.2.dylib', (relink/'relink.sh').read_text())
            tools = root/'tools'
            tools.mkdir()
            compiler = tools/'compiler'
            compiler.write_text('#!/bin/sh\ntest "$SDKROOT" = "$FFIDO_TEST_SDK" || exit 9\necho linked >> "$FFIDO_TEST_LINK_TRACE"\n')
            (tools/'xcrun').write_text('#!/bin/sh\ntest "$*" = "--sdk macosx --show-sdk-path" || exit 8\nprintf "%s\\n" "$FFIDO_TEST_SDK"\n')
            for name in ['install_name_tool', 'codesign']:
                (tools/name).write_text('#!/bin/sh\nexit 0\n')
            for command in tools.iterdir():
                command.chmod(0o755)
            trace = root/'linked.txt'
            environment = {**os.environ, 'PATH': str(tools)+os.pathsep+os.environ['PATH'],
                           'CXX': str(compiler), 'SDKROOT': '/original-sdk-is-unavailable',
                           'FFIDO_TEST_SDK': str(root/'selected SDK'), 'FFIDO_TEST_LINK_TRACE': str(trace)}
            subprocess.run(['sh', str(relink/'relink.sh')], env=environment, check=True)
            self.assertEqual(trace.read_text().splitlines(), ['linked']*3)



class LegalGateTest(unittest.TestCase):
    def test_server_rejects_missing_dependency_sources(self):
        module = load('package')
        with tempfile.TemporaryDirectory() as tmp:
            stage = pathlib.Path(tmp)
            (stage/'legal').mkdir()
            for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md']:
                (stage/'legal'/name).write_text('fixture')
            legal = stage/'share/ffido/legal'
            legal.mkdir(parents=True)
            (legal/'revisions.json').write_text(json.dumps({'huskylib': 'a'*40}))
            with self.assertRaisesRegex(ValueError, 'Missing dependency sources: huskylib'):
                module.verify_legal(stage, 'server', 'linux')

    def test_desktop_rejects_missing_embedded_mit_notice(self):
        module = load('package')
        with tempfile.TemporaryDirectory() as tmp:
            stage = pathlib.Path(tmp)
            (stage/'legal').mkdir()
            for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'Flutter-LICENSE']:
                (stage/'legal'/name).write_text('fixture')
            with self.assertRaisesRegex(ValueError, 'embedded MIT notice'):
                module.verify_legal(stage, 'client', 'windows')


if __name__ == '__main__':
    unittest.main()
