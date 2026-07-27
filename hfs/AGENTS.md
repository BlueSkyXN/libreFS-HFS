# hfs navigation card

`hfs/` contains runtime glue: `start.sh`, `nginx.conf`, `ops_service.py`, and `admin_service.py`.
Read this card before changing startup, routing, auth, control-plane payloads, or container paths.
Cross-check `Dockerfile`, `scripts/validate-contract.sh`, `docs/contract-alignment.md`, and `docs/source-walkthrough.md`.

## Local invariants

- Dockerfile copies `start.sh` to `/start.sh`, `nginx.conf` to `/etc/nginx/nginx.conf`, and services to `/usr/local/bin/librefs-*-service.py`.
- `nginx.conf` must keep `listen 7860`.
- Public routes stay fixed: S3 API `/`, Console `/console/`, read-only ops `/_ops/`, default-disabled admin `/_admin/`.
- `/_ops/` stays read-only and never returns secret values.
- `/_admin/` stays disabled by default; write actions must be allowlisted, authenticated, confirmed when destructive, and audited.

## Required before changes

- Ports, paths, proxy headers, auth, supervision, or runtime env: check `Dockerfile`, README, and affected docs.
- New runtime glue files: add Dockerfile copy rules and `scripts/validate-contract.sh` coverage if they enter the image.
- Language or JSON payloads: keep machine fields stable; localize only user-facing fields.

## Do not

- Do not move the Space root into `hfs/`; Pattern A keeps repo root as Space root.
- Do not store `.env.local`, tokens, credentials, local data, logs, or temporary output here.
- Do not add command execution, arbitrary file read/write, SQL, restart, terminal, file manager, or credential management to `/_ops/`.
- Do not turn `ADMIN_FILES_ENABLED` or `ADMIN_FILES_WRITE_ENABLED` into real file-management features without explicit approval.

## Validation

- `bash -n hfs/start.sh`
- `python3 -m py_compile hfs/ops_service.py hfs/admin_service.py`
- `mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi && nginx -t -c "$PWD/hfs/nginx.conf"` (requires local `nginx`)
- `scripts/validate-contract.sh`
