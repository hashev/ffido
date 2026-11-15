#!/usr/bin/env python3
"""Run Runner's updater lifecycle XCTest without launching a user Flutter profile."""
import argparse
import pathlib
import plistlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


def run(frameworks):
    frameworks = frameworks.resolve(strict=True)
    if not (frameworks/'Sparkle.framework/Modules/module.modulemap').is_file():
        raise ValueError('Use the matching build/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64 directory')
    platform = pathlib.Path(subprocess.check_output(['xcrun', '--show-sdk-platform-path'], text=True).strip())/'Developer'
    subprocess.run(['xcodebuild', '-version'], check=True, timeout=30)
    with tempfile.TemporaryDirectory(prefix='ffido-native-lifecycle-') as temporary:
        stage = pathlib.Path(temporary)
        subprocess.run(['xcrun', 'swiftc', '-emit-library', '-emit-module', '-enable-testing', '-module-name', 'fido',
                        str(ROOT/'apps/frontend/macos/Runner/ManagedUpdater.swift'), str(ROOT/'apps/frontend/macos/Runner/LaunchProfile.swift'),
                        '-F', str(frameworks), '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
                        '-o', str(stage/'libfido.dylib'), '-emit-module-path', str(stage/'fido.swiftmodule')], check=True, timeout=120)
        source = (ROOT/'apps/frontend/macos/RunnerTests/RunnerTests.swift').read_text()
        (stage/'RunnerTests.swift').write_text(source.replace('import FlutterMacOS\n', ''))
        bundle = stage/'RunnerTests.xctest/Contents'
        (bundle/'MacOS').mkdir(parents=True)
        (bundle/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'RunnerTests', 'CFBundleIdentifier': 'org.ffido.native-lifecycle-test', 'CFBundlePackageType': 'BNDL'}))
        command = ['xcrun', 'swiftc', '-emit-library', '-module-name', 'RunnerTests', '-I', str(stage), '-I', str(platform/'usr/lib'),
                   '-L', str(stage), '-L', str(platform/'usr/lib'), '-lfido', '-lXCTestSwiftSupport',
                   '-F', str(platform/'Library/Frameworks'), '-F', str(frameworks), '-framework', 'XCTest',
                   str(stage/'RunnerTests.swift'), '-o', str(bundle/'MacOS/RunnerTests')]
        for directory in (stage, platform/'usr/lib', platform/'Library/Frameworks'):
            command += ['-Xlinker', '-rpath', '-Xlinker', str(directory)]
        subprocess.run(command, check=True, timeout=120)
        subprocess.run(['xcrun', 'xctest', str(bundle.parent)], check=True, timeout=90)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--frameworks', type=pathlib.Path, required=True)
    run(parser.parse_args().frameworks)
