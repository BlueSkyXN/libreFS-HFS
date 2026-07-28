#!/usr/bin/env bash
set -Eeuo pipefail

BUNDLE_DIR=""

usage() {
  cat <<'USAGE'
Usage: scripts/verify-space-bundle.sh --bundle <directory>

Verify the allowlisted LibreFS HFS source wrapper bundle before it is uploaded
to a Space. The verifier rejects product source, .env files, local material,
caches, generated data, credentials, symlinks, and unrecorded files.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      BUNDLE_DIR="${2:-}"
      shift 2
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

if [[ -z "$BUNDLE_DIR" || ! -d "$BUNDLE_DIR" ]]; then
  echo "--bundle must name an existing directory." >&2
  exit 2
fi

required_paths=(
  README.md
  Dockerfile
  LICENSE
  hfs-dev.toml
  .dockerignore
  .gitattributes
  hfs/start.sh
  hfs/nginx.conf
  hfs/ops_service.py
  hfs/admin_service.py
  BUILD_SOURCE.json
  SHA256SUMS
)

for path in "${required_paths[@]}"; do
  if [[ ! -f "$BUNDLE_DIR/$path" ]]; then
    echo "Bundle verification failed: missing required file $path" >&2
    exit 1
  fi
done

if find "$BUNDLE_DIR" -type l -print -quit | grep -q .; then
  echo "Bundle verification failed: symlinks are not allowed." >&2
  exit 1
fi

actual_paths="$(cd "$BUNDLE_DIR" && find . -type f -print | LC_ALL=C sort | cut -c3-)"
expected_paths="$(printf '%s\n' "${required_paths[@]}" | LC_ALL=C sort)"
if [[ "$actual_paths" != "$expected_paths" ]]; then
  printf 'Bundle verification failed: unexpected or missing files.\nExpected:\n%s\nActual:\n%s\n' \
    "$expected_paths" "$actual_paths" >&2
  exit 1
fi

if grep -Eq '(^|/)(\.env(?:\..*)?|local|\.git|__pycache__|\.data|tmp|temp)(/|$)' <<<"$actual_paths"; then
  echo "Bundle verification failed: forbidden local, environment, cache, or data path." >&2
  exit 1
fi

if grep -Eq '^\s*COPY\s+\.\s+' "$BUNDLE_DIR/Dockerfile"; then
  echo "Bundle verification failed: Dockerfile must not use COPY . as a delivery input." >&2
  exit 1
fi

BUNDLE_DIR="$BUNDLE_DIR" python3 - <<'PY'
import hashlib
import json
import os
import re
import sys
from pathlib import Path

root = Path(os.environ["BUNDLE_DIR"])
expected = {
    "schema_version",
    "source_kind",
    "source_commit",
    "librefs_source_commit",
    "source_repository",
    "upstream_source_ref_env",
    "generated_at",
}
try:
    evidence = json.loads((root / "BUILD_SOURCE.json").read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    print(f"Bundle verification failed: invalid BUILD_SOURCE.json: {exc}", file=sys.stderr)
    raise SystemExit(1)

if set(evidence) != expected:
    print("Bundle verification failed: BUILD_SOURCE.json has an unexpected schema.", file=sys.stderr)
    raise SystemExit(1)
if evidence["schema_version"] != 1 or evidence["source_kind"] != "commit":
    print("Bundle verification failed: source evidence must identify schema 1 and an immutable commit.", file=sys.stderr)
    raise SystemExit(1)
if not re.fullmatch(r"[0-9a-f]{40}", str(evidence["source_commit"])):
    print("Bundle verification failed: source evidence does not contain a lowercase 40-character commit.", file=sys.stderr)
    raise SystemExit(1)
if not re.fullmatch(r"[0-9a-f]{40}", str(evidence["librefs_source_commit"])):
    print("Bundle verification failed: source evidence does not contain a lowercase 40-character libreFS commit.", file=sys.stderr)
    raise SystemExit(1)
if evidence["source_repository"] != "https://github.com/BlueSkyXN/libreFS-HFS.git":
    print("Bundle verification failed: source evidence names an unexpected repository.", file=sys.stderr)
    raise SystemExit(1)
if evidence["upstream_source_ref_env"] != "LIBREFS_COMMIT":
    print("Bundle verification failed: source evidence must identify LIBREFS_COMMIT.", file=sys.stderr)
    raise SystemExit(1)

checksums: dict[str, str] = {}
for line in (root / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
    match = re.fullmatch(r"([0-9a-f]{64})\s+\*?(.+)", line)
    if not match or ("/" in match.group(2) and match.group(2).startswith("../")):
        print("Bundle verification failed: malformed SHA256SUMS entry.", file=sys.stderr)
        raise SystemExit(1)
    if match.group(2) in checksums:
        print("Bundle verification failed: SHA256SUMS contains a duplicate entry.", file=sys.stderr)
        raise SystemExit(1)
    checksums[match.group(2)] = match.group(1)

expected_checksum_files = {path.name for path in []}
for path in root.rglob("*"):
    if not path.is_file() or path.name == "SHA256SUMS":
        continue
    relative = path.relative_to(root).as_posix()
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if checksums.get(relative) != digest:
        print(f"Bundle verification failed: checksum mismatch or omission for {relative}.", file=sys.stderr)
        raise SystemExit(1)
if set(checksums) != {path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file() and path.name != "SHA256SUMS"}:
    print("Bundle verification failed: SHA256SUMS must cover each bundle input exactly once.", file=sys.stderr)
    raise SystemExit(1)
PY

printf 'Bundle verification passed: %s\n' "$BUNDLE_DIR"
