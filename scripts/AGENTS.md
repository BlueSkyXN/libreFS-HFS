# scripts navigation card

`scripts/` 放本仓库的验证和线上 smoke 工具。修改脚本前先读根 `AGENTS.md`、目标脚本和相关 docs；这些脚本会被文档和人工运维直接引用。

## Why this is high-risk

- `validate-contract.sh` 是仓库契约检查入口，误删 pattern 会让部署漂移漏检。
- `smoke-s3-curl.sh` 会对线上 S3-compatible endpoint 创建 bucket/object、设置 bucket policy 并清理资源。
- 脚本可能使用真实 root credentials，但不得打印或提交 secret value。

## Local rules

- 保持 `set -Eeuo pipefail`。
- `validate-contract.sh` 只能做契约检查，不安装依赖、不本地编译 libreFS；远端检查必须保留在显式 `--remote` 后。
- `smoke-s3-curl.sh` 必须继续使用 `curl --aws-sigv4`，并在 bucket 非 404 时拒绝复用，避免误删用户数据。
- 新增脚本参数时同步 `usage()`、`docs/operations.md` 和 `docs/source-walkthrough.md`。
- 所有临时文件必须用 `mktemp` 或安全临时目录，并通过 trap 清理。

## Do not

- 不要把 root credentials、ops/admin token 或响应里的 secret value echo 到日志。
- 不要默认执行 mutating HF CLI 命令，例如 `hf spaces secrets add`、`variables add`、`volumes set`、`restart`。
- 不要让 smoke 脚本默认使用固定 bucket 名，除非用户显式设置并已确认可覆盖。

## Validation

- 语法：`bash -n scripts/validate-contract.sh scripts/smoke-s3-curl.sh`。
- 契约：`scripts/validate-contract.sh`。
- 凭证型 S3 smoke 只在用户明确授权线上验收时运行：`MINIO_ROOT_USER=... MINIO_ROOT_PASSWORD=... scripts/smoke-s3-curl.sh`。
