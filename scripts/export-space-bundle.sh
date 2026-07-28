#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_COMMIT=""
LIBREFS_SOURCE_COMMIT=""
OUTPUT_DIR=""
MANIFEST="hfs-dev.toml"

usage() {
  cat <<'USAGE'
Usage: scripts/export-space-bundle.sh --output <empty-directory> --librefs-source-commit <commit> [--source-commit <commit>] [--manifest <profile>]

Export the minimal LibreFS HFS source wrapper for a manual, confirmed Space
release. The exporter only accepts a clean checkout at the exact immutable
Git commit being exported. It writes BUILD_SOURCE.json and SHA256SUMS as
provenance evidence; neither file contains credentials or Space Settings.

Options:
  --output <dir>                  New or empty output directory for the bundle.
  --source-commit <sha>           Exact wrapper commit. Defaults to HEAD.
  --librefs-source-commit <sha>   Exact libreFS commit that Docker must compile.
  --manifest <profile>            hfs-dev.toml or hfs-dev.candidate.toml.
  -h, --help              Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --source-commit)
      SOURCE_COMMIT="${2:-}"
      shift 2
      ;;
    --librefs-source-commit)
      LIBREFS_SOURCE_COMMIT="${2:-}"
      shift 2
      ;;
    --manifest)
      MANIFEST="${2:-}"
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

case "$MANIFEST" in
  hfs-dev.toml|hfs-dev.candidate.toml) ;;
  *) echo "--manifest must be hfs-dev.toml or hfs-dev.candidate.toml." >&2; exit 2 ;;
esac

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "--output is required." >&2
  exit 2
fi

if ! [[ "$LIBREFS_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "--librefs-source-commit must be a 40-character lowercase Git SHA." >&2
  exit 2
fi

cd "$ROOT_DIR"
SOURCE_COMMIT="${SOURCE_COMMIT:-$(git rev-parse HEAD)}"

if ! [[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "--source-commit must be a 40-character lowercase Git SHA." >&2
  exit 2
fi

if [[ "$(git rev-parse HEAD)" != "$SOURCE_COMMIT" ]]; then
  echo "The export commit must be the current HEAD; checkout the intended immutable commit first." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "Refusing to export a dirty checkout. Commit or discard only the intended changes before release." >&2
  exit 1
fi

if [[ -e "$OUTPUT_DIR" ]]; then
  if [[ ! -d "$OUTPUT_DIR" || -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "--output must be a new or empty directory: $OUTPUT_DIR" >&2
    exit 1
  fi
else
  mkdir -p "$OUTPUT_DIR"
fi

bundle_paths=(
  README.md
  Dockerfile
  LICENSE
  "$MANIFEST"
  .dockerignore
  hfs/start.sh
  hfs/nginx.conf
  hfs/ops_service.py
  hfs/admin_service.py
)

for path in "${bundle_paths[@]}"; do
  git cat-file -e "${SOURCE_COMMIT}:${path}" 2>/dev/null || {
    echo "Required tracked wrapper file is missing from $SOURCE_COMMIT: $path" >&2
    exit 1
  }
done

git archive --format=tar "$SOURCE_COMMIT" -- "${bundle_paths[@]}" | tar -x -C "$OUTPUT_DIR"
if [[ "$MANIFEST" != "hfs-dev.toml" ]]; then
  mv "$OUTPUT_DIR/$MANIFEST" "$OUTPUT_DIR/hfs-dev.toml"
fi

SOURCE_COMMIT="$SOURCE_COMMIT" LIBREFS_SOURCE_COMMIT="$LIBREFS_SOURCE_COMMIT" OUTPUT_DIR="$OUTPUT_DIR" python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

output = Path(os.environ["OUTPUT_DIR"])
evidence = {
    "schema_version": 1,
    "source_kind": "commit",
    "source_commit": os.environ["SOURCE_COMMIT"],
    "librefs_source_commit": os.environ["LIBREFS_SOURCE_COMMIT"],
    "source_repository": "https://github.com/BlueSkyXN/libreFS-HFS.git",
    "upstream_source_ref_env": "LIBREFS_COMMIT",
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
(output / "BUILD_SOURCE.json").write_text(
    json.dumps(evidence, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

(
  cd "$OUTPUT_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum README.md Dockerfile LICENSE hfs-dev.toml .dockerignore \
      hfs/start.sh hfs/nginx.conf hfs/ops_service.py hfs/admin_service.py BUILD_SOURCE.json > SHA256SUMS
  else
    shasum -a 256 README.md Dockerfile LICENSE hfs-dev.toml .dockerignore \
      hfs/start.sh hfs/nginx.conf hfs/ops_service.py hfs/admin_service.py BUILD_SOURCE.json > SHA256SUMS
  fi
)

"$ROOT_DIR/scripts/verify-space-bundle.sh" --bundle "$OUTPUT_DIR"
printf 'Exported source bundle for wrapper commit %s: %s\n' "$SOURCE_COMMIT" "$OUTPUT_DIR"
