#!/usr/bin/env bash
set -Eeuo pipefail

: "${MINIO_ROOT_USER:?Set MINIO_ROOT_USER as a Hugging Face Space secret}"
: "${MINIO_ROOT_PASSWORD:?Set MINIO_ROOT_PASSWORD as a Hugging Face Space secret}"

DATA_DIR="${DATA_DIR:-/data}"
LIBREFS_API_ADDR="${LIBREFS_API_ADDR:-:9000}"
LIBREFS_CONSOLE_ADDR="${LIBREFS_CONSOLE_ADDR:-:9001}"
NGINX_CONF="${NGINX_CONF:-/etc/nginx/nginx.conf}"
OPS_HOST="${OPS_HOST:-127.0.0.1}"
OPS_PORT="${OPS_PORT:-8081}"
OPS_TOKEN="${OPS_TOKEN:-librefs_ops_demo_token}"
ADMIN_ENABLED="${ADMIN_ENABLED:-false}"
ADMIN_HOST="${ADMIN_HOST:-127.0.0.1}"
ADMIN_PORT="${ADMIN_PORT:-8082}"
ADMIN_AUDIT_LOG="${ADMIN_AUDIT_LOG:-${DATA_DIR%/}/logs/admin-audit.jsonl}"

export DATA_DIR
export LIBREFS_API_ADDR
export LIBREFS_CONSOLE_ADDR
export NGINX_CONF
export OPS_HOST
export OPS_PORT
export OPS_TOKEN
export ADMIN_ENABLED
export ADMIN_HOST
export ADMIN_PORT
export ADMIN_AUDIT_LOG

if [[ -n "${PUBLIC_BASE_URL:-}" ]]; then
  public_base="${PUBLIC_BASE_URL%/}"
elif [[ -n "${SPACE_HOST:-}" ]]; then
  public_base="https://${SPACE_HOST}"
else
  public_base="http://localhost:7860"
fi

export MINIO_SERVER_URL="${MINIO_SERVER_URL:-$public_base}"
export MINIO_SERVER_URL="${MINIO_SERVER_URL%/}"
case "$MINIO_SERVER_URL" in
  http://*|https://*) ;;
  *)
    echo "MINIO_SERVER_URL must start with http:// or https://: $MINIO_SERVER_URL" >&2
    exit 1
    ;;
esac

export MINIO_BROWSER_REDIRECT_URL="${MINIO_BROWSER_REDIRECT_URL:-${MINIO_SERVER_URL}/console/}"
if [[ "$MINIO_BROWSER_REDIRECT_URL" != */ ]]; then
  export MINIO_BROWSER_REDIRECT_URL="${MINIO_BROWSER_REDIRECT_URL}/"
fi
if [[ "$MINIO_BROWSER_REDIRECT_URL" != */console/ ]]; then
  echo "MINIO_BROWSER_REDIRECT_URL must end with /console/: $MINIO_BROWSER_REDIRECT_URL" >&2
  exit 1
fi

mkdir -p \
  "$DATA_DIR" \
  "${DATA_DIR%/}/logs" \
  /tmp/nginx/client_body \
  /tmp/nginx/proxy \
  /tmp/nginx/fastcgi \
  /tmp/nginx/uwsgi \
  /tmp/nginx/scgi

nginx -t -c "$NGINX_CONF"

librefs server "$DATA_DIR" \
  --address "$LIBREFS_API_ADDR" \
  --console-address "$LIBREFS_CONSOLE_ADDR" &
LIBREFS_PID=$!

python3 /usr/local/bin/librefs-ops-service.py &
OPS_PID=$!

python3 /usr/local/bin/librefs-admin-service.py &
ADMIN_PID=$!

nginx -c "$NGINX_CONF" -g "daemon off;" &
NGINX_PID=$!

shutdown() {
  trap - INT TERM
  kill "$LIBREFS_PID" "$OPS_PID" "$ADMIN_PID" "$NGINX_PID" 2>/dev/null || true
  wait "$LIBREFS_PID" "$OPS_PID" "$ADMIN_PID" "$NGINX_PID" 2>/dev/null || true
}

terminate() {
  shutdown
  exit 0
}

trap terminate INT TERM

process_active() {
  local pid="$1"
  local proc_pid proc_name proc_state rest

  if [[ -r "/proc/$pid/stat" ]]; then
    read -r proc_pid proc_name proc_state rest <"/proc/$pid/stat" || return 1
    [[ "$proc_state" != "Z" ]]
    return
  fi

  kill -0 "$pid" 2>/dev/null
}

status=0
processes=(
  "librefs:$LIBREFS_PID"
  "ops-service:$OPS_PID"
  "admin-service:$ADMIN_PID"
  "nginx:$NGINX_PID"
)

while true; do
  for process in "${processes[@]}"; do
    name="${process%%:*}"
    pid="${process#*:}"

    if ! process_active "$pid"; then
      if wait "$pid"; then
        status=1
        echo "$name exited unexpectedly with status 0" >&2
      else
        status=$?
        echo "$name exited with status $status" >&2
      fi
      break 2
    fi
  done

  sleep 1
done

shutdown
exit "$status"
