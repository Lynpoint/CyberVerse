"""Start only the owned loopback proxy; never restart Docker or shared services."""
from pathlib import Path
import subprocess


root = Path(__file__).resolve().parents[2]
branch = subprocess.check_output(['git', '-C', str(root), 'branch', '--show-current'], text=True).strip()
if root.name != 'frontend-assist' or branch != 'feat/frontend/photo-avatar-video':
    raise SystemExit('Wrong Avatar development checkout')
result = subprocess.run(['tmux', 'has-session', '-t', 'cv-avatar-proxy'], capture_output=True)
if result.returncode:
    subprocess.run(['tmux', 'new-session', '-d', '-s', 'cv-avatar-proxy', '-c', str(root),
                    'python3 ' + str(root / 'scripts/avatar-assist/loopback_proxy.py')], check=True)
print('SHIYI_AVATAR_PROXY_STARTED_OR_REUSED')
