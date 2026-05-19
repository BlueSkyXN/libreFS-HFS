#!/usr/bin/env bash
set -Eeuo pipefail

: "${MINIO_ROOT_USER:?Set MINIO_ROOT_USER as a Hugging Face Space secret}"
: "${MINIO_ROOT_PASSWORD:?Set MINIO_ROOT_PASSWORD as a Hugging Face Space secret}"

DATA_DIR="${DATA_DIR:-/data}"
LIBREFS_API_ADDR="${LIBREFS_API_ADDR:-:9000}"
LIBREFS_CONSOLE_ADDR="${LIBREFS_CONSOLE_ADDR:-:9001}"
NGINX_CONF="${NGINX_CONF:-/etc/nginx/nginx.conf}"

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

nginx -c "$NGINX_CONF" -g "daemon off;" &
NGINX_PID=$!

shutdown() {
  trap - INT TERM
  kill "$LIBREFS_PID" "$NGINX_PID" 2>/dev/null || true
  wait "$LIBREFS_PID" "$NGINX_PID" 2>/dev/null || true
}

terminate() {
  shutdown
  exit 0
}

wait_for_exit() {
  local name="$1"
  local pid="$2"
  local rc=0

  if wait "$pid"; then
    rc=0
  else
    rc=$?
  fi

  if [[ "$rc" -eq 0 ]]; then
    echo "$name exited unexpectedly with status 0" >&2
    status=1
  else
    echo "$name exited with status $rc" >&2
    status="$rc"
  fi
}

trap terminate INT TERM

status=0
while true; do
  if ! kill -0 "$LIBREFS_PID" 2>/dev/null; then
    wait_for_exit "librefs" "$LIBREFS_PID"
    break
  fi

  if ! kill -0 "$NGINX_PID" 2>/dev/null; then
    wait_for_exit "nginx" "$NGINX_PID"
    break
  fi

  sleep 1
done

shutdown
exit "$status"
