#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/smoke-s3-curl.sh

Run a credentialed S3 smoke test against the LibreFS HFS endpoint using only
curl's built-in AWS SigV4 support. The script creates a temporary bucket,
uploads one object, verifies signed and anonymous reads, applies a public-read
policy, then removes the temporary resources.

Required environment:
  MINIO_ROOT_USER or AWS_ACCESS_KEY_ID
  MINIO_ROOT_PASSWORD or AWS_SECRET_ACCESS_KEY

Optional environment:
  S3_ENDPOINT        Default: https://blueskyxn-librefs-hfs.hf.space
  AWS_REGION         Default: us-east-1
  S3_SMOKE_BUCKET    Default: generated temporary bucket name
  S3_SMOKE_OBJECT    Default: smoke.txt
  S3_SMOKE_PAYLOAD   Default: generated timestamp payload
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ENDPOINT="${S3_ENDPOINT:-https://blueskyxn-librefs-hfs.hf.space}"
ENDPOINT="${ENDPOINT%/}"
REGION="${AWS_REGION:-us-east-1}"
ACCESS_KEY="${MINIO_ROOT_USER:-${AWS_ACCESS_KEY_ID:-}}"
SECRET_KEY="${MINIO_ROOT_PASSWORD:-${AWS_SECRET_ACCESS_KEY:-}}"
BUCKET="${S3_SMOKE_BUCKET:-librefs-hfs-smoke-$(date -u +%Y%m%d%H%M%S)-$$}"
OBJECT="${S3_SMOKE_OBJECT:-smoke.txt}"
PAYLOAD="${S3_SMOKE_PAYLOAD:-librefs-hfs smoke $(date -u +%Y-%m-%dT%H:%M:%SZ)}"

case "$ENDPOINT" in
  http://*|https://*) ;;
  *)
    echo "S3_ENDPOINT must start with http:// or https://: $ENDPOINT" >&2
    exit 2
    ;;
esac

if [[ -z "$ACCESS_KEY" || -z "$SECRET_KEY" ]]; then
  echo "Set MINIO_ROOT_USER/MINIO_ROOT_PASSWORD or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY." >&2
  exit 2
fi

if [[ ! "$BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
  echo "S3_SMOKE_BUCKET is not a valid DNS-style bucket name: $BUCKET" >&2
  exit 2
fi

case "$OBJECT" in
  /*|*'?'*)
    echo "S3_SMOKE_OBJECT must not start with / or contain ?: $OBJECT" >&2
    exit 2
    ;;
esac

curl_help="$(curl --help all)"
for required_curl_flag in '--aws-sigv4' '--fail-with-body'; do
  if ! grep -q -- "$required_curl_flag" <<<"$curl_help"; then
    echo "This curl build does not support $required_curl_flag." >&2
    exit 2
  fi
done

tmp_dir="$(mktemp -d)"
payload_file="$tmp_dir/payload.txt"
signed_download="$tmp_dir/signed-download.txt"
public_download="$tmp_dir/public-download.txt"
private_body="$tmp_dir/private-body.txt"
status_body="$tmp_dir/status-body.txt"
policy_file="$tmp_dir/public-read-policy.json"
bucket_created=0
object_uploaded=0
policy_applied=0

signed_curl() {
  curl --silent --show-error --fail-with-body \
    --aws-sigv4 "aws:amz:${REGION}:s3" \
    --user "${ACCESS_KEY}:${SECRET_KEY}" \
    "$@"
}

signed_status() {
  curl --silent --show-error \
    --aws-sigv4 "aws:amz:${REGION}:s3" \
    --user "${ACCESS_KEY}:${SECRET_KEY}" \
    -o "$status_body" \
    -w '%{http_code}' \
    "$@" || true
}

cleanup() {
  if [[ "$policy_applied" -eq 1 ]]; then
    signed_curl -X DELETE "$ENDPOINT/$BUCKET?policy" >/dev/null 2>&1 || true
  fi
  if [[ "$object_uploaded" -eq 1 ]]; then
    signed_curl -X DELETE "$ENDPOINT/$BUCKET/$OBJECT" >/dev/null 2>&1 || true
  fi
  if [[ "$bucket_created" -eq 1 ]]; then
    signed_curl -X DELETE "$ENDPOINT/$BUCKET" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}

printf '%s\n' "$PAYLOAD" > "$payload_file"

cat > "$policy_file" <<EOF_POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": ["*"]
      },
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::$BUCKET/*"]
    }
  ]
}
EOF_POLICY

trap cleanup EXIT

echo "==> list buckets"
signed_curl "$ENDPOINT/" >/dev/null

echo "==> ensure temporary bucket does not already exist: $BUCKET"
bucket_status="$(signed_status -I "$ENDPOINT/$BUCKET")"
if [[ "$bucket_status" != "404" ]]; then
  echo "Refusing to use bucket $BUCKET because HEAD returned HTTP $bucket_status, expected 404." >&2
  exit 1
fi

echo "==> create temporary bucket: $BUCKET"
signed_curl -X PUT "$ENDPOINT/$BUCKET" >/dev/null
bucket_created=1

echo "==> upload object: $OBJECT"
signed_curl -X PUT --data-binary @"$payload_file" "$ENDPOINT/$BUCKET/$OBJECT" >/dev/null
object_uploaded=1

echo "==> signed object download"
signed_curl "$ENDPOINT/$BUCKET/$OBJECT" -o "$signed_download"
if ! cmp -s "$payload_file" "$signed_download"; then
  echo "Signed download content does not match uploaded payload." >&2
  exit 1
fi

echo "==> anonymous read is denied before policy"
private_status="$(curl --silent --show-error -o "$private_body" -w '%{http_code}' "$ENDPOINT/$BUCKET/$OBJECT" || true)"
if [[ "$private_status" != "403" ]]; then
  echo "Expected anonymous read HTTP 403 before policy, got $private_status" >&2
  exit 1
fi

echo "==> apply public-read bucket policy"
signed_curl -X PUT -H 'Content-Type: application/json' --data-binary @"$policy_file" "$ENDPOINT/$BUCKET?policy" >/dev/null
policy_applied=1

echo "==> anonymous read succeeds after policy"
curl --silent --show-error --fail-with-body "$ENDPOINT/$BUCKET/$OBJECT" -o "$public_download"
if ! cmp -s "$payload_file" "$public_download"; then
  echo "Public download content does not match uploaded payload." >&2
  exit 1
fi

echo "S3 smoke test passed. Temporary bucket will be removed: $BUCKET"
