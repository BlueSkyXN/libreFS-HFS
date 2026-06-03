#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_BUCKET="BlueSkyXN/librefs-hfs-data"
BUCKET="${HF_BUCKET_ID:-$DEFAULT_BUCKET}"
OPS_URL="${OPS_URL:-}"
INTERVAL=0
COUNT=1

usage() {
  cat <<'USAGE'
Usage: scripts/sample-hf-bucket-storage.sh [options]

Sample Hugging Face Storage Bucket accounting and visible tree size.
The script is read-only and emits one JSON object per line.

Options:
  --bucket <bucket-id>  HF bucket id. Defaults to HF_BUCKET_ID or BlueSkyXN/librefs-hfs-data.
  --ops-url <url>       Optional ops base URL, for example https://host/_ops.
                        Requires OPS_TOKEN and calls <url>/storage?format=json.
  --interval <seconds>  Sleep interval between samples. Defaults to 0.
  --count <count>       Number of samples. Defaults to 1. Use 0 for continuous sampling.
  -h, --help            Show this help.

Environment:
  HF_BUCKET_ID          Default bucket id override.
  OPS_URL               Optional ops base URL override.
  OPS_TOKEN             Token used only in the X-Ops-Token header when --ops-url is set.
USAGE
}

is_nonnegative_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)
      BUCKET="${2:-}"
      shift 2
      ;;
    --ops-url)
      OPS_URL="${2:-}"
      shift 2
      ;;
    --interval)
      INTERVAL="${2:-}"
      shift 2
      ;;
    --count)
      COUNT="${2:-}"
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

if [[ -z "$BUCKET" ]]; then
  echo "Bucket id must not be empty." >&2
  exit 2
fi

if ! is_nonnegative_int "$INTERVAL"; then
  echo "--interval must be a non-negative integer number of seconds." >&2
  exit 2
fi

if ! is_nonnegative_int "$COUNT"; then
  echo "--count must be a non-negative integer." >&2
  exit 2
fi

if [[ "$COUNT" == "0" && "$INTERVAL" == "0" ]]; then
  echo "--count 0 requires --interval greater than 0 to avoid a busy loop." >&2
  exit 2
fi

if ! command -v hf >/dev/null 2>&1; then
  echo "hf CLI is required." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required." >&2
  exit 1
fi

if [[ -n "$OPS_URL" ]]; then
  if [[ -z "${OPS_TOKEN:-}" ]]; then
    echo "OPS_TOKEN is required when --ops-url or OPS_URL is set." >&2
    exit 2
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required when --ops-url or OPS_URL is set." >&2
    exit 1
  fi
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ops_endpoint() {
  local base="${OPS_URL%/}"
  if [[ "$base" == */storage ]]; then
    printf '%s?format=json' "$base"
  else
    printf '%s/storage?format=json' "$base"
  fi
}

sample_once() {
  local info_json="$TMP_DIR/info.json"
  local list_json="$TMP_DIR/list.json"
  local ops_json="$TMP_DIR/ops.json"

  hf buckets info "$BUCKET" --json >"$info_json"
  hf buckets list "$BUCKET" -R --json >"$list_json"

  if [[ -n "$OPS_URL" ]]; then
    curl -fsS -H "X-Ops-Token: ${OPS_TOKEN}" "$(ops_endpoint)" >"$ops_json"
  else
    printf '{}\n' >"$ops_json"
  fi

  python3 - "$info_json" "$list_json" "$ops_json" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone


def read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = handle.read().strip()
    except OSError:
        return None
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def as_int(value):
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def first_present(mapping, keys):
    if not isinstance(mapping, dict):
        return None
    for key in keys:
        if key in mapping:
            return mapping[key]
    return None


def iter_items(document):
    if isinstance(document, list):
        return document
    if isinstance(document, dict):
        for key in ("items", "files", "entries", "objects", "paths", "siblings"):
            value = document.get(key)
            if isinstance(value, list):
                return value
    return []


def is_file_item(item):
    if not isinstance(item, dict):
        return False
    item_type = str(item.get("type", "file")).lower()
    if item_type in {"dir", "directory", "folder"}:
        return False
    if item.get("is_dir") is True or item.get("is_directory") is True:
        return False
    return True


def item_path(item):
    value = first_present(item, ("path", "name", "key", "rfilename", "filename"))
    return str(value) if value is not None else ""


info = read_json(sys.argv[1]) or {}
listing = read_json(sys.argv[2])
ops = read_json(sys.argv[3]) or {}

visible_sum = 0
visible_files = 0
largest = None

for item in iter_items(listing):
    if not is_file_item(item):
        continue
    size = as_int(first_present(item, ("size", "file_size", "bytes", "blob_size"))) or 0
    path = item_path(item)
    visible_sum += size
    visible_files += 1
    if largest is None or size > largest["size"]:
        largest = {"path": path, "size": size}

info_size = as_int(first_present(info, ("size", "total_size", "bytes")))
info_total_files = as_int(first_present(info, ("total_files", "totalFiles", "file_count", "files")))
ops_visible_sum = as_int(first_present(ops.get("visible_tree", {}), ("total_bytes",)))

output = {
    "timestamp_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "bucket": os.environ.get("HF_BUCKET_ID_EFFECTIVE", ""),
    "info_size": info_size,
    "info_total_files": info_total_files,
    "visible_sum": visible_sum,
    "visible_files": visible_files,
    "drift_bytes": (info_size - visible_sum) if info_size is not None else None,
    "ops_visible_sum": ops_visible_sum,
    "largest_visible_file": largest,
}
print(json.dumps(output, ensure_ascii=False, sort_keys=True))
PY
}

export HF_BUCKET_ID_EFFECTIVE="$BUCKET"

iteration=0
while :; do
  sample_once
  iteration=$((iteration + 1))
  if [[ "$COUNT" != "0" && "$iteration" -ge "$COUNT" ]]; then
    break
  fi
  if [[ "$INTERVAL" -gt 0 ]]; then
    sleep "$INTERVAL"
  fi
done
