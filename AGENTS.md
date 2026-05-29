# Repository agent instructions

## Purpose

本仓库是 LibreFS HFS 的 Hugging Face Docker Space 部署包装层。仓库不 vendored libreFS 源码；远端 Docker build 从 `https://github.com/libreFS/libreFS.git` 拉源码并编译 `librefs`，runtime 用 Nginx 在公开端口 `7860` 合并 S3 API 和 Web Console。

核心契约：Ubuntu builder/runtime、远端源码构建、不使用 libreFS 官方 Docker image、外部只暴露 `7860`、S3 API 在 `/`、Web Console 在 `/console/`、只读诊断面在 `/_ops/`、代码默认关闭的管理面在 `/_admin/`。

## Codex startup behavior

- Codex 通常从仓库根目录启动；本文件是 repo-local 主规则/router。
- 当前有根 `AGENTS.md`、`hfs/AGENTS.md`、`docs/AGENTS.md` 和 `scripts/AGENTS.md`；没有 `AGENTS.override.md`。
- 修改 `hfs/`、`docs/` 或 `scripts/` 下文件前，按下面的 On-demand cat protocol 读取对应子卡；同目录出现 `AGENTS.override.md` 时先停止并确认策略。
- 不要把 README 或 docs 当作自动加载的项目指令；关键部署约束、命令和验证标准必须在本文件里复述。

## Directory map

| Path | Responsibility | Local AGENTS.md | Read when |
| --- | --- | ---: | --- |
| `README.md` | HF Space metadata、项目入口、endpoint、Secrets、能力状态 | No | 修改 front matter、公开地址、状态表、health check、文档索引时 |
| `LICENSE` | 仓库许可证文本，应对齐 libreFS 上游 AGPL-3.0 | No | 修改 license metadata、合规说明或合并许可证文件时 |
| `Dockerfile` | 远端 build/runtime 镜像契约、Go 下载、源码编译、runtime packages、Python ops/admin 服务复制、healthcheck | No | 修改 base image、build args、上游源码 ref、UID/GID、runtime packages、`HEALTHCHECK` 时 |
| `hfs-dev.toml` | HFS 开发范式 alignment manifest，声明 Pattern A、runtime 模式、Space root 和 pin surface | No | 修改 HFS 分类、runtime 获取模式、发布态 pin surface 或 required files 时 |
| `hfs/` | HFS runtime glue；容器入口、Nginx、ops/admin 服务 | Yes | 修改任何运行胶水、进程监管、路由、鉴权或容器内复制路径时 |
| `hfs/start.sh` | 容器启动入口；校验 Secrets、推导公开 URL、启动并监控 libreFS、ops-service、admin-service、Nginx | Yes | 修改环境变量、端口、URL 推导、进程管理、signal handling 时 |
| `hfs/nginx.conf` | 单端口反向代理；`/_ops/` -> ops-service，`/_admin/` -> admin-service，`/console/` -> Web Console，`/` -> S3 API | Yes | 修改路由、proxy header、buffering、timeout、body size、Console 子路径、iframe/CSP header 时 |
| `hfs/ops_service.py` | 只读诊断 HTTP 服务；dashboard、health、system、config、version、metrics | Yes | 修改 `/_ops` endpoint、网页登录态、鉴权、配置摘要、metrics、健康检查时 |
| `hfs/admin_service.py` | 默认关闭的管理 HTTP 服务；status、action catalog、run-health-checks、reload-nginx | Yes | 修改 `/_admin` endpoint、写 action、审计、token 校验时 |
| `.dockerignore` | Docker build context 过滤，避免 `.env*`、`local/`、临时文件进入 Hugging Face build | No | 修改 build context 或本地材料忽略规则时 |
| `.gitattributes` | Hugging Face 仓库展示/LFS 类型规则 | No | 修改 HF 文件类型或大文件规则时 |
| `.gitignore` | 本地 Git 忽略规则 | No | 修改 `.data/`、`.env*`、`/local`、logs、临时文件忽略规则时 |
| `docs/` | 架构、配置、部署、使用、运维、故障排查、契约对照和源码逐文件说明 | Yes | 修改任何 docs 内容、能力状态、endpoint、生产快照或文档索引前 |
| `docs/contract-alignment.md` | 代码事实、生产回读状态和文档维护口径的对照表 | Yes | 修改 runtime、HF Variables/Secrets/Volume、ops/admin 或任何文档实时状态时 |
| `scripts/` | 本地/远端契约验证与凭证型 S3 smoke 脚本 | Yes | 修改 validation、smoke、curl SigV4、清理逻辑或远端验收命令时 |
| `.codex/` | 本地 Codex 工作区占位目录，当前没有跟踪文件 | No | 只有用户要求维护本地 agent/skill 配置时 |
| `.env.local` | 本地配置和 secret 台账；Git/Docker context 均应忽略 | No | 默认不要读取；只有用户明确要求维护本地台账时 |
| `local/` | 本地材料目录；Git/Docker context 均应忽略 | No | 默认不要读取或处理；只有用户明确点名 `local/` 时 |

## On-demand cat protocol

当前本地子卡片覆盖 `hfs/`、`docs/` 和 `scripts/`。未来目标路径或父目录出现新的 `AGENTS.md` 时：

1. 按从根到目标目录的顺序运行 `cat <path>/AGENTS.md`；修改 `hfs/`、`docs/` 或 `scripts/` 前必须先读对应子卡。
2. 子卡只覆盖对应子树；冲突时更靠近目标文件的规则优先。
3. 同目录发现 `AGENTS.override.md` 时停止修改并确认策略。

## Git remotes and branch policy

当前仓库有两个远端，职责不同：

| Remote | URL | Role |
| --- | --- | --- |
| `hf` | `https://huggingface.co/spaces/BlueSkyXN/libreFS-HFS` | Hugging Face Space 部署仓库；推送 `main` 会触发 Space rebuild |
| `origin` | `https://github.com/BlueSkyXN/libreFS-HFS.git` | GitHub 远端仓库；用于备份、协作、同步 GitHub 侧变化 |

Rules:

- 默认先读 `git status --short --branch` 和 `git remote -v`，不要假设当前分支或远端。
- 不要擅自 `git push hf main`；这会触发 Hugging Face Space rebuild。
- 不要擅自 push 到 `origin`；用户只说“合并/审查”时先完成本地合并建议或本地提交。
- 合并远端变化前，先比较 `hf/main`、`origin/main` 和本地 `main`，并保留用户未提交修改；提交前必须确认 staged 范围。
- 如果 GitHub 远端修改 `LICENSE`，必须确认仍是 `GNU Affero General Public License v3.0`，因为 libreFS 上游和 README 都是 AGPL-3.0。

## Commands

本仓库没有 `package.json`、`Makefile`、`pyproject.toml`、CI workflow 或统一 test script。不要编造 install/build/test；只使用真实脚本、HF CLI 和文档中的命令。

- 本地 Git/格式：`git status --short --branch`、`git remote -v`、`git diff --check`。
- 本地契约：`scripts/validate-contract.sh`。它检查 README front matter、Dockerfile、`hfs/start.sh`、Python ops/admin、`hfs/nginx.conf`、license，并在本机有 Nginx 时做 `nginx -t`；不安装依赖、不本地编译 libreFS。
- 远端健康：`scripts/validate-contract.sh --remote` 或 `curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready -o /dev/null -w 'health_http=%{http_code}\n'`；需要网络，不读取 Secret。
- 凭证型 S3 smoke：`MINIO_ROOT_USER=... MINIO_ROOT_PASSWORD=... scripts/smoke-s3-curl.sh`。会创建/清理临时 bucket/object，只在用户明确要求线上验收时运行。
- Nginx 语法：`mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi && nginx -t -c "$PWD/hfs/nginx.conf"`。
- Space 状态/日志：`curl -fsSL https://huggingface.co/api/spaces/BlueSkyXN/libreFS-HFS`、`hf spaces logs BlueSkyXN/libreFS-HFS --build --tail 200`、`hf spaces logs BlueSkyXN/libreFS-HFS --tail 200`。如果匿名 Space API 返回 `401`，用 health endpoint 和已登录 HF CLI 回读状态，不要直接判为 runtime 故障。
- 远端 Git/HF 配置回读：`git ls-remote hf HEAD refs/heads/main`、`hf spaces variables list BlueSkyXN/libreFS-HFS`、`hf spaces secrets list BlueSkyXN/libreFS-HFS`、`hf spaces volumes list BlueSkyXN/libreFS-HFS`。HF Secrets 只显示 key，不显示 value。
- Console/ops/admin smoke：按需检查 `/console/` header、Console JS/CSS MIME、`/_ops/` dashboard、`/_ops/health`、`/_admin/api/status`。ops 脚本请求需要 `X-Ops-Token` 或 bearer token；网页登录可用 `?token=` 首次引导到 HttpOnly cookie；admin 需要 `X-Admin-Token`；admin 生产是否开启必须先回读 HF Variables。

不要运行 mutating HF 命令，除非用户明确要求 live operation：`hf spaces secrets add`、`hf spaces variables add`、`hf spaces volumes set`、`hf spaces restart`。当前 `hf` help: `spaces variables add` uses `-e` / `--env`; `spaces volumes set` uses `-v` / `--volume`; docs examples use `spaces secrets add -s`.

## Global rules

- 默认使用中文沟通；代码、命令、配置键、路径和专有名词保持英文。
- 本仓库是公开 HF Space 部署包。可记录 Secret 名称，但不要提交真实 `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD`、token 或 key。
- 本仓库不是上游 libreFS 源码仓库；不要 vendor、复制或手写大段 libreFS 源码。
- 当前部署策略明确要求 Ubuntu builder + Ubuntu runtime，不使用 libreFS 官方 Docker image。改这个策略前必须得到用户明确确认。
- libreFS upstream 默认 ref 当前写为 `master`。不要把 `LIBREFS_REF` 改成 `main`，除非先用只读命令确认上游默认分支已变化，并同步更新 docs。
- `LIBREFS_COMMIT=HEAD` 表示不 pin 精确 commit；如果改成具体 commit，Docker build 中的 `git rev-parse HEAD` 校验必须保留。
- `README.md` front matter 的 `sdk: docker` 和 `app_port: 7860` 是 HF Space 行为契约。`app_port` 必须与 `hfs/nginx.conf` 的 `listen 7860` 和 Dockerfile `EXPOSE 7860` 保持一致。
- `license: agpl-3.0`、`LICENSE` 文件和上游 libreFS 许可证必须保持一致。不要把许可证降级或改成普通 GPL。
- Runtime 以 UID/GID `1000` 运行，但 Dockerfile 必须兼容 UID/GID 已存在的情况；不要退回无条件 `useradd -m -u 1000 user`。
- Runtime 不应依赖 root 权限；新增 runtime 写入路径时必须确保 UID/GID `1000` 可写。
- `/data` 是对象数据目录；没有挂载 Hugging Face Storage Bucket 时数据不保证持久。
- 区分代码默认值和当前生产配置：`ADMIN_ENABLED` 代码默认是 `false`；当前线上是否为 `true` 必须用 `hf spaces variables list BlueSkyXN/libreFS-HFS` 或 `docs/contract-alignment.md` 的最新回读入口确认。
- Hugging Face Space 外部只暴露 `7860`。`9000` 和 `9001` 是容器内部端口，不要在文档或配置里描述成外部直连端口。
- S3 client 应使用 path-style addressing；HF Space 子域名下不要推荐 virtual-hosted bucket URL。
- 避免建议或创建名为 `console`、`minio`、`_ops`、`_admin` 的公开 bucket，因为这些路径与 Console、健康检查、ops 和 admin 路由冲突。
- `/_ops/` 是只读诊断面和浏览器 dashboard，默认使用 `OPS_TOKEN` 保护；不能新增写操作、任意命令、任意文件读取、SQL、restart 或 secret 原文返回。
- 公开 ops API 路径必须带 `/_ops/` 前缀：`/_ops/health`、`/_ops/system`、`/_ops/config`、`/_ops/version`、`/_ops/metrics`。裸 `/health` 等只是在 Nginx 剥掉 `/_ops/` 后的内部 handler path，不要写成外部 URL。
- `/_ops/?token=...` 只作为临时浏览器登录/bootstrap 入口；验证成功后应设置 `Secure; HttpOnly; SameSite=Lax; Path=/_ops` cookie 并跳转到无 token URL。脚本和 JSON API 请求不接受 query token 鉴权，必须使用 `X-Ops-Token`、`Authorization: Bearer <token>` 或浏览器 cookie；不要在文档、日志、截图或分享链接里长期保留 query token。
- `/_ops/healthz` 是免 token 的内部轻量 liveness endpoint，只能返回 ops 服务存活状态；不能扩展成 system/config/version/metrics 信息。
- `/_admin/` 是独立管理面，代码默认 `ADMIN_ENABLED=false`；开启时必须设置 `ADMIN_TOKEN`。`ADMIN_TOKEN` 是独立配置键和 header，代码不强制它与 `OPS_TOKEN` 的值不同；不要在未回读 `.env.local` 或 HF Secret key 状态时猜测线上 token。
- 当前 admin 第一版只允许 `run-health-checks` 和 `reload-nginx`；`reload-nginx` 必须显式 `confirm=true` 并写审计日志。不要新增 Web terminal、file manager、bucket/policy/root credential 管理或 `librefs` restart，除非用户明确要求并重新评估生命周期。
- ops/admin JSON 支持 `en` 和 `zh-CN`。语言优先级是 `?lang=`、`X-Control-Language`、`Accept-Language`、`CONTROL_PLANE_DEFAULT_LANG`、默认 `en`；`error`、endpoint path、action `name` 等机器字段保持稳定，`message`、`hint`、`label`、`description`、`risk`、`notes` 才本地化。
- `ADMIN_FILES_ENABLED` 和 `ADMIN_FILES_WRITE_ENABLED` 只是当前 status payload 的预留字段；设置它们不会启用 file manager 或文件写入能力。
- 对外说明要保守：适合测试、临时共享和轻量使用，不建议作为生产对象存储。

## File-specific rules

### `README.md`

- README 同时是 HF Space card；front matter 会影响远端构建与展示。
- 保留 `sdk: docker`、`app_port: 7860`、`license: agpl-3.0`，除非有明确证据和用户确认。
- 可以写公开 endpoint、Console URL、Secret/Variable 名称和占位符；不要写真实 secret value，也不要把一次 spot check 写成长期保证。
- 修改 health check、endpoint 或 public object URL 示例时，同步 `docs/usage.md` 和 `docs/operations.md`。
- 修改能力状态、生产快照或 admin 开关表述时，先看 `docs/contract-alignment.md`，再决定是否需要 live 回读。

### `LICENSE`

- `LICENSE` 应是 `GNU Affero General Public License v3.0`，对齐上游 libreFS。
- 如果从 GitHub remote 合入普通 `GNU General Public License v3.0`，应修正为 AGPL-3.0。
- 不要手写许可证文本；需要刷新时从上游 libreFS 或 FSF 官方文本核对。

### `Dockerfile`

- 保留多阶段结构：builder 编译 `/out/librefs`，runtime 只复制 `librefs` 和 `hfs/` 下的 runtime glue。
- Builder 依赖保持最小：`ca-certificates`、`curl`、`git`、`tar`。
- Go 通过 `GO_VERSION` 下载官方 tarball；修改时同步 `README.md` 和 `docs/configuration.md`。
- `TARGETARCH` 当前只接受 `amd64|arm64`；扩展前确认 Go tarball 名称和 HF buildx 行为。
- 保留 `go build -trimpath -buildvcs=false -ldflags="-s -w"` 和 BuildKit cache mount。
- Runtime 只安装必需包：`bash`、`ca-certificates`、`curl`、`nginx`、`python3`、`tini`。
- Runtime 必须复制 `hfs/ops_service.py` 和 `hfs/admin_service.py` 到 `/usr/local/bin/`；服务通过 `hfs/start.sh` 用 `python3` 启动。
- `HEALTHCHECK` 应继续访问 `http://127.0.0.1:7860/minio/health/ready`。

### `hfs/start.sh`

- 保持 `set -Eeuo pipefail`。
- 启动前必须校验 `MINIO_ROOT_USER` 和 `MINIO_ROOT_PASSWORD`，缺失时直接失败。
- 公开 URL 优先级：`PUBLIC_BASE_URL` > `SPACE_HOST` > `http://localhost:7860`。
- `MINIO_SERVER_URL` 必须去掉末尾 `/`；`MINIO_BROWSER_REDIRECT_URL` 必须以 `/console/` 结尾。
- 如果用户覆盖 `MINIO_SERVER_URL`，必须包含 `http://` 或 `https://` scheme；如果覆盖 `MINIO_BROWSER_REDIRECT_URL`，仍必须落在 `/console/` 子路径。
- 执行 `nginx -t -c "$NGINX_CONF"` 前必须创建 `/tmp/nginx/*` 临时目录。
- libreFS 和 Nginx 必须都被监控；任一进程退出时容器应退出并清理另一个进程。修改 signal handling 后检查 `tini`、`INT`、`TERM`。
- ops-service 和 admin-service 也必须被监控；任一进程退出时容器应退出并清理其余进程。
- `OPS_TOKEN` 默认值只适合 demo/lightweight diagnostics，公开长期运行建议在 HF Secret 中覆盖。
- `ADMIN_ENABLED` 代码默认必须是 `false`；当前生产可通过 HF Variable 显式开启，不能把生产状态写成代码默认值。
- `ADMIN_AUDIT_LOG` 默认落在 `/data/logs/admin-audit.jsonl`。

### `hfs/nginx.conf`

- 保留 `listen 7860`，除非同时修改 HF `app_port`、Dockerfile `EXPOSE` 和文档。
- `location = /_ops` 和 `location /_ops/` 必须在 `location /` 前，转发到 `http://127.0.0.1:8081/`。
- `location = /_admin` 和 `location /_admin/` 必须在 `location /` 前，转发到 `http://127.0.0.1:8082/`。
- `location = /console` 继续重定向到 `/console/`。
- `location /console/` 的 `proxy_pass` 必须是 `http://127.0.0.1:9001/;`，末尾 `/` 用来剥掉 `/console/` 前缀。
- `location /` 继续转发到 `http://127.0.0.1:9000`，这是 S3 API 根路径。
- 保留 `client_max_body_size 0`、buffering off 和必要 forwarded headers。
- WebSocket/upgrade header 只应用在 Console 代理中；S3 API location 保持简单连接行为。
- Console iframe header 处理只放在 `/console/`，不要扩展到 S3 API 根路径。

### `hfs/ops_service.py`

- 保持只读边界；`/_ops/config` 只返回 secret presence，不返回任何 secret value。
- 外部可见 API 路径必须保持 `/_ops/health`、`/_ops/system`、`/_ops/config`、`/_ops/version`、`/_ops/metrics`；根 `/_ops/` 面向浏览器返回聚合 dashboard，脚本或 `?format=json` 可拿 JSON 索引。
- 保持三类 ops 鉴权兼容：`X-Ops-Token`、`Authorization: Bearer <token>`、浏览器 HttpOnly cookie。`?token=` 只用于首次网页登录 bootstrap，成功后要清理 URL；不要让 query token 成为脚本/API 鉴权方式。
- 语言选择逻辑必须和 `hfs/admin_service.py` 保持一致：`?lang=`、`X-Control-Language`、`Accept-Language`、`CONTROL_PLANE_DEFAULT_LANG`。
- 新增 payload 字段时区分稳定机器字段和本地化文案字段，避免管理脚本依赖中文或英文句子。

### `hfs/admin_service.py`

- `ADMIN_ENABLED=false` 时 `/_admin/` 应返回 `admin_disabled`，不要绕过默认关闭策略。
- `ADMIN_TOKEN` 缺失或错误时不能执行 action；`run-health-checks` 是只读 action，`reload-nginx` 是写 action 且必须 `confirm=true`。
- `ADMIN_FILES_ENABLED`、`ADMIN_FILES_WRITE_ENABLED` 只能作为状态/预留字段；不要据此实现 file manager、任意文件写入、terminal 或 `librefs` restart。
- 审计日志默认写入 `/data/logs/admin-audit.jsonl`，新增写 action 时必须同步审计、docs 和契约验证。

### `docs/`

- 改运行契约后优先同步 `docs/contract-alignment.md`、`docs/source-walkthrough.md`、`docs/configuration.md`、`docs/operations.md`。
- `docs/troubleshooting.md` 只记录真实遇到或高概率故障，不要加入未验证的猜测型故障。
- 文档不参与 runtime，但在 Hugging Face Space 仓库里任何提交都可能触发 rebuild；最终汇报要说明是否只是文档变更。

## Do not

- 不要提交真实密码、token、access key、secret key、root 凭证或 `.data/` 对象数据。
- 不要读取或处理 `local/`、`.env.local`，除非用户明确点名这些本地材料。
- 不要擅自 `git push hf main`；推送会触发 Hugging Face Space rebuild。
- 不要擅自 `git push origin main`；GitHub remote 也需要用户明确要求。
- 不要把 `LIBREFS_REF` 改成 `main` 来“修复”构建，除非先确认上游确实切换默认分支。
- 不要移除 `/console/` 子路径或把 Console 改到根路径；根路径属于 S3 API。
- 不要把 `/minio/health/ready` 当成业务页面；它是 health endpoint。
- 不要把 `/_ops/` 写成管理面；它只能做只读诊断。
- 不要默认开启 `/_admin/`；不要把 `ADMIN_TOKEN`、`OPS_TOKEN` 或本地 `.env.local` 的值写入仓库。
- 不要新增 `/_admin/terminal/`、file manager、任意 shell command 或 `librefs` restart，除非用户明确要求并接受风险。
- 不要把未签名浏览器访问 `/` 返回 S3 XML error 解释成故障；签名 S3 请求和公开 policy 对象 URL 才是预期访问方式。
- 不要承诺 `/data` 持久化，除非已经挂载 HF Storage Bucket 并完成重启与 rebuild 后读取验证。
- 不要新增 package manager、Node/Python/Rust 项目骨架或 CI 配置来“补测试”，除非用户明确要求。
- 不要把 docs 里的 live 状态描述成永久保证；实时状态必须回读确认。

## Validation

完成修改后，按修改范围选择最小验证。不能运行的外部步骤必须在最终汇报里明确说明。

### AGENTS-only changes

1. 确认本轮新增改动只影响 `AGENTS.md`；若工作区已有无关 dirty files，保留并在最终汇报中说明。
2. 运行 `git diff --check --` 加本轮所有变更的 `AGENTS.md` 路径。
3. 检查根 `AGENTS.md` 目标 8-16 KiB，硬上限 25 KiB。
4. 不需要远端 Space 验证。

### Documentation-only changes

1. 检查改动是否只影响目标 Markdown 或 agent 指令文件。
2. 确认 endpoint、Space/GitHub repo、Secret 名称、Variable 名称与 `docs/contract-alignment.md` 和现有 docs 一致。
3. 文档提到运行状态时避免写成未验证的实时结论；需要实时结论时运行远端状态命令。

### `README.md` front matter changes

1. 确认 `sdk: docker` 仍存在。
2. 确认 `app_port: 7860` 与 `hfs/nginx.conf`、Dockerfile 保持一致。
3. 确认 `license: agpl-3.0` 与 `LICENSE` 一致。
4. 推送后使用 Space API 检查 `stage` 和 `error`。

### `LICENSE` changes

1. 确认文件头是 `GNU AFFERO GENERAL PUBLIC LICENSE`。
2. 确认 README front matter 仍是 `license: agpl-3.0`。
3. 如来自远端合并，说明是否修正了错误的 GPL/AGPL 差异。

### `Dockerfile` changes

1. 只读检查 diff，确认仍是 Ubuntu builder/runtime 和源码构建路径。
2. 确认 runtime 仍只新增必要 `python3` 来运行 ops/admin 标准库服务。
3. 推送后查看 HF build logs。
4. Space 进入 `RUNNING` 后检查 `/minio/health/ready`、Console 静态资源和 `/_ops/health`。
5. 需要完整功能验收时，执行签名 S3 smoke test。

### `hfs/start.sh` changes

1. 确认缺少 root Secret 时会明确失败。
2. 确认公开 URL 推导、`MINIO_SERVER_URL` 去尾 `/`、覆盖值包含 `http://` 或 `https://` scheme、`MINIO_BROWSER_REDIRECT_URL` 以 `/console/` 结尾。
3. 确认 `librefs`、ops-service、admin-service、Nginx 任一退出都会导致容器退出并清理其余进程。
4. 推送后检查 runtime logs，确认 Nginx config test、API URL 和 WebUI URL 正确。

### `hfs/nginx.conf` changes

1. 运行 `nginx -t -c "$PWD/hfs/nginx.conf"` 或等价容器内检查。
2. 检查 `/_ops` -> `/_ops/`、`/_admin` -> `/_admin/`、`/console` -> `/console/`、Console JS/CSS MIME、Console iframe header、`/minio/health/ready`。
3. 如涉及上传路径、buffering 或 timeout，补充大文件上传/下载 smoke test。

### `hfs/ops_service.py` / `hfs/admin_service.py` changes

1. 运行 `python3 -m py_compile hfs/ops_service.py hfs/admin_service.py`。
2. 确认 `/_ops/config` 只返回 secret presence，不返回 secret value。
3. 确认 `/_ops/` 浏览器访问返回 dashboard，`/_ops/?format=json` 返回 JSON 索引，`/_ops/health` 等外部 API 均需要 `/_ops/` 前缀。
4. 确认 `?token=` 登录成功后设置 HttpOnly cookie 并跳转到无 token URL；header/bearer token 仍可用于脚本。
5. 确认 `ADMIN_ENABLED=false` 时 `/_admin/` 返回 `404 admin_disabled`。
6. 确认 admin 写 action 需要 `ADMIN_TOKEN` 和 `confirm=true`，并写入 audit log。
7. 确认 `?lang=zh-CN` / `X-Control-Language: zh-CN` 只影响本地化字段，不改变 `error`、path 或 action `name`。

## Notes for future agents

- 优先读取真实文件、文档和远端状态；不要根据记忆猜 Hugging Face、libreFS、Nginx 或 GitHub remote 行为。
- 核心风险是部署契约耦合：`README.md` front matter、`LICENSE`、`Dockerfile`、`hfs/start.sh`、`hfs/nginx.conf`、`hfs/ops_service.py`、`hfs/admin_service.py` 和 docs 必须一致。
- 当前服务适合测试、临时共享和轻量使用；不要包装成生产级对象存储。无法验证远端步骤时，直接列出未验证项和原因。
