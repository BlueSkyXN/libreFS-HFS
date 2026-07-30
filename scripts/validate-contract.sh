#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE=0

usage() {
  cat <<'USAGE'
Usage: scripts/validate-contract.sh [--remote]

Validate the LibreFS HFS source-lane packaging contract without installing
project dependencies or building libreFS locally. Docker source builds are
intentionally skipped because they fetch the upstream repository over the
network.

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
  README.md docs Dockerfile hfs .dockerignore .gitignore .gitattributes AGENTS.md scripts .github hfs-dev.toml .env.example

check "shell script syntax" bash -n \
  hfs/start.sh \
  scripts/export-space-bundle.sh \
  scripts/verify-space-bundle.sh \
  scripts/smoke-s3-curl.sh \
  scripts/sample-hf-bucket-storage.sh

test -x scripts/export-space-bundle.sh
test -x scripts/verify-space-bundle.sh
test -x scripts/smoke-s3-curl.sh
test -x scripts/sample-hf-bucket-storage.sh

check "Python service syntax without bytecode" python3 -B -c '
import sys
from pathlib import Path

for source_path in sys.argv[1:]:
    compile(Path(source_path).read_text(encoding="utf-8"), source_path, "exec")
' hfs/ops_service.py hfs/admin_service.py scripts/presign-s3-request.py

check "README front matter" require_pattern README.md '^sdk: docker$' 'README.md must keep sdk: docker'
require_pattern README.md '^app_port: 7860$' 'README.md must keep app_port: 7860'
require_pattern README.md '^license: agpl-3.0$' 'README.md must keep license: agpl-3.0'

check "HFS v2 semantic registry" test -f hfs-dev.toml
test -f hfs-dev.candidate.toml
require_pattern hfs-dev.toml '^standard = "2\.1"$' 'manifest must use HFS standard 2.1'
require_pattern hfs-dev.candidate.toml '^standard = "2\.1"$' 'candidate manifest must use HFS standard 2.1'
require_pattern hfs-dev.toml '^project = "librefs-hfs"$' 'manifest must declare the wrapper project'
require_pattern hfs-dev.toml '^space = "BlueSkyXN/libreFS-HFS"$' 'manifest must declare the target Space'
require_pattern hfs-dev.candidate.toml '^space = "BlueSkyXN/libreFS-HFS-v2-candidate"$' 'candidate manifest must declare the private candidate Space'
require_pattern hfs-dev.toml '^project_class = "preview"$' 'canonical manifest must classify the project as preview'
require_pattern hfs-dev.toml '^target_role = "primary"$' 'canonical manifest must declare the primary target role'
require_pattern hfs-dev.toml '^env_file = "\.env"$' 'canonical manifest must declare the local plaintext ledger'
require_pattern hfs-dev.toml '^secret_files = \[\]$' 'canonical manifest must declare no structured secret files'
require_pattern hfs-dev.candidate.toml '^project_class = "preview"$' 'candidate manifest must classify the project as preview'
require_pattern hfs-dev.candidate.toml '^target_role = "candidate"$' 'candidate manifest must declare the candidate target role'
require_pattern hfs-dev.candidate.toml '^env_file = "local/hfs-targets/candidate\.env"$' 'candidate manifest must use an isolated local plaintext ledger'
require_pattern hfs-dev.candidate.toml '^secret_files = \[\]$' 'candidate manifest must declare no structured secret files'
require_pattern hfs-dev.toml '^sovereignty = "port"$' 'libreFS-HFS must remain a port wrapper'
require_pattern hfs-dev.toml '^lane = "source"$' 'libreFS-HFS must remain in the source lane'
require_pattern hfs-dev.toml '^version_source = "commit"$' 'manifest must declare commit-based production provenance'
require_pattern hfs-dev.toml '^pattern = "A"$' 'libreFS-HFS must remain a Pattern A repository'
require_pattern hfs-dev.toml '^runtime_mode = "bundle-only-build"$' 'runtime must remain bundle-only build'
require_pattern hfs-dev.toml '^release_commit_env = "LIBREFS_COMMIT"$' 'registry must name the upstream release commit pin'
require_pattern hfs-dev.toml '^release_gate_env = "HFS_RELEASE_BUILD"$' 'registry must name the release gate'
require_pattern hfs-dev.toml '"MINIO_ROOT_PASSWORD"' 'registry must name required Space secrets without values'
require_pattern hfs-dev.toml '^optional_secrets = \[$' 'registry must separate disabled admin credentials as optional'
require_pattern hfs-dev.toml '"ADMIN_TOKEN"' 'registry must keep the disabled admin token registered'
require_pattern hfs-dev.toml '"HF_TOKEN"' 'registry must keep deployment controls local-only'
if grep -Eq '(hf_[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,})' hfs-dev.toml; then
  echo "Contract check failed: hfs-dev.toml must not contain a credential value" >&2
  exit 1
fi

check "local configuration ledger boundary" test -f .env.example
for ignored_path in .env .env.local local/ BUILD_SOURCE.json; do
  if ! git check-ignore --quiet --no-index -- "$ignored_path"; then
    echo "Contract check failed: $ignored_path must be ignored locally" >&2
    exit 1
  fi
done
require_pattern .dockerignore '^\.env\.\*$' 'Docker context must exclude .env.*'
require_pattern .dockerignore '^local$' 'Docker context must exclude local material'
require_pattern .dockerignore '^__pycache__$' 'Docker context must exclude Python caches'

check "Dockerfile source provenance contract" require_pattern Dockerfile '^FROM ubuntu:\$\{UBUNTU_VERSION\} AS builder$' 'builder must stay on Ubuntu'
require_pattern Dockerfile '^FROM ubuntu:\$\{UBUNTU_VERSION\}$' 'runtime must stay on Ubuntu'
require_pattern Dockerfile 'git remote add origin https://github\.com/libreFS/libreFS\.git' 'build must fetch libreFS upstream source'
require_pattern Dockerfile 'HFS_RELEASE_BUILD' 'Dockerfile must distinguish a release source build'
require_pattern Dockerfile 'Bundle-only builds require LIBREFS_COMMIT to be a 40-character lowercase commit SHA' 'bundle build must reject a mutable upstream source'
require_pattern Dockerfile 'Bundle provenance LIBREFS commit does not match the Docker build input' 'bundle build must bind its source evidence to the Docker input'
require_pattern Dockerfile 'git fetch --depth 1 origin "\$\{LIBREFS_COMMIT\}"' 'release builds must fetch the pinned libreFS commit directly'
require_pattern Dockerfile 'git checkout --detach "\$\{LIBREFS_COMMIT\}"' 'release builds must checkout the pinned libreFS commit'
require_pattern Dockerfile 'test "\$\(git rev-parse HEAD\)" = "\$\{LIBREFS_COMMIT\}"' 'release builds must verify the upstream checkout'
require_pattern Dockerfile 'COPY --chmod=0444 BUILD_SOURCE\.json /usr/share/librefs-hfs/BUILD_SOURCE\.json' 'runtime must retain immutable wrapper source evidence'
require_pattern Dockerfile 'COPY --chmod=0444 SHA256SUMS /usr/share/librefs-hfs/SHA256SUMS' 'runtime must retain wrapper source checksums'
require_pattern Dockerfile 'stat -c %a /usr/share/librefs-hfs/BUILD_SOURCE.json' 'runtime image must verify provenance file modes explicitly'
require_pattern Dockerfile '^EXPOSE 7860$' 'container must expose only the HF app port'
require_pattern Dockerfile 'http://127\.0\.0\.1:7860/minio/health/ready' 'healthcheck must use the public Nginx port'
if grep -Eq '^\s*COPY\s+\.\s+' Dockerfile; then
  echo "Contract check failed: Dockerfile must not COPY the complete repository" >&2
  exit 1
fi

check "start.sh provenance and runtime contract" require_pattern hfs/start.sh 'MINIO_ROOT_USER' 'start.sh must require MINIO_ROOT_USER'
require_pattern hfs/start.sh 'MINIO_ROOT_PASSWORD' 'start.sh must require MINIO_ROOT_PASSWORD'
require_pattern hfs/start.sh '^HFS_BUILD_SOURCE_PATH="/usr/share/librefs-hfs/BUILD_SOURCE\.json"$' 'start.sh must use the fixed image source evidence path'
require_pattern hfs/start.sh '^HFS_BUILD_CHECKSUMS_PATH="/usr/share/librefs-hfs/SHA256SUMS"$' 'start.sh must use the fixed image checksum path'
if grep -Eq 'HFS_BUILD_(SOURCE|CHECKSUMS)_PATH="\$\{' hfs/start.sh; then
  echo "Contract check failed: runtime settings must not redirect immutable source evidence" >&2
  exit 1
fi
require_pattern hfs/start.sh 'Immutable wrapper source evidence checksum does not match' 'start.sh must fail closed on mismatched source evidence'
require_pattern hfs/start.sh 'checksums\[name\] = digest' 'start.sh must index SHA256SUMS by filename'
require_pattern hfs/start.sh 'Immutable wrapper source evidence does not satisfy the HFS source contract' 'start.sh must fail closed on invalid source evidence'
require_pattern hfs/start.sh 'Bundle-only runtime requires LIBREFS_COMMIT' 'bundle runtime must fail closed without an immutable upstream pin'
require_pattern hfs/start.sh 'librefs_source_commit' 'runtime must bind wrapper and libreFS source commits together'
require_pattern hfs/start.sh 'PUBLIC_BASE_URL' 'start.sh must honor PUBLIC_BASE_URL'
require_pattern hfs/start.sh 'SPACE_HOST' 'start.sh must derive from SPACE_HOST'
require_pattern hfs/start.sh 'MINIO_BROWSER_REDIRECT_URL.*console/' 'Console redirect URL must include /console/'
require_pattern hfs/start.sh 'nginx -t -c "\$NGINX_CONF"' 'start.sh must validate Nginx config before starting'
require_pattern hfs/start.sh 'ADMIN_ENABLED.*false' 'admin surface must default to disabled'

check "source bundle verifier fixture" bash -c '
  set -Eeuo pipefail
  tmp_dir="$(mktemp -d)"
  trap "rm -rf \"$tmp_dir\"" EXIT
  bundle="$tmp_dir/bundle"
  mkdir -p "$bundle/hfs"
  cp README.md Dockerfile LICENSE hfs-dev.toml .dockerignore .gitattributes "$bundle/"
  cp hfs/start.sh hfs/nginx.conf hfs/ops_service.py hfs/admin_service.py "$bundle/hfs/"
  python3 - "$bundle/BUILD_SOURCE.json" <<"PY"
import json
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "schema_version": 1,
    "source_kind": "commit",
    "source_commit": "0123456789abcdef0123456789abcdef01234567",
    "librefs_source_commit": "89abcdef0123456789abcdef0123456789abcdef",
    "source_repository": "https://github.com/BlueSkyXN/libreFS-HFS.git",
    "upstream_source_ref_env": "LIBREFS_COMMIT",
    "generated_at": "2026-07-26T00:00:00Z",
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
  (
    cd "$bundle"
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum README.md Dockerfile LICENSE hfs-dev.toml .dockerignore .gitattributes hfs/start.sh hfs/nginx.conf hfs/ops_service.py hfs/admin_service.py BUILD_SOURCE.json > SHA256SUMS
    else
      shasum -a 256 README.md Dockerfile LICENSE hfs-dev.toml .dockerignore .gitattributes hfs/start.sh hfs/nginx.conf hfs/ops_service.py hfs/admin_service.py BUILD_SOURCE.json > SHA256SUMS
    fi
  )
  scripts/verify-space-bundle.sh --bundle "$bundle"
  printf "package product\n" > "$bundle/librefs-product-source.go"
  if scripts/verify-space-bundle.sh --bundle "$bundle"; then
    echo "Contract check failed: verifier accepted an unallowlisted product source file" >&2
    exit 1
  fi
  rm -f "$bundle/librefs-product-source.go"
  printf "\n" >> "$bundle/BUILD_SOURCE.json"
  if scripts/verify-space-bundle.sh --bundle "$bundle"; then
    echo "Contract check failed: verifier accepted tampered source evidence" >&2
    exit 1
  fi
'

check "S3 smoke script contract" require_pattern scripts/smoke-s3-curl.sh '--aws-sigv4' 'S3 smoke test must use curl SigV4 support'
require_pattern scripts/smoke-s3-curl.sh 'presign-s3-request\.py' 'private candidate S3 smoke must use query signing'
require_pattern scripts/smoke-s3-curl.sh 'Authorization: Bearer' 'private candidate S3 smoke must authenticate to the HF gateway'
require_pattern scripts/smoke-s3-curl.sh 'Refusing to use bucket' 'S3 smoke test must refuse existing buckets'

check "storage sampler script contract" test -f scripts/sample-hf-bucket-storage.sh
require_pattern scripts/sample-hf-bucket-storage.sh '^EXPECTED_HF_HUB_VERSION="1\.5\.0"$' 'storage sampler must pin huggingface_hub 1.5.0'
require_pattern scripts/sample-hf-bucket-storage.sh '^EXPECTED_CLICK_VERSION="8\.3\.3"$' 'storage sampler must pin the module CLI click runtime'
require_pattern scripts/sample-hf-bucket-storage.sh 'HfApi\(\)\.bucket_info\(sys\.argv\[1\]\)' 'storage sampler must use structured HfApi bucket accounting'
require_pattern scripts/sample-hf-bucket-storage.sh 'python3 -m huggingface_hub\.cli\.hf buckets list' 'storage sampler must use the pinned module CLI for the visible tree'
require_pattern scripts/sample-hf-bucket-storage.sh '"\$BUCKET" --recursive --format json' 'storage sampler must request recursive JSON visible-tree output'
require_pattern scripts/sample-hf-bucket-storage.sh 'OPS_TOKEN' 'storage sampler must use OPS_TOKEN only for optional ops endpoint access'
if grep -Eq '(^|[^[:alnum:]_.-])hf[[:space:]]+buckets[[:space:]]+(info|list)([[:space:]]|$)' scripts/sample-hf-bucket-storage.sh; then
  echo "Contract check failed: storage sampler must not use the unpinned hf console entrypoint" >&2
  exit 1
fi
if grep -Eq 'buckets[[:space:]]+info[^[:cntrl:]]*--(json|format)' scripts/sample-hf-bucket-storage.sh; then
  echo "Contract check failed: storage sampler must not claim buckets info has JSON output" >&2
  exit 1
fi

check "nginx routing contract" require_pattern hfs/nginx.conf 'listen 7860;' 'Nginx must listen on HF app port 7860'
require_pattern hfs/nginx.conf 'location = /console' 'Nginx must normalize /console'
require_pattern hfs/nginx.conf 'location = /_ops' 'Nginx must normalize /_ops'
require_pattern hfs/nginx.conf 'proxy_pass http://127\.0\.0\.1:8081/;' 'Nginx must proxy ops service'
require_pattern hfs/nginx.conf 'location = /_admin' 'Nginx must normalize /_admin'
require_pattern hfs/nginx.conf 'proxy_pass http://127\.0\.0\.1:8082/;' 'Nginx must proxy admin service'
require_pattern hfs/nginx.conf 'proxy_pass http://127\.0\.0\.1:9001/;' 'Console proxy_pass must strip /console/ prefix'
require_pattern hfs/nginx.conf 'proxy_pass http://127\.0\.0\.1:9000;' 'S3 API must stay at the root path'
require_pattern hfs/nginx.conf 'proxy_set_header X-HF-Authorization "";' 'S3 proxy must strip the private Space gateway header before SigV4 verification'
require_pattern hfs/nginx.conf 'proxy_set_header X-Amzn-Trace-Id "";' 'S3 proxy must strip platform trace headers added after SigV4 signing'
require_pattern hfs/nginx.conf 'proxy_set_header Authorization \$s3_authorization;' 'S3 proxy must strip only HF Bearer auth while preserving header SigV4'
require_pattern hfs/nginx.conf 'proxy_hide_header X-Frame-Options;' 'Console proxy must hide upstream X-Frame-Options'

check "ops/admin service contract" require_pattern hfs/ops_service.py 'SECRET_KEYS' 'ops service must summarize secret presence only'
require_pattern hfs/ops_service.py 'secret values are intentionally omitted' 'ops config must not return raw secrets'
require_pattern hfs/ops_service.py 'def wrapper_source_payload' 'ops version must expose safe source provenance'
require_pattern hfs/ops_service.py 'path in \{"/", ""\}.*query_token.*wants_html' 'query token must only bootstrap browser login at /_ops/'
require_pattern hfs/admin_service.py 'ADMIN_ENABLED.*false' 'admin service must default to disabled'
require_pattern hfs/admin_service.py 'confirm=true is required' 'admin write action must require explicit confirm'

if grep -Eq 'access_log /dev/stdout;' hfs/nginx.conf; then
  echo "Contract check failed: Nginx access logs must not use the default query-string format" >&2
  exit 1
fi

check "manual deployment workflow" test -f .github/workflows/deploy-hf-space.yml
require_pattern .github/workflows/deploy-hf-space.yml 'workflow_dispatch:' 'Space deployment must be manually dispatched'
require_pattern .github/workflows/deploy-hf-space.yml 'confirm_release' 'Space deployment must require explicit confirmation'
require_pattern .github/workflows/deploy-hf-space.yml 'options: \[candidate, production\]' 'Space deployment must use fixed manifest-owned targets'
require_pattern .github/workflows/deploy-hf-space.yml 'hfs-dev\.candidate\.toml' 'Space deployment must select the candidate manifest explicitly'
require_pattern .github/workflows/deploy-hf-space.yml 'FORMAL_SPACE: BlueSkyXN/libreFS-HFS' 'production deployment must pin the canonical Space id'
require_pattern .github/workflows/deploy-hf-space.yml 'target Space must be private before wrapper upload' 'candidate and production targets must already be private'
require_pattern .github/workflows/deploy-hf-space.yml 'scripts/export-space-bundle\.sh' 'workflow must export the wrapper boundary'
require_pattern .github/workflows/deploy-hf-space.yml 'scripts/verify-space-bundle\.sh' 'workflow must verify the wrapper boundary'
require_pattern .github/workflows/deploy-hf-space.yml 'Refuse a Space repository outside the wrapper boundary' 'workflow must fail closed on legacy Space files'
require_pattern .github/workflows/deploy-hf-space.yml 'huggingface_hub\.cli\.hf download' 'workflow must read back the Space repository through the pinned module CLI'
require_pattern .github/workflows/deploy-hf-space.yml 'huggingface_hub\.cli\.hf upload' 'workflow must upload the Space repository through the pinned module CLI'
require_pattern .github/workflows/deploy-hf-space.yml 'HF_CLI_VERSION: "1\.5\.0"' 'workflow must pin huggingface_hub 1.5.0'
require_pattern .github/workflows/deploy-hf-space.yml 'HF_CLI_CLICK_VERSION: "8\.3\.3"' 'workflow must pin the module CLI click runtime'
require_pattern .github/workflows/deploy-hf-space.yml 'huggingface_hub==\$\{HF_CLI_VERSION\}' 'workflow must install the pinned huggingface_hub version'
require_pattern .github/workflows/deploy-hf-space.yml 'click==\$\{HF_CLI_CLICK_VERSION\}' 'workflow must install the pinned click version'
require_pattern .github/workflows/deploy-hf-space.yml 'get_space_variables' 'workflow must read Space Variables through HfApi because the pinned CLI has no Settings subcommands'
require_pattern .github/workflows/deploy-hf-space.yml 'space_info' 'workflow must read Space metadata through HfApi'
if grep -Eq '(^|[^[:alnum:]_.-])hf[[:space:]]+(download|upload|spaces)([[:space:]]|$)' .github/workflows/deploy-hf-space.yml; then
  echo "Contract check failed: deployment workflow must invoke the pinned HF CLI through its Python module entrypoint" >&2
  exit 1
fi
require_pattern .github/workflows/deploy-hf-space.yml 'sha256sum -c SHA256SUMS' 'workflow must verify complete uploaded wrapper bytes'
if grep -Eq 'git push|--force|--delete|\|\| true' .github/workflows/deploy-hf-space.yml; then
  echo "Contract check failed: deployment workflow must not force-push, delete, or bypass a failed check" >&2
  exit 1
fi

check "strict production pre-upload workflow gate" python3 - <<'PY'
from pathlib import Path

workflow = Path(".github/workflows/deploy-hf-space.yml").read_text(encoding="utf-8")
upload_offset = workflow.index('python3 -m huggingface_hub.cli.hf upload "$SPACE_ID"')
required_before_upload = (
    'if os.environ["HFS_TARGET"] == "production" and os.environ["SPACE_ID"] != os.environ["FORMAL_SPACE"]:',
    'if info.private is not True:',
    '[[ "$GITHUB_REF" == "refs/heads/main" ]]',
    'git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main',
    '[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]',
    '[[ "$(git rev-parse origin/main)" == "$GITHUB_SHA" ]]',
)
for fragment in required_before_upload:
    offset = workflow.find(fragment)
    if offset < 0 or offset > upload_offset:
        raise SystemExit(f"production pre-upload gate missing or late: {fragment}")
if 'os.environ["HFS_TARGET"] == "candidate" and not info.private' in workflow:
    raise SystemExit("production Space privacy must not be skipped")
if '[[ "$LIBREFS_COMMIT" == "$GITHUB_SHA" ]]' in workflow:
    raise SystemExit("upstream LIBREFS_COMMIT must remain independent from the wrapper main commit")
PY

check "license contract" require_pattern LICENSE 'GNU AFFERO GENERAL PUBLIC LICENSE' 'LICENSE must remain AGPL-3.0'

if command -v nginx >/dev/null 2>&1; then
  mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi
  check "nginx syntax" nginx -t -c "$ROOT_DIR/hfs/nginx.conf"
else
  printf '==> nginx syntax\n'
  echo "skip: nginx is not installed locally"
fi

printf '==> Docker source build\n'
echo "skip: source wrapper Docker build fetches libreFS from GitHub and is not run locally"

if [[ "$REMOTE" -eq 1 ]]; then
  check "remote health endpoint" curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready \
    -o /dev/null \
    -w 'health_http=%{http_code}\n'
fi

echo "All selected contract checks passed."
