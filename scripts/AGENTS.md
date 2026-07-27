# scripts navigation card

`scripts/` contains repository validation and live smoke tools used by docs and manual operations.
Read this card before changing script flags, credential handling, cleanup behavior, or remote checks.
Key files: `validate-contract.sh` for non-live contract checks, `smoke-s3-curl.sh` for credentialed S3 validation.

## Why this is high-risk

- `validate-contract.sh` is the main drift detector for README front matter, Dockerfile, HFS manifest, runtime glue, Nginx routing, ops/admin safety, and license.
- `smoke-s3-curl.sh` creates a temporary bucket/object, applies bucket policy, verifies reads, and cleans up against the configured endpoint.
- Scripts may receive real root credentials through environment variables; they must not print or persist secret values.

## Local rules

- Keep `set -Eeuo pipefail`.
- `validate-contract.sh` must stay lightweight: no dependency install, no local upstream libreFS build, no mutating HF commands. Remote checks stay behind explicit `--remote`.
- `smoke-s3-curl.sh` must keep `curl --aws-sigv4`, reject existing buckets, use generated temporary names by default, and clean up with `trap`.
- New flags or environment variables require updates to `usage()`, `docs/operations.md`, and `docs/source-walkthrough.md`.

## Do not

- Do not echo root credentials, ops/admin tokens, signed URLs, or secret-bearing response bodies.
- Do not make mutating HF CLI calls by default: `secrets add`, `variables add`, `volumes set`, `restart`, or `git push hf main`.
- Do not let smoke tests reuse fixed bucket names unless the user explicitly confirms the target is disposable.

## Validation

- `bash -n scripts/validate-contract.sh scripts/smoke-s3-curl.sh`
- `scripts/validate-contract.sh`
- Credentialed live smoke only with explicit user authorization: `MINIO_ROOT_USER=... MINIO_ROOT_PASSWORD=... scripts/smoke-s3-curl.sh`
