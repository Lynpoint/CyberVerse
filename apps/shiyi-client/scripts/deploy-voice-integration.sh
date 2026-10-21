#!/usr/bin/env bash
set -eo pipefail
ROOT=/home/user/cyberverse-workspaces/integration
cd "$ROOT"
source /home/user/miniconda3/etc/profile.d/conda.sh
conda activate cv-integration
export PATH="$HOME/.local/cyberverse-tools/protobuf-29.3/bin:/usr/local/go/bin:$PATH"
RUNTIME="$ROOT/.shiyi-integration"
mkdir -p "$RUNTIME/backups" "$RUNTIME/logs"
chmod 700 "$RUNTIME" "$RUNTIME/backups"
python - <<'PY'
from pathlib import Path
from datetime import datetime
import json, os, re, secrets, shutil, subprocess
import yaml
root=Path.cwd()
runtime=root/'.shiyi-integration'
stamp=datetime.now().strftime('%Y%m%d-%H%M%S-%f')
for rel in ('config/cyberverse.yaml','config/env'):
 p=root/rel
 if not p.is_file(): raise SystemExit('Missing existing configuration: '+rel)
 backup=runtime/'backups'/(p.name+'.'+stamp)
 shutil.copy2(p,backup);backup.chmod(0o600)
def dotenv(path):
 result={}
 if not path.is_file(): return result
 for line in path.read_text().splitlines():
  m=re.match(r'^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=(.*)$',line)
  if m: result[m[1]]=m[2].strip().strip(chr(34)).strip(chr(39))
 return result
def usable(value):
 return bool(value) and not any(x in value.lower() for x in ('your_','your-','replace','example','xxx','changeme'))
envpath=root/'config/env'
env=dotenv(envpath)
if not usable(env.get('DASHSCOPE_API_KEY','')):
 for p in (Path('/home/user/CyberVerse/config/env'),Path('/home/user/CyberVerse/.env')):
  candidate=dotenv(p).get('DASHSCOPE_API_KEY','')
  if usable(candidate):
   env['DASHSCOPE_API_KEY']=candidate
   print('REUSED_EXISTING_PROJECT_DASHSCOPE_KEY')
   break
 if not usable(env.get('DASHSCOPE_API_KEY','')):
  result=subprocess.run(['docker','inspect','--format','{{json .Config.Env}}','infra-cyberverse-inference-1'],capture_output=True,text=True)
  if result.returncode==0:
   values=dict(x.split('=',1) for x in json.loads(result.stdout) if '=' in x)
   candidate=values.get('DASHSCOPE_API_KEY','')
   if usable(candidate): env['DASHSCOPE_API_KEY']=candidate;print('REUSED_RUNNING_PROJECT_DASHSCOPE_KEY')
updates={'GRPC_INFERENCE_ADDR':'127.0.0.1:55051'}
if usable(env.get('DASHSCOPE_API_KEY','')): updates['DASHSCOPE_API_KEY']=env['DASHSCOPE_API_KEY']
if not usable(env.get('TURN_PASSWORD','')): updates['TURN_PASSWORD']=secrets.token_hex(32)
lines=envpath.read_text().splitlines()
for key,value in updates.items():
 replacement=key+'='+__import__('shlex').quote(value)
 matches=[i for i,line in enumerate(lines) if re.match(r'^\s*(?:export\s+)?'+re.escape(key)+r'\s*=',line)]
 if len(matches)>1: raise SystemExit('Duplicate configuration key: '+key)
 if matches: lines[matches[0]]=replacement
 else: lines.append(replacement)
envpath.write_text('\n'.join(lines)+'\n');envpath.chmod(0o600)
cfgpath=root/'config/cyberverse.yaml'
cfg=yaml.safe_load(cfgpath.read_text())
cfg['server'].update(host='127.0.0.1',http_port=18080,grpc_port=55051)
cfg['inference_grpc']['addr']='127.0.0.1:55051'
cfg['inference']['avatar']['enabled']=False
cfg.setdefault('warmup',{})['enabled']=False
pipeline=cfg['pipeline']
pipeline.update(default_mode='omni',streaming_mode='direct',turn_enabled=True,turn_port=18443,ice_public_ip='127.0.0.1')
pipeline.setdefault('rag',{})['enabled']=False
pipeline.setdefault('visual_input',{})['enabled']=False
cfg.setdefault('recording',{})['enabled']=False
cfgpath.write_text(yaml.safe_dump(cfg,allow_unicode=True,sort_keys=False))
vite=root/'frontend/vite.integration.config.ts'
vite.write_text("import { mergeConfig } from 'vite'\nimport base from './vite.config'\nexport default mergeConfig(base, { server: { host: '127.0.0.1', port: 15173, strictPort: true, proxy: { '/api': { target: 'http://127.0.0.1:18080', changeOrigin: true }, '/ws': { target: 'ws://127.0.0.1:18080', ws: true } } } })\n")
exclude=root/'.git/info/exclude'
existing=exclude.read_text() if exclude.exists() else ''
additions=[x for x in ('/.shiyi-integration/','/frontend/vite.integration.config.ts') if x not in existing.splitlines()]
if additions: exclude.write_text(existing.rstrip()+'\n'+'\n'.join(additions)+'\n')
print('CONFIGURED_ISOLATED_PORTS 18080 55051 15173 18443')
print('DASHSCOPE_KEY_STATUS', 'present_unverified' if usable(env.get('DASHSCOPE_API_KEY','')) else 'NEEDS_USER_KEY')
PY
make setup >"$RUNTIME/logs/setup.log" 2>&1
python -m pip install -e ".[llm,tts,omni,qwen,rag,agent]" >>"$RUNTIME/logs/setup.log" 2>&1
npm ci --omit=dev --prefix inference/pi_bridge >>"$RUNTIME/logs/setup.log" 2>&1
python -m pip check
printf 'PREPARE_COMPLETE\n'
exit 0
