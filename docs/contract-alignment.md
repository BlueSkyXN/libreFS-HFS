# 代码-文档契约对照

本文档把当前代码事实、生产回读状态和文档维护口径放在同一处，用于减少文档漂移。修改代码或远端配置后，先更新这里，再同步其他文档。

最后核对时间：2026-05-29。

## 当前生产回读

| 项目 | 当前状态 | 证据命令 |
| --- | --- | --- |
| GitHub `origin/main` | `b498d4effbfc02d7e95f77a8f98bb3a790df9f00` | `git ls-remote origin HEAD refs/heads/main` |
| Hugging Face `hf/main` | `007485be905313ddc426c86fbd4322c80bb87797`；GitHub main 已领先，尚未推送到 HF 部署仓。 | `git ls-remote hf HEAD refs/heads/main` |
| Space health | `/minio/health/ready` 回读 `HTTP 200`；Space API 可能需要认证，不能只依赖匿名 `curl`。 | `curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready -o /dev/null -w 'health_http=%{http_code}\n'` |
| HF Variables | 当前显式配置：`ADMIN_ENABLED=true`、`PUBLIC_BASE_URL`、`MINIO_SERVER_URL`、`MINIO_BROWSER_REDIRECT_URL`、`GO_VERSION=1.26.3`、`LIBREFS_REF=master`、`LIBREFS_COMMIT=e194bd779f36fdc08f310d2819d9356f0c1f991b`、`MINIO_SITE_NAME`、`MINIO_SITE_REGION`、`MINIO_BROWSER`、`MINIO_BROWSER_REDIRECT`、`MINIO_UPDATE`、`MINIO_CALLHOME_ENABLE`、`MINIO_API_ROOT_ACCESS`、`MINIO_API_CORS_ALLOW_ORIGIN`。其中多项与代码默认或 upstream 默认值重复，属于可后续清理的配置噪音。 | `hf spaces variables list BlueSkyXN/libreFS-HFS` |
| HF Secrets | `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD`、`OPS_TOKEN`、`ADMIN_TOKEN` 已存在；HF 不回显 value。 | `hf spaces secrets list BlueSkyXN/libreFS-HFS` |
| HF Volume | `bucket BlueSkyXN/libreFS-HFS-storage -> /data`，`read_only=False` | `hf spaces volumes list BlueSkyXN/libreFS-HFS` |

生产状态是快照，不是永久保证。涉及实时状态、Secret 同步、Volume 挂载或 runtime sha 时必须重新回读。

## 不可漂移契约

| 契约点 | 当前事实 | 权威来源 | 文档同步位置 |
| --- | --- | --- | --- |
| Space 类型 | Docker Space，`app_port: 7860`，`license: agpl-3.0` | `README.md` front matter | `README.md`, `docs/configuration.md`, `docs/deployment-huggingface.md` |
| HFS 范式分类 | Pattern A / HFS Port Repository；repo root 同时是 Space root 和 GitHub 维护 root，runtime glue 收在 `hfs/` | `hfs-dev.toml`, `README.md`, `Dockerfile`, `hfs/` | `README.md`, `docs/architecture.md`, `docs/source-walkthrough.md`, `AGENTS.md` |
| Runtime 获取模式 | `source-fetch`；Docker build 阶段从 libreFS upstream `git fetch` 源码并编译 | `hfs-dev.toml`, `Dockerfile` | `README.md`, `docs/architecture.md`, `docs/development-plan.md` |
| 外部端口 | 只暴露 `7860` | `Dockerfile` `EXPOSE 7860`，`hfs/nginx.conf` `listen 7860` | 全部 endpoint/port 文档 |
| 构建策略 | Ubuntu builder/runtime，从 `https://github.com/libreFS/libreFS.git` 拉源码编译，不使用官方 image | `Dockerfile` | `README.md`, `docs/architecture.md`, `docs/source-walkthrough.md` |
| Go 版本 | `GO_VERSION=1.26.3` | `Dockerfile` | `docs/configuration.md`, `docs/source-walkthrough.md`, `docs/deployment-huggingface.md` |
| libreFS ref | 开发默认是 `LIBREFS_REF=master`、`LIBREFS_COMMIT=HEAD`；发布态必须设置具体 `LIBREFS_COMMIT=<upstream commit sha>` | `Dockerfile`, `hfs-dev.toml` | `docs/configuration.md`, `docs/troubleshooting.md`, `docs/development-plan.md` |
| Release hardening | 当前 release pin surface 只计入 upstream commit SHA；Go tarball checksum 和 Ubuntu base image digest 是后续 hardening backlog，不改当前 runtime | `hfs-dev.toml`, `Dockerfile` | `docs/configuration.md`, `docs/development-plan.md` |
| Runtime packages | `bash`、`ca-certificates`、`curl`、`nginx`、`python3`、`tini` | `Dockerfile` | `docs/architecture.md`, `docs/source-walkthrough.md` |
| Runtime user | UID/GID `1000`，存在则复用，不无条件创建 | `Dockerfile` | `docs/source-walkthrough.md`, `docs/troubleshooting.md` |
| 必需启动 Secrets | 只有 `MINIO_ROOT_USER` 和 `MINIO_ROOT_PASSWORD` 缺失会让 `hfs/start.sh` 立即退出 | `hfs/start.sh` | `docs/configuration.md`, `docs/deployment-huggingface.md`, `docs/troubleshooting.md` |
| Ops token | `OPS_TOKEN` 默认 `librefs_ops_demo_token`，生产应使用 HF Secret 覆盖 | `hfs/start.sh`, `hfs/ops_service.py` | `README.md`, `docs/configuration.md`, `docs/operations.md` |
| Admin 开关 | 代码默认 `ADMIN_ENABLED=false`；当前生产回读为 `ADMIN_ENABLED=true` | `hfs/start.sh`, HF Variables | `README.md`, `docs/configuration.md`, `docs/operations.md`, `docs/troubleshooting.md` |
| Admin token | 开启 admin 时必须设置 `ADMIN_TOKEN`；使用 `X-Admin-Token` 或 bearer token；代码不强制它与 `OPS_TOKEN` 不同 | `hfs/admin_service.py` | `docs/configuration.md`, `docs/operations.md`, `docs/architecture.md` |
| 公开 URL 推导 | `PUBLIC_BASE_URL` > `SPACE_HOST` > `http://localhost:7860` | `hfs/start.sh` | `docs/architecture.md`, `docs/configuration.md`, `docs/source-walkthrough.md` |
| `MINIO_SERVER_URL` | 必须有 `http://` 或 `https://`，并去掉尾部 `/` | `hfs/start.sh` | `docs/architecture.md`, `docs/configuration.md`, `docs/source-walkthrough.md` |
| `MINIO_BROWSER_REDIRECT_URL` | 必须以 `/console/` 结尾 | `hfs/start.sh` | `docs/architecture.md`, `docs/configuration.md`, `docs/source-walkthrough.md` |
| 进程模型 | `librefs`、ops-service、admin-service、Nginx 任一退出，容器退出并清理其余进程 | `hfs/start.sh` | `docs/architecture.md`, `docs/source-walkthrough.md`, `docs/operations.md` |
| Nginx 路由 | `/_ops/ -> 8081`，`/_admin/ -> 8082`，`/console/ -> 9001`，`/ -> 9000` | `hfs/nginx.conf` | `README.md`, `docs/architecture.md`, `docs/configuration.md`, `docs/source-walkthrough.md` |
| Console 子路径 | `location /console/` 使用 `proxy_pass http://127.0.0.1:9001/;` 剥掉 `/console/` 前缀 | `hfs/nginx.conf` | `docs/architecture.md`, `docs/source-walkthrough.md`, `docs/troubleshooting.md` |
| Console iframe | 只在 `/console/` 隐藏 upstream `X-Frame-Options` 并补 `Content-Security-Policy frame-ancestors` | `hfs/nginx.conf` | `docs/architecture.md`, `docs/configuration.md`, `docs/operations.md`, `docs/troubleshooting.md` |
| Ops endpoints | 外部路径为 `GET /_ops/` dashboard、`/_ops/health`、`/_ops/system`、`/_ops/config`、`/_ops/version`、`/_ops/metrics`；Nginx 转发后内部 handler 才是 `/health` 等短路径；`/_ops/healthz` 免 token 只用于轻量存活检查 | `hfs/nginx.conf`, `hfs/ops_service.py` | `README.md`, `docs/architecture.md`, `docs/configuration.md`, `docs/operations.md`, `docs/source-walkthrough.md` |
| Ops 安全边界 | 只读；`/_ops/config` 只返回 Secret 是否存在，不返回 value；`?token=` 只作为浏览器首次登录/bootstrap，成功后用 `HttpOnly` cookie；脚本和 JSON API 请求不接受 query token 鉴权，必须用 `X-Ops-Token`、bearer token 或浏览器 cookie | `hfs/ops_service.py` | `README.md`, `docs/architecture.md`, `docs/configuration.md`, `docs/operations.md` |
| Admin endpoints | `GET /api/status`、`GET /api/actions`、`POST /api/actions/run-health-checks`、`POST /api/actions/reload-nginx` | `hfs/admin_service.py` | `docs/configuration.md`, `docs/operations.md`, `docs/source-walkthrough.md` |
| Admin 写操作 | `reload-nginx` 是写 action，必须 JSON body `{"confirm": true}`，并写审计日志 | `hfs/admin_service.py` | `docs/architecture.md`, `docs/configuration.md`, `docs/operations.md` |
| Admin 非目标 | 没有 Web terminal、file manager、bucket/policy/root credential 管理或 `librefs` restart | `hfs/admin_service.py`, 当前路由 | `README.md`, `docs/architecture.md`, `docs/configuration.md`, `docs/usage.md`, `docs/operations.md` |
| 双语文案 | 支持 `en` 和 `zh-CN`；语言优先级为 `?lang=`、`X-Control-Language`、`Accept-Language`、`CONTROL_PLANE_DEFAULT_LANG`、默认 `en` | `hfs/ops_service.py`, `hfs/admin_service.py` | `README.md`, `docs/configuration.md`, `docs/operations.md`, `docs/architecture.md` |
| 数据目录 | libreFS 数据和 admin audit log 默认在 `/data`；当前生产挂载 Storage Bucket 到 `/data` | `hfs/start.sh`, HF Volumes | `README.md`, `docs/architecture.md`, `docs/operations.md`, `docs/usage.md` |
| 持久化口径 | Volume 挂载不等于持久化验收通过；仍需上传、重启、读取、rebuild、再读取 | 运维要求 | 所有持久化说明 |
| S3 smoke | `scripts/smoke-s3-curl.sh` 会真实创建临时 bucket/object、设置 public read policy 并清理 | `scripts/smoke-s3-curl.sh` | `docs/README.md`, `docs/operations.md`, `docs/source-walkthrough.md` |
| 契约验证 | `scripts/validate-contract.sh` 检查 front matter、Dockerfile、`hfs/start.sh`、Python、Nginx、license 和可选远端 health | `scripts/validate-contract.sh` | `docs/README.md`, `docs/operations.md`, `docs/source-walkthrough.md` |

## 文档维护规则

1. 区分“代码默认值”和“当前生产配置”。例如 `ADMIN_ENABLED` 代码默认是 `false`，但当前生产是 `true`。
2. 不把 Secret 明文写入文档。HF CLI 只能证明 key 存在；value 同步必须用本地 `.env.local` 的值调线上接口验证。
3. 不把 health check 写成 S3 功能验收。S3 写入、下载、policy 和匿名直链必须用凭证型 smoke test 验证。
4. 不把 Volume 挂载写成持久化已验收。必须完成重启和 rebuild 后读回。
5. 修改 `hfs/ops_service.py` 或 `hfs/admin_service.py` 时，同步检查 `docs/configuration.md`、`docs/operations.md`、`docs/architecture.md` 和本文档。
6. 修改远端 HF Variables、Secrets 或 Volume 后，同步更新“当前生产回读”，并保留“代码默认值”不变。
