"""Build only the isolated API binary, never modify shared deployments."""
from pathlib import Path
import os
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[2]
branch = subprocess.check_output(['git', '-C', str(root), 'branch', '--show-current'], text=True).strip()
if root.name != 'frontend-assist' or branch != 'feat/frontend/photo-avatar-video':
    raise SystemExit('Wrong Avatar development checkout')
go = Path('/usr/local/go/bin/go')
if not go.is_file():
    raise SystemExit('Go 1.25 is required to build the isolated API')
patch = root / 'scripts/avatar-assist/direct-bitrate.patch'
helper = root / 'server/internal/direct/shiyi_bitrate.go'
if not helper.exists():
    subprocess.run(['git', '-C', str(root), 'apply', '--check', '--recount', str(patch)], check=True)
    subprocess.run(['git', '-C', str(root), 'apply', '--recount', str(patch)], check=True)
    for name in ['shiyi_bitrate.go', 'shiyi_bitrate_test.go']:
        target = root / 'server/internal/direct' / name
        target.write_bytes((root / 'scripts/avatar-assist' / name).read_bytes())
runtime = root / '.shiyi-avatar/runtime'
runtime.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, CGO_ENABLED='1', GOMAXPROCS='4', GOCACHE=str(runtime / 'go-cache'))
gofmt = str(go.parent / 'gofmt')
subprocess.run([gofmt, '-w', str(helper), str(helper.with_name('shiyi_bitrate_test.go'))], check=True)
subprocess.run([str(go), 'test', '-p', '4', './internal/direct'], cwd=root / 'server', env=env, check=True)
output = runtime / 'cyberverse-server'
subprocess.run([str(go), 'build', '-p', '4', '-tags', 'netgo,osusergo',
                '-o', str(output) + '.new', './cmd/cyberverse-server'],
               cwd=root / 'server', env=env, check=True)
libraries = runtime / 'lib'
libraries.mkdir(exist_ok=True)
dependencies = subprocess.check_output(['ldd', str(output) + '.new'], text=True)
if 'not found' in dependencies:
    raise SystemExit('A private API runtime dependency is missing')
for line in dependencies.splitlines():
    match = re.search(r'(/[^ ]+) +\(', line)
    if match:
        path = Path(match.group(1))
        if not path.is_file():
            raise SystemExit('Invalid runtime library path')
        shutil.copy2(path, libraries / path.name)
if not (libraries / 'ld-linux-x86-64.so.2').is_file():
    raise SystemExit('Expected x86-64 Linux dynamic loader is missing')
Path(str(output) + '.new').replace(output)
print('SHIYI_LOW_BANDWIDTH_API_BUILT')
