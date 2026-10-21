#!/usr/bin/env bash
set -eo pipefail
ROOT=/home/user/cyberverse-workspaces/integration
RUNTIME="$ROOT/.shiyi-integration"
SESSION=cv-integration
if tmux has-session -t "$SESSION" 2>/dev/null; then
  printf 'SESSION_ALREADY_EXISTS; reusing integration services\n'
  exit 0
fi
if ss -ltn | grep -Eq ':(18080|55051|15173|18443)([[:space:]]|$)'; then
  printf 'PORT_CONFLICT; no services started\n'
  exit 1
fi
test -d "$RUNTIME/logs"
tmux new-session -d -s "$SESSION" -n control -c "$ROOT"
tmux set-option -t "$SESSION" remain-on-exit on
COMMON="set -o pipefail; cd '$ROOT'; source /home/user/miniconda3/etc/profile.d/conda.sh; conda activate cv-integration; export PATH=\"\$HOME/.local/cyberverse-tools/protobuf-29.3/bin:/usr/local/go/bin:\$PATH\";"
tmux new-window -t "$SESSION" -n inference bash -lc "$COMMON make inference 2>&1 | tee -a '$RUNTIME/logs/inference.log'"
tmux new-window -t "$SESSION" -n api bash -lc "$COMMON GRPC_INFERENCE_ADDR=127.0.0.1:55051 make server CONDA_ENV=\"\$CONDA_PREFIX\" GO=/usr/local/go/bin/go 2>&1 | tee -a '$RUNTIME/logs/api.log'"
tmux new-window -t "$SESSION" -n web bash -lc "$COMMON cd frontend; npm run build -- --mode integration > '$RUNTIME/logs/frontend-build.log' 2>&1 && npm run preview -- --config vite.integration.config.ts --host 127.0.0.1 --port 15173 --strictPort 2>&1 | tee -a '$RUNTIME/logs/web.log'"
tmux list-windows -t "$SESSION"
printf 'START_COMMANDS_DISPATCHED\n'
exit 0
