# docs navigation card

`docs/` is the public documentation and operational fact source for LibreFS HFS.
Read this card before editing live state, endpoints, Secret/Variable names, ops/admin, or persistence wording.
Start with `docs/contract-alignment.md` for runtime behavior or canonical preview snapshots.

## Local invariants

- Separate code defaults from canonical preview config; read back live state before calling it current.
- Document Secret keys and presence only; never write token, password, access-key, or private URL values.
- Health checks prove route/process availability only, not S3 writes, policy, public reads, or persistence.
- `/data` Volume attached is not persistence validation; require upload, restart, read, rebuild, and read again.
- Public ops API paths must include `/_ops/`; bare handler paths are internal after Nginx strips the prefix.
- `?token=` is temporary browser bootstrap only. Script/API docs should use `X-Ops-Token`, bearer token, or browser cookie semantics.

## Update order

- Runtime contract or canonical preview snapshot: update `docs/contract-alignment.md` first, then README and affected docs.
- Endpoint, Console URL, S3 URL, ops/admin route, login, or token transport: check README plus `configuration.md`, `operations.md`, `architecture.md`, and `source-walkthrough.md`.
- `troubleshooting.md` should cover real or high-probability failures with evidence, not speculative catalogs.

## Do not

- Do not turn a one-time spot check into a long-term guarantee.
- Do not call `/_ops/` a management surface or imply `/_admin/` is enabled by default.
- Do not describe this Space as production-grade object storage.
- Do not document live HF Variables/Secrets/Volume as current without readback or a snapshot date.

## Validation

- Documentation-only: `git diff --check -- README.md docs AGENTS.md`
- Runtime-contract docs: `scripts/validate-contract.sh`
- Live status docs: use root HF/Space readback commands; Secrets can confirm key presence only, not values.
