#!/usr/bin/env python3
"""Exercise installer transactions in disposable bundles; stub OS registration/launch only."""
import os
import plistlib
import subprocess
import tempfile
from pathlib import Path

source = (Path(__file__).parent / 'install-update.sh').read_text()
for scenario in ['success', 'bad-signature', 'copy-failure', 'rename-failure', 'launch-failure', 'still-running', 'occupied-path']:
    with tempfile.TemporaryDirectory(prefix='todoy-installer-test-') as temp:
        root = Path(temp)
        work = root / 'workspace'
        candidate = work / 'ToDoy.app'
        target = root / 'Applications' / 'ToDoy.app'
        result = root / 'data' / 'update-result.txt'
        sentinel = root / 'data' / 'tasks.json'
        sentinel.parent.mkdir()
        sentinel.write_text('user-data-must-stay')
        for bundle, marker in [(candidate, 'new'), (target, 'old')]:
            (bundle / 'Contents').mkdir(parents=True)
            (bundle / 'marker').write_text(marker)
            (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'local.desktop.todo.panel'}))
        bins = root / 'bin'
        bins.mkdir()
        def executable(name, text):
            path = bins / name
            path.write_text('#!/bin/zsh\n' + text)
            path.chmod(0o755)
            return str(path)
        no_op = executable('noop', 'exit 0\n')
        code = source
        for tool in ['/usr/bin/pluginkit', '/usr/bin/pkill', '/usr/bin/killall',
                     '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister']:
            code = code.replace(tool, no_op)
        code = code.replace('/usr/bin/codesign', '/usr/bin/false' if scenario == 'bad-signature' else no_op)
        if scenario == 'copy-failure':
            code = code.replace('/usr/bin/ditto', '/usr/bin/false')
        launch = executable('launch', '[[ "$(cat "$1/marker")" == new ]] && exit 1\nexit 0\n' if scenario == 'launch-failure' else 'exit 0\n')
        code = code.replace('/usr/bin/open', launch)
        if scenario == 'rename-failure':
            executable('mv', '[[ "$1" == *".ToDoy-update-"* ]] && exit 1\nexec /bin/mv "$@"\n')
        parent = str(os.getpid()) if scenario == 'still-running' else '99999999'
        if scenario == 'still-running':
            code = code.replace('{1..120}', '{1..1}').replace('sleep 1', 'true')
        collision = target.parent / f'.ToDoy-update-{parent}.app'
        if scenario == 'occupied-path':
            collision.mkdir()
            (collision / 'do-not-delete').write_text('untouched')
        helper = root / 'helper.sh'
        helper.write_text(code)
        completed = subprocess.run(['/bin/zsh', str(helper), parent, str(candidate), str(target), str(result)],
                                   env={**os.environ, 'PATH': str(bins) + ':' + os.environ['PATH']}, capture_output=True, text=True)
        success = scenario == 'success'
        assert (completed.returncode == 0) == success, (scenario, completed.stderr)
        assert (target / 'marker').read_text() == ('new' if success else 'old'), scenario
        assert sentinel.read_text() == 'user-data-must-stay', scenario
        assert result.exists() != success, scenario
        assert not (target.parent / f'.ToDoy-backup-{parent}.app').exists(), scenario
        if scenario == 'occupied-path':
            assert (collision / 'do-not-delete').read_text() == 'untouched'
        print(scenario, 'OK')
