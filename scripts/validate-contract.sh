#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE=0

usage() {
  cat <<'USAGE'
Usage: scripts/validate-contract.sh [--remote]

Validate the LibreFS HFS packaging contract without installing project
dependencies or building libreFS locally.

Options:
  --remote    Also check the public Hugging Face Space health endpoint.
  -h, --help  Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      REMOTE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

check() {
  local label="$1"
  shift

  printf '==> %s\n' "$label"
  "$@"
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if ! grep -Eq -- "$pattern" "$file"; then
    echo "Contract check failed: $message" >&2
    echo "Missing pattern in $file: $pattern" >&2
    exit 1
  fi
}

check "whitespace and conflict-marker check" git diff --check -- \
  README.md docs Dockerfile hfs .dockerignore .gitignore .gitattributes AGENTS.md scripts

check "shell script syntax" bash -n hfs/start.sh
bash -n scripts/smoke-s3-curl.sh
test -x scripts/smoke-s3-curl.sh

check "Python service syntax" python3 -m py_compile hfs/ops_service.py hfs/admin_service.py

check "README front matter" require_pattern README.md '^sdk: docker$' 'README.md must keep sdk: docker'
require_pattern README.md '^app_port: 7860$' 'README.md must keep app_port: 7860'
require_pattern README.md '^license: agpl-3.0$' 'README.md must keep license: agpl-3.0'

check "HFS alignment manifest" test -f hfs-dev.toml
require_pattern hfs-dev.toml '^schema_version = 2$' 'alignment manifest must use structured v2 release pins'
require_pattern hfs-dev.toml '^standard = "hfs-dev"$' 'alignment manifest must identify the hfs-dev standard'
require_pattern hfs-dev.toml '^pattern = "A"$' 'libreFS-HFS must remain a Pattern A port repository'
require_pattern hfs-dev.toml '^runtime_mode = "source-fetch"$' 'libreFS-HFS build fetches upstream libreFS source'
require_pattern hfs-dev.toml '^space_root_mode = "repo-root"$' 'Pattern A Space root must remain the repository root'
require_pattern hfs-dev.toml '^release_pin_required = true$' 'release builds must expose immutable pin surfaces'
require_pattern hfs-dev.toml 'hfs/start\.sh' 'runtime glue manifest must include hfs/start.sh'
require_pattern hfs-dev.toml '^\[\[release_pins\]\]$' 'release pins must use structured v2 tables'
require_pattern hfs-dev.toml '^name = "LIBREFS_COMMIT"$' 'release pin must include LIBREFS_COMMIT'
require_pattern hfs-dev.toml '^required_for_release = true$' 'LIBREFS_COMMIT must be required for release builds'
require_pattern hfs-dev.toml '^release_requires_commit_sha = true$' 'source-fetch release pin must require an upstream commit SHA'
require_pattern hfs-dev.toml '^name = "LIBREFS_REF"$' 'development mutable source must be documented separately from the release pin'
require_pattern hfs-dev.toml 'GO_TARBALL_SHA256' 'Go tarball checksum hardening backlog must remain visible'
require_pattern hfs-dev.toml 'UBUNTU_BASE_IMAGE=.*@sha256' 'Ubuntu base image digest hardening backlog must remain visible'

check "Dockerfile contract" require_pattern Dockerfile '^FROM ubuntu:\$\{UBUNTU_VERSION\} AS builder$' 'builder must stay on Ubuntu'
require_pattern Dockerfile '^FROM ubuntu:\$\{UBUNTU_VERSION\}$' 'runtime must stay on Ubuntu'
require_pattern Dockerfile 'git remote add origin https://github\.com/libreFS/libreFS\.git' 'build must fetch libreFS upstream source'
require_pattern Dockerfile 'python3' 'runtime must include Python for ops/admin services'
require_pattern Dockerfile 'librefs-ops-service\.py' 'runtime must copy ops service'
require_pattern Dockerfile 'librefs-admin-service\.py' 'runtime must copy admin service'
require_pattern Dockerfile '^EXPOSE 7860$' 'container must expose only the HF app port'
require_pattern Dockerfile 'http://127\.0\.0\.1:7860/minio/health/ready' 'healthcheck must use the public Nginx port'

check "start.sh contract" require_pattern hfs/start.sh 'MINIO_ROOT_USER' 'start.sh must require MINIO_ROOT_USER'
require_pattern hfs/start.sh 'MINIO_ROOT_PASSWORD' 'start.sh must require MINIO_ROOT_PASSWORD'
require_pattern hfs/start.sh 'PUBLIC_BASE_URL' 'start.sh must honor PUBLIC_BASE_URL'
require_pattern hfs/start.sh 'SPACE_HOST' 'start.sh must derive from SPACE_HOST'
require_pattern hfs/start.sh 'MINIO_BROWSER_REDIRECT_URL.*console/' 'Console redirect URL must include /console/'
require_pattern hfs/start.sh 'MINIO_BROWSER_REDIRECT_URL must end with /console/' 'Console redirect override must be validated'
require_pattern hfs/start.sh 'MINIO_SERVER_URL must start with http:// or https://' 'S3 public URL must include a scheme'
require_pattern hfs/start.sh 'nginx -t -c "\$NGINX_CONF"' 'start.sh must validate Nginx config before starting'
require_pattern hfs/start.sh 'librefs-ops-service\.py' 'start.sh must start ops service'
require_pattern hfs/start.sh 'librefs-admin-service\.py' 'start.sh must start admin service'
require_pattern hfs/start.sh 'ADMIN_ENABLED.*false' 'admin surface must default to disabled'

check "S3 smoke script contract" require_pattern scripts/smoke-s3-curl.sh '--aws-sigv4' 'S3 smoke test must use curl SigV4 support'
require_pattern scripts/smoke-s3-curl.sh 'Refusing to use bucket' 'S3 smoke test must refuse existing buckets'

check "nginx routing contract" require_pattern hfs/nginx.conf 'listen 7860;' 'Nginx must listen on HF app port 7860'
require_pattern hfs/nginx.conf 'location = /console' 'Nginx must normalize /console'
require_pattern hfs/nginx.conf 'location = /_ops' 'Nginx must normalize /_ops'
require_pattern hfs/nginx.conf 'proxy_pass http://127\.0\.0\.1:8081/;' 'Nginx must proxy ops service'
require_pattern hfs/nginx.conf 'location = /_admin' 'Nginx must normalize /_admin'
require_pattern hfs/nginx.conf 'proxy_pass http://127\.0\.0\.1:8082/;' 'Nginx must proxy admin service'
require_pattern hfs/nginx.conf 'proxy_pass http://127\.0\.0\.1:9001/;' 'Console proxy_pass must strip /console/ prefix'
require_pattern hfs/nginx.conf 'proxy_pass http://127\.0\.0\.1:9000;' 'S3 API must stay at the root path'
require_pattern hfs/nginx.conf 'proxy_hide_header X-Frame-Options;' 'Console proxy must hide upstream X-Frame-Options'
require_pattern hfs/nginx.conf 'frame-ancestors.*huggingface\.co' 'Console CSP must allow Hugging Face iframe embedding'

check "ops/admin service contract" require_pattern hfs/ops_service.py 'SECRET_KEYS' 'ops service must summarize secret presence only'
require_pattern hfs/ops_service.py 'secret values are intentionally omitted' 'ops config must not return raw secrets'
require_pattern hfs/ops_service.py 'path in \{"/", ""\}.*query_token.*wants_html' 'query token must only bootstrap browser login at /_ops/'
require_pattern hfs/admin_service.py 'ADMIN_ENABLED.*false' 'admin service must default to disabled'
require_pattern hfs/admin_service.py 'confirm=true is required' 'admin write action must require explicit confirm'

if sed -n '/def request_tokens/,/def request_token/p' hfs/ops_service.py | grep -q 'query_token'; then
  echo "Contract check failed: query token must not be accepted as script/API authentication" >&2
  exit 1
fi

if grep -Eq 'listen +(9000|9001);' hfs/nginx.conf; then
  echo "Contract check failed: hfs/nginx.conf must not expose internal ports 9000/9001" >&2
  exit 1
fi

check "license contract" require_pattern LICENSE 'GNU AFFERO GENERAL PUBLIC LICENSE' 'LICENSE must remain AGPL-3.0'

if command -v nginx >/dev/null 2>&1; then
  mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi
  check "nginx syntax" nginx -t -c "$ROOT_DIR/hfs/nginx.conf"
else
  printf '==> nginx syntax\n'
  echo "skip: nginx is not installed locally"
fi

if [[ "$REMOTE" -eq 1 ]]; then
  check "remote health endpoint" curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready \
    -o /dev/null \
    -w 'health_http=%{http_code}\n'
fi

echo "All selected contract checks passed."
