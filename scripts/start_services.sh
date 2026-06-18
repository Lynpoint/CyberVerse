#!/usr/bin/env bash
# Restart the local CyberVerse development services.
# Usage: scripts/start_services.sh [inference|server|frontend ...]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="${ROOT_DIR}/.run"
LOG_DIR="${RUN_DIR}/logs"
STOP_TIMEOUT="${STOP_TIMEOUT:-10}"
SERVICES=(inference server frontend)

cd "${ROOT_DIR}"

if [[ ! -f ".venv/bin/activate" ]]; then
  echo "Virtual environment not found: ${ROOT_DIR}/.venv/bin/activate" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"

is_known_service() {
  local service="$1"

  case "${service}" in
    inference|server|frontend) return 0 ;;
    *) return 1 ;;
  esac
}

process_cwd_in_repo() {
  local pid="$1"
  local line cwd=""

  while IFS= read -r line; do
    if [[ "${line}" == n* ]]; then
      cwd="${line#n}"
      break
    fi
  done < <(lsof -a -p "${pid}" -d cwd -Fn 2>/dev/null || true)

  [[ -n "${cwd}" && ( "${cwd}" == "${ROOT_DIR}" || "${cwd}" == "${ROOT_DIR}"/* ) ]]
}

matches_service_command() {
  local service="$1"
  local command="$2"

  case "${service}" in
    inference)
      [[ "${command}" == *"make inference"* ||
         "${command}" == *"scripts/inference.sh"* ||
         "${command}" == *"-m inference.server"* ]]
      ;;
    server)
      [[ "${command}" == *"make server"* ||
         "${command}" == *"cmd/cyberverse-server"* ||
         "${command}" == *"cyberverse-server"* ]]
      ;;
    frontend)
      [[ "${command}" == *"make frontend"* ||
         "${command}" == *"npm run dev"* ||
         "${command}" == *"vite"* ]]
      ;;
  esac
}

pid_belongs_to_service() {
  local service="$1"
  local pid="$2"
  local command

  command="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
  [[ -n "${command}" ]] || return 1
  matches_service_command "${service}" "${command}" && process_cwd_in_repo "${pid}"
}

discover_service_pids() {
  local service="$1"
  local pid command

  ps -axo pid=,command= | while read -r pid command; do
    [[ -n "${pid:-}" && "${pid}" =~ ^[0-9]+$ ]] || continue
    [[ "${pid}" != "$$" ]] || continue

    if matches_service_command "${service}" "${command:-}" && process_cwd_in_repo "${pid}"; then
      printf '%s\n' "${pid}"
    fi
  done
}

children_of() {
  local pid="$1"
  pgrep -P "${pid}" 2>/dev/null || true
}

kill_tree_once() {
  local signal="$1"
  local pid="$2"
  local child

  [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] || return 0
  [[ "${pid}" != "$$" ]] || return 0
  [[ -z "${BASHPID:-}" || "${pid}" != "${BASHPID}" ]] || return 0
  kill -0 "${pid}" 2>/dev/null || return 0

  for child in $(children_of "${pid}"); do
    kill_tree_once "${signal}" "${child}"
  done

  kill "-${signal}" "${pid}" 2>/dev/null || true
}

wait_for_exit() {
  local pid="$1"
  local waited=0

  while kill -0 "${pid}" 2>/dev/null; do
    if (( waited >= STOP_TIMEOUT )); then
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  return 0
}

stop_service() {
  local service="$1"
  local pid_file="${LOG_DIR}/${service}.pid"
  local pids=()
  local unique_pids=()
  local pid

  if [[ -f "${pid_file}" ]]; then
    while IFS= read -r pid; do
      if [[ -n "${pid}" ]] && pid_belongs_to_service "${service}" "${pid}"; then
        pids+=("${pid}")
      fi
    done < "${pid_file}"
  fi

  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && pids+=("${pid}")
  done < <(discover_service_pids "${service}")

  if ((${#pids[@]} == 0)); then
    rm -f "${pid_file}"
    echo "[${service}] no historical process found"
    return 0
  fi

  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && unique_pids+=("${pid}")
  done < <(printf '%s\n' "${pids[@]}" | awk '!seen[$0]++')
  pids=("${unique_pids[@]}")

  echo "[${service}] stopping historical process(es): ${pids[*]}"

  for pid in "${pids[@]}"; do
    kill_tree_once TERM "${pid}"
  done

  for pid in "${pids[@]}"; do
    if ! wait_for_exit "${pid}"; then
      echo "[${service}] process ${pid} did not stop within ${STOP_TIMEOUT}s; sending KILL"
      kill_tree_once KILL "${pid}"
    fi
  done

  rm -f "${pid_file}"
}

start_service() {
  local service="$1"
  local log_file="${LOG_DIR}/${service}.log"
  local pid_file="${LOG_DIR}/${service}.pid"
  local pid

  {
    printf '\n===== %s starting make %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${service}"
  } >> "${log_file}"

  nohup bash -lc '
    set -e
    cd "$1"
    source .venv/bin/activate
    exec make "$2"
  ' _ "${ROOT_DIR}" "${service}" >> "${log_file}" 2>&1 &

  pid="$!"
  printf '%s\n' "${pid}" > "${pid_file}"
  echo "[${service}] started pid=${pid}, log=${log_file}"
}

main() {
  local service

  if (($# > 0)); then
    SERVICES=("$@")
  fi

  for service in "${SERVICES[@]}"; do
    if ! is_known_service "${service}"; then
      echo "Unknown service: ${service}. Expected one of: inference server frontend" >&2
      exit 1
    fi
  done

  for service in "${SERVICES[@]}"; do
    stop_service "${service}"
  done

  for service in "${SERVICES[@]}"; do
    start_service "${service}"
  done
}

main "$@"
