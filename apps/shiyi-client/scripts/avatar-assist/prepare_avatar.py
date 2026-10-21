"""Prepare GPU-1 Avatar without restarting or reconfiguring shared services."""
import argparse
import json
from pathlib import Path
import secrets
import subprocess

import yaml


OWNER = 'shiyi-avatar-assist'
BRANCH = 'feat/frontend/photo-avatar-video'


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()


def runtime_image(container, tag):
    exists = subprocess.run(['docker', 'image', 'inspect', tag], capture_output=True).returncode == 0
    if exists:
        image = json.loads(run(['docker', 'image', 'inspect', tag]))[0]
        if image['Config'].get('Labels', {}).get('shiyi.owner') != OWNER:
            raise RuntimeError('Existing image is not owned by this deployment: ' + tag)
        return tag
    info = json.loads(run(['docker', 'inspect', container]))[0]
    # Mounted config/data are excluded. Never pause the shared container or
    # preserve its injected credentials in the new image configuration.
    preserve = {'PATH', 'LD_LIBRARY_PATH', 'CUDA_VERSION', 'NVIDIA_VISIBLE_DEVICES',
                'NVIDIA_DRIVER_CAPABILITIES', 'NVIDIA_REQUIRE_CUDA', 'PYTHONUNBUFFERED',
                'LANG', 'LC_ALL', 'DEBIAN_FRONTEND', 'NVARCH', 'CUDA_HOME'}
    cmd = ['docker', 'commit', '--pause=false', '--change', 'LABEL shiyi.owner=' + OWNER]
    cleared = []
    for entry in info['Config'].get('Env') or []:
        name = entry.partition('=')[0]
        if name not in preserve:
            cmd.extend(['--change', 'ENV ' + name + '='])
            cleared.append(name)
    cmd.extend([container, tag])
    run(cmd, timeout=240)
    saved = json.loads(run(['docker', 'image', 'inspect', tag]))[0]
    for entry in saved['Config'].get('Env') or []:
        name, _, value = entry.partition('=')
        if name in cleared and value:
            raise RuntimeError('Runtime image credential sanitization failed')
    return tag


def prepare(root, integration, checkpoints):
    root = root.resolve()
    if root.name != 'frontend-assist' or run(['git', '-C', str(root), 'branch', '--show-current']) != BRANCH:
        raise RuntimeError('Run only in frontend-assist on ' + BRANCH)
    for sub in ['SoulX-FlashHead-1_3B', 'wav2vec2-base-960h']:
        if not (checkpoints / sub).is_dir():
            raise RuntimeError('Missing model directory: ' + sub)
    runtime = root / '.shiyi-avatar'
    config = runtime / 'config'
    if config.exists():
        raise RuntimeError('Existing runtime configuration preserved; review instead of overwriting')
    values = {}
    for line in (integration / 'config/env').read_text().splitlines():
        key, sep, value = line.strip().partition('=')
        if sep and key.strip() in {
            'DASHSCOPE_API_KEY', 'DASHSCOPE_BASE_URL', 'DASHSCOPE_WS_URL',
            'DASHSCOPE_OMNI_WS_URL', 'DASHSCOPE_COSYVOICE_WS_URL',
        }:
            values[key.strip()] = value.strip().strip(chr(34) + chr(39))
    if not values.get('DASHSCOPE_API_KEY'):
        raise RuntimeError('No existing approved Qwen credential is configured')
    runtime.mkdir(exist_ok=True)
    config.mkdir(mode=0o700)
    for name in ['data', 'cache']:
        (runtime / name).mkdir(mode=0o700, exist_ok=True)
    cfg = yaml.safe_load((integration / 'config/cyberverse.yaml').read_text())
    cfg['server'].update(host='0.0.0.0', http_port=18082, grpc_port=55053)
    cfg['inference_grpc']['addr'] = 'inference:55053'
    cfg['warmup']['enabled'] = False
    cfg['inference']['avatar'].update(enabled=True, default='flash_head', idle_strategy='silent_inference')
    gpu_uuid = run(['nvidia-smi', '--id=1', '--query-gpu=uuid', '--format=csv,noheader'])
    if not gpu_uuid.startswith('GPU-') or '\n' in gpu_uuid:
        raise RuntimeError('Cannot uniquely identify GPU 1')
    cfg['inference']['avatar']['runtime'] = {'cuda_visible_devices': gpu_uuid, 'world_size': 1}
    cfg['session']['max_concurrent'] = 1
    cfg['pipeline'].update(default_mode='omni', streaming_mode='direct', turn_port=18445, ice_public_ip='127.0.0.1')
    cfg['recording']['enabled'] = False
    (config / 'cyberverse.yaml').write_text(yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False))
    avatar = config / 'avatar_models'
    avatar.mkdir()
    model = yaml.safe_load((root / 'infra/config/avatar_models/flash_head.yaml').read_text())
    model['flash_head'].update(model_type='lite', compile_model=False, compile_vae=False)
    (avatar / 'flash_head.yaml').write_text(yaml.safe_dump(model, sort_keys=False))
    values['TURN_PASSWORD'] = secrets.token_urlsafe(32)
    env = config / 'env'
    env.write_text(''.join(k + '=' + v + '\n' for k, v in values.items()))
    env.chmod(0o600)
    exclude = root / '.git/info/exclude'
    current = exclude.read_text() if exclude.exists() else ''
    if '/.shiyi-avatar/' not in current.splitlines():
        with exclude.open('a') as f:
            f.write('\n/.shiyi-avatar/\n')
    subprocess.run(['python3', str(root / 'scripts/avatar-assist/build_server.py')], check=True)
    inference_image = runtime_image('infra-cyberverse-inference-1', 'shiyi/local-inference:avatar-20261021')
    server_image = runtime_image('infra-cyberverse-server-1', 'shiyi/local-server:avatar-20261021')
    (runtime / 'compose.env').write_text('\n'.join([
        'SHIYI_ROOT=' + str(root),
        'SHIYI_GPU_UUID=' + gpu_uuid,
        'SHIYI_CHECKPOINTS=' + str(checkpoints.resolve()),
        'SHIYI_INFERENCE_IMAGE=' + inference_image,
        'SHIYI_SERVER_IMAGE=' + server_image, '']))
    print(json.dumps({'prepared': True, 'branch': BRANCH, 'gpu': 1, 'api_port': 18082,
                      'turn_port': 18445, 'runtime': str(runtime), 'credentials_printed': False}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--integration', type=Path, required=True)
    parser.add_argument('--checkpoints', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.root, args.integration, args.checkpoints)


if __name__ == '__main__':
    main()
