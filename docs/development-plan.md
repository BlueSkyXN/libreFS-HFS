# 开发状态与下一步计划

本文档记录当前代码实现、尚未完成的事项和下一步开发计划。它不是实时运行状态报告；涉及 Hugging Face Space、Secrets、Volumes、S3 写入和持久化的结论，都必须在执行时重新回读。

## 项目目的

LibreFS HFS 是 libreFS 的 Hugging Face Docker Space 部署包装层。仓库自身不包含 libreFS 源码，而是在远端 Docker build 阶段从 `https://github.com/libreFS/libreFS.git` 拉取源码并编译 `librefs`。

按 HFS 开发范式，本仓库属于 Pattern A（HFS Port Repository），repo root 同时是 Space root 和 GitHub 维护 root；runtime 获取模式是 `source-fetch`，多服务 runtime glue 集中在 `hfs/`。

必须保持的核心契约：

- builder 和 runtime 都从 `ubuntu:24.04` 开始。
- 不使用 libreFS 官方 Docker image。
- Hugging Face 外部只暴露 `7860`。
- Nginx 在 `7860` 汇聚四个内部服务：S3 API 走 `/`，Web Console 走 `/console/`，只读诊断走 `/_ops/`，默认关闭的管理面走 `/_admin/`。
- 数据目录是 `/data`；是否持久化取决于 HF Storage Bucket 挂载和后续读回验收。

## 当前实现

| 领域 | 当前实现 | 证据文件 |
| --- | --- | --- |
| HFS 范式 | Pattern A；repo root 是 Space root，runtime glue 收在 `hfs/`。 | `hfs-dev.toml`, `README.md`, `Dockerfile`, `hfs/` |
| Runtime 获取模式 | `source-fetch`；Docker build 阶段从 libreFS upstream 拉源码并编译。 | `hfs-dev.toml`, `Dockerfile` |
| Docker build | 多阶段 Ubuntu build/runtime；builder 下载 Go tarball、拉取 libreFS upstream 并编译 `/out/librefs`。 | `Dockerfile` |
| Runtime 入口 | `hfs/start.sh` 校验 root Secrets，推导公开 URL，设置 MinIO-compatible URL 环境变量，启动并监控 libreFS、ops-service、admin-service、Nginx。 | `hfs/start.sh` |
| 单端口路由 | `hfs/nginx.conf` 监听 `7860`；`/_ops/` 转发到 `127.0.0.1:8081/`，`/_admin/` 转发到 `127.0.0.1:8082/`，`/console/` 转发到 `127.0.0.1:9001/`，其余路径转发到 `127.0.0.1:9000`。 | `hfs/nginx.conf` |
| 只读诊断面 | `hfs/ops_service.py` 提供 health、system、config、version、metrics；不返回 secret 原文。 | `hfs/ops_service.py` |
| 默认关闭管理面 | `hfs/admin_service.py` 提供默认关闭的 status/actions/run-health-checks/reload-nginx 白名单；当前生产环境通过 `ADMIN_ENABLED=true` 显式开启。 | `hfs/admin_service.py` |
| Ops/Admin 双语文案 | ops/admin JSON 支持 `en` 和 `zh-CN`，机器字段稳定，本地化字段用于管理界面展示。 | `hfs/ops_service.py`, `hfs/admin_service.py` |
| Space metadata | `README.md` front matter 保持 `sdk: docker`、`app_port: 7860`、`license: agpl-3.0`。 | `README.md` |
| 文档体系 | `docs/` 覆盖架构、部署、配置、使用、运维、排障和源码逐文件说明。 | `docs/*.md` |
| 轻量验证 | `scripts/validate-contract.sh` 汇总 front matter、Dockerfile、启动脚本、Python ops/admin 服务、Nginx、license 和可选远端 health 检查。 | `scripts/validate-contract.sh` |
| 凭证型 S3 smoke test | `scripts/smoke-s3-curl.sh` 使用 curl AWS SigV4 支持执行临时 bucket、对象、匿名拒绝和 public read policy 验收。 | `scripts/smoke-s3-curl.sh` |

## 未完成事项

| 优先级 | 事项 | 当前边界 | 下一步 |
| --- | --- | --- | --- |
| P0 | 签名 S3 smoke test | 已有 `scripts/smoke-s3-curl.sh` 可避免安装 `aws` 或 `mc`；但公开 health、Console HTML 和静态资源仍不能证明 `ListBuckets`、上传、下载、policy 和匿名直链完整可用。 | 在可使用 root 凭证时执行该脚本，并记录命令和结果。 |
| P0 | `/data` 持久化读回 | Volume 挂载只说明路径具备持久化条件，不等于已通过重启和 rebuild 后读回。 | 做“上传对象 -> restart -> 读取 -> rebuild -> 再读取”的闭环。 |
| P1 | 上游源码可重复性 | `LIBREFS_REF=master` + `LIBREFS_COMMIT=HEAD` 是开发默认值，会跟随 upstream 移动，适合快速测试，但不是 release pin。 | 发布态必须设置并记录 `LIBREFS_COMMIT=<upstream commit sha>`；`hfs-dev.toml` 的 release pin surface 只把具体 commit SHA 计入可复现输入。 |
| P1 | 远端发布同步 | GitHub `origin/main` 和 Hugging Face `hf/main` 是两个不同远端；GitHub PR 合并不会自动触发 Space rebuild。 | 发布到 HF 前单独确认是否需要 `git push hf main`，并按运维检查清单回读。 |
| P1 | Ops/Admin live 验收 | 本地静态检查能验证路由和服务语法，但不能证明 HF runtime 已接管新镜像。当前生产环境已开启 admin，不能再把 `/_admin/` 默认 404 当作线上预期。 | 发布到 HF 后检查 `/_ops/health`、`/_admin/api/status`、无 token `401`、runtime logs 和 Space `runtime.raw.sha`；只有关闭 `ADMIN_ENABLED` 时才验证 `404 admin_disabled`。 |
| P2 | Release hardening | 当前不改 runtime。Go tarball 下载仍未做 checksum 校验，Ubuntu base image 仍使用 tag 而非 digest；这不影响当前 checker，但还不是完整 supply-chain pin。 | 真正做 release hardening 时，再引入 `GO_TARBALL_SHA256` 校验和 `ubuntu:24.04@sha256:<digest>` 或等价 base image digest surface。 |
| P2 | 私有对象长期直链 | 当前只有 S3 签名请求、presigned URL、public bucket policy 三种模式，没有私有稳定下载网关。 | 如果确实需要，另行设计小型鉴权下载服务，不塞进当前 Nginx-only 包装层。 |
| P2 | 生产化能力 | HF Space 适合测试、临时共享和轻量使用，不适合作为生产对象存储。 | 生产目标应迁移到专用对象存储或专用运行环境，再做容量、备份和恢复设计。 |

## 近期开发计划

1. 固化低成本验证入口：保持 `scripts/validate-contract.sh` 覆盖本仓部署契约，减少手工漏检。
2. 执行凭证型 smoke test：在不引入重型依赖的前提下，用 `scripts/smoke-s3-curl.sh` 记录最小验收路径和结果。
3. 完成持久化验收：只在确认测试对象、重启和 rebuild 后读回均通过时，把某次持久化状态标记为已验收。
4. 评估 upstream pin：当服务从临时测试进入稳定使用阶段，选择并记录具体 `LIBREFS_COMMIT=<sha>`；不要把 `master + HEAD` 当作 release pin。
5. 发布到 Hugging Face：GitHub PR 合并后，如果目标是更新线上 Space，再由人工确认后推送 `hf main`，避免无意 rebuild。

## 最近已完成

近期以低复杂度方式修复这些问题：

- Runtime glue 已按 HFS 开发范式集中到 `hfs/`，根目录继续作为 Space root。
- `hfs/start.sh` 现在会把 libreFS 或 Nginx 的意外 `0` 退出视为异常，避免长期服务静默正常退出。
- 新增 `scripts/validate-contract.sh`，把分散在文档里的关键部署契约变成可重复执行的轻量检查。
- `hfs/start.sh` 现在会拒绝缺少 URL scheme 的 `MINIO_SERVER_URL`，并强制 `MINIO_BROWSER_REDIRECT_URL` 以 `/console/` 结尾，避免 Console 子路径配置漂移。
- 新增 `scripts/smoke-s3-curl.sh`，用 `curl --aws-sigv4` 覆盖最小 S3 读写和公开直链验收路径，无需安装 `aws` 或 `mc`。
- 新增 `/_ops/` 和 `/_admin/` 的中英文 JSON 文案能力，保留稳定机器字段，降低管理页面误读风险。
- PR #5 已合并并推送到 GitHub 和 Hugging Face；后续每次文档或代码发布后，都必须重新回读 Space runtime sha，不能沿用历史快照。

仍需独立执行或持续复核的事项：

- 需要按需执行 `scripts/smoke-s3-curl.sh`，覆盖真实 S3 写入/读取、policy 和匿名直链。
- 需要做 `/data` 重启和 rebuild 后读回验收，不能只凭 volume 挂载判断持久化已通过。
- 文档中的生产状态是 2026-05-29 的快照；涉及 HF Variables、Secrets、Volumes、`origin/main`/`hf/main` 差异和 runtime sha 时必须重新回读。
