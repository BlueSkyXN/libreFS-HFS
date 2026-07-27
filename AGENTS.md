# Repository agent instructions

## Purpose

本仓库是 LibreFS HFS 的 Hugging Face Docker Space 部署包装层。仓库本身不 vendored libreFS 源码；远端 Docker build 从 `https://github.com/libreFS/libreFS.git` 拉源码并编译 `librefs`，runtime 用 Nginx 在公开端口 `7860` 合并 S3 API、Web Console、只读 ops 和默认关闭的 admin control plane。

核心契约：Ubuntu builder/runtime、远端源码构建、不使用 libreFS 官方 Docker image、外部只暴露 `7860`、S3 API 在 `/`、Web Console 在 `/console/`、只读诊断面在 `/_ops/`、管理面在 `/_admin/` 且代码默认 `ADMIN_ENABLED=false`。

## Codex startup behavior

- Codex 通常从仓库根目录启动；本文件是 repo-local Root router。
- 子目录卡片只在需要时读取。修改 `hfs/`、`docs/` 或 `scripts/` 前必须先 `cat` 对应子目录 `AGENTS.md`。
- 当前跟踪的本地卡片是 `hfs/AGENTS.md`、`docs/AGENTS.md` 和 `scripts/AGENTS.md`。当前未发现 `AGENTS.override.md`。
- 不要把 README 或 docs 当作自动加载的项目指令；关键约束、命令和验证入口必须以本文件为准。
- 如果后续目标目录或其父目录出现新的 `AGENTS.md`，按从浅到深的顺序读取；同目录出现 `AGENTS.override.md` 时停止并向用户确认策略。

## Directory map

| Path | Responsibility | Local AGENTS.md | Read when |
| --- | --- | ---: | --- |
| `README.md` | HF Space card、front matter、公开 endpoint、状态摘要和文档入口 | No | 修改 `sdk`、`app_port`、license、endpoint、能力状态、health check 或文档索引时 |
| `LICENSE` | 仓库许可证，必须对齐 upstream libreFS AGPL-3.0 | No | 修改 license metadata、合规说明或合并远端 license 变化时 |
| `Dockerfile` | Ubuntu builder/runtime、Go 下载、pinned upstream source build、runtime packages、healthcheck | No | 修改 base image、build args、`LIBREFS_COMMIT`、UID/GID、复制路径或 `HEALTHCHECK` 时 |
| `hfs-dev.toml` | HFS development alignment manifest，声明 Pattern A、bundle-only build、Space root 和 release pin surface | No | 修改 HFS 分类、runtime 获取模式、required files、release hardening backlog 或 pin surface 时 |
| `hfs/` | Runtime glue：container entrypoint、Nginx、ops/admin Python services | Yes | 修改启动流程、进程监管、路由、鉴权、control plane、复制路径或容器写入路径前 |
| `docs/` | 架构、配置、部署、运维、故障排查、契约对照和源码逐文件说明 | Yes | 修改任何文档、能力状态、endpoint、生产快照、HF Variables/Secrets/Volume 表述前 |
| `scripts/` | 本地/远端契约验证和 credentialed S3 smoke 工具 | Yes | 修改 validation、smoke、SigV4、清理逻辑、远端验收或脚本参数前 |
| `.dockerignore` | Docker build context 过滤，避免 `.env*`、`local/`、临时文件进入远端 build | No | 修改 build context 或本地材料忽略规则时 |
| `.gitattributes` | Hugging Face/Git 展示和文件类型规则 | No | 修改 HF 文件类型、LFS 或展示规则时 |
| `.gitignore` | 本地 Git 忽略规则 | No | 修改 `.data/`、`.env*`、`local/`、logs 或临时文件忽略规则时 |
| `.codex/` | 本地 Codex 工作区占位目录，当前无跟踪文件 | No | 只有用户明确要求维护本地 Codex 配置时 |
| `.env.local` | 本地配置和 secret 台账，Git/Docker context 都应忽略 | No | 默认不要读取；只有用户明确点名维护本地台账时 |
| `local/` | 本地私有材料目录，Git/Docker context 都应忽略 | No | 默认不要读取或处理；只有用户明确点名 `local/` 时 |

## On-demand cat protocol

1. 修改 `hfs/`、`docs/` 或 `scripts/` 下文件前，先读取对应 `AGENTS.md`。
2. 如果目标路径未来出现嵌套 `AGENTS.md`，按根到目标目录顺序读取所有卡片。
3. 子目录卡片只覆盖对应子树；冲突时更靠近目标文件的规则优先。
4. 发现同目录 `AGENTS.override.md` 时停止修改并向用户确认，不要写会被 override 屏蔽的普通 `AGENTS.md`。

## Git remotes and branch policy

| Remote | URL | Role |
| --- | --- | --- |
| `hf` | `https://huggingface.co/spaces/BlueSkyXN/libreFS-HFS` | Hugging Face Space 部署仓库；push `main` 会触发 Space rebuild |
| `origin` | `https://github.com/BlueSkyXN/libreFS-HFS.git` | GitHub 远端仓库；用于备份、协作和 GitHub 侧同步 |

- 默认先读 `git status --short --branch` 和 `git remote -v`，不要假设当前分支、dirty state 或远端。
- 不要擅自 push 到 `hf` 或 `origin`。`git push hf main` 是 live deployment operation，必须有用户明确授权。
- 合并远端变化前，先比较 `hf/main`、`origin/main` 和本地 `main`，并保留用户未提交修改。
- 如果远端合入 `LICENSE` 变化，必须确认文件头仍是 `GNU AFFERO GENERAL PUBLIC LICENSE`，README front matter 仍是 `license: agpl-3.0`。

## Commands

本仓库没有 `package.json`、`Makefile`、`pyproject.toml`、CI workflow 或统一 test script。不要编造 install/build/test；只使用真实脚本、Git/HF CLI、Nginx 和文档中已有命令。

| Command | Purpose | Scope | Sandbox notes |
| --- | --- | --- | --- |
| `git status --short --branch` | 查看分支和 dirty state | repo | 只读 |
| `git remote -v` | 确认 `origin`/`hf` 远端 | repo | 只读 |
| `git diff --check -- <paths>` | 检查 whitespace/conflict markers | changed paths | 默认可运行 |
| `bash -n hfs/start.sh` | entrypoint shell 语法 | runtime glue | 默认可运行 |
| `bash -n scripts/validate-contract.sh scripts/smoke-s3-curl.sh` | 脚本语法 | scripts | 默认可运行 |
| `python3 -m py_compile hfs/ops_service.py hfs/admin_service.py` | Python control-plane 语法 | hfs services | 默认可运行 |
| `scripts/validate-contract.sh` | 本地轻量契约检查：front matter、Dockerfile、HFS manifest、shell/Python、Nginx pattern、license | repo | 默认可运行；本机无 `nginx` 时脚本会跳过 Nginx syntax |
| `mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi && nginx -t -c "$PWD/hfs/nginx.conf"` | Nginx syntax | `hfs/nginx.conf` | 需要本机安装 `nginx` |
| `scripts/validate-contract.sh --remote` | 契约检查加公开 health endpoint | repo + live Space | 需要网络；不读取 Secret |
| `curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready -o /dev/null -w 'health_http=%{http_code}\n'` | 公开 health check | live Space | 需要网络 |
| `MINIO_ROOT_USER=... MINIO_ROOT_PASSWORD=... scripts/smoke-s3-curl.sh` | Credentialed S3 smoke：临时 bucket/object、policy、清理 | live Space | 需要 root credentials，会修改线上对象存储；只在用户明确授权时运行 |
| `git ls-remote hf HEAD refs/heads/main` | 回读 HF Git remote head | live Git remote | 需要网络 |
| `hf spaces variables list BlueSkyXN/libreFS-HFS` | 回读 HF Variables | live Space | 需要已登录 HF CLI；不要修改 |
| `hf spaces secrets list BlueSkyXN/libreFS-HFS` | 回读 Secret key presence | live Space | 需要已登录 HF CLI；只显示 key，不显示 value |
| `hf spaces volumes list BlueSkyXN/libreFS-HFS` | 回读 Volume 挂载 | live Space | 需要已登录 HF CLI |
| `hf spaces logs BlueSkyXN/libreFS-HFS --build --tail 200` | 查看 build logs | live Space | 需要已登录 HF CLI |
| `hf spaces logs BlueSkyXN/libreFS-HFS --tail 200` | 查看 runtime logs | live Space | 需要已登录 HF CLI |

Mutating HF commands require explicit live-operation authorization: `hf spaces secrets add`, `hf spaces variables add`, `hf spaces volumes set`, `hf spaces restart`, and any `git push hf main`.

## Global rules

- 默认使用中文沟通；代码、命令、路径、配置键、API 名、库名和专有名词保留英文。
- 本仓库是公开 HF Space 部署包。可以记录 Secret 名称和 presence，不要提交真实 `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD`、`OPS_TOKEN`、`ADMIN_TOKEN`、access key、secret key 或 `.data/` 对象数据。
- 本仓库不是 upstream libreFS 源码仓库；不要 vendor、复制或手写大段 libreFS 源码。
- 当前部署策略要求 Ubuntu builder + Ubuntu runtime，并在 build 阶段从 upstream source 编译；改成官方 image 或其他 base image 前必须得到用户明确确认。
- bundle-only build 必须设置 40 位 `LIBREFS_COMMIT`，并且其值必须与 `BUILD_SOURCE.json` 的 `librefs_source_commit` 相同；Docker build 必须直接 fetch/checkout 并用 `git rev-parse HEAD` 校验。
- `README.md` front matter 的 `sdk: docker`、`app_port: 7860`、`license: agpl-3.0` 是 HF Space 行为契约。`app_port` 必须与 `Dockerfile` `EXPOSE 7860` 和 `hfs/nginx.conf` `listen 7860` 保持一致。
- Runtime 以 UID/GID `1000` 运行；Dockerfile 必须兼容 UID/GID 已存在的情况。新增 runtime 写入路径时必须确保 UID/GID `1000` 可写。
- `/data` 是对象数据和 admin audit log 默认目录。没有完成上传、重启、读取、rebuild 后再读取验证前，不要把 Volume 挂载描述成持久化已验收。
- Hugging Face Space 外部只暴露 `7860`。`9000`、`9001`、`8081`、`8082` 都是容器内部端口，不要写成外部直连端口。
- S3 client 应使用 path-style addressing；HF Space 子域名下不要推荐 virtual-hosted bucket URL。
- 避免建议或创建名为 `console`、`minio`、`_ops`、`_admin` 的公开 bucket，因为这些路径与保留路由冲突。
- 区分代码默认值和当前生产配置。`ADMIN_ENABLED` 代码默认必须是 `false`；当前线上状态必须用 HF Variables 或 `docs/contract-alignment.md` 的最新回读入口确认。

## Runtime and control-plane invariants

- `hfs/start.sh` 必须校验 `MINIO_ROOT_USER` 和 `MINIO_ROOT_PASSWORD`，推导 `PUBLIC_BASE_URL > SPACE_HOST > http://localhost:7860`，去掉 `MINIO_SERVER_URL` 尾部 `/`，并要求 `MINIO_BROWSER_REDIRECT_URL` 落在 `/console/`。
- `hfs/start.sh` 必须在启动前创建 `/tmp/nginx/*` 并执行 `nginx -t -c "$NGINX_CONF"`；`librefs`、ops-service、admin-service、Nginx 任一退出时容器应退出并清理其余进程。
- `hfs/nginx.conf` 必须保持 `/_ops/`、`/_admin/`、`/console/` 在根 `location /` 前；Console `proxy_pass` 必须剥掉 `/console/` 前缀；S3 API 仍在根路径。
- Console WebSocket/upgrade header 和 iframe/CSP header 只属于 `/console/`，不要扩展到 S3 API 根路径。
- `/_ops/` 是只读诊断面，支持 `X-Ops-Token`、bearer token 和浏览器 HttpOnly cookie。`?token=` 只用于浏览器首次登录/bootstrap，成功后跳转到无 token URL；脚本/API 不接受 query token 鉴权。
- `/_ops/config` 只能返回 secret presence 和非敏感摘要，不能返回任何 secret value。`/_ops/healthz` 是免 token liveness endpoint，只能返回 ops 服务存活状态。
- `/_admin/` 是独立管理面，代码默认关闭；开启时必须设置 `ADMIN_TOKEN`。当前 action 仅允许 `run-health-checks` 和 `reload-nginx`，其中 `reload-nginx` 必须 `confirm=true` 并写 audit log。
- ops/admin JSON 支持 `en` 和 `zh-CN`。`error`、endpoint path、action `name` 等机器字段保持稳定；`message`、`hint`、`label`、`description`、`risk`、`notes` 才本地化。
- `ADMIN_FILES_ENABLED` 和 `ADMIN_FILES_WRITE_ENABLED` 只是 status payload 预留字段，设置它们不会启用 file manager 或文件写入能力。
- 对外说明保持保守：适合测试、临时共享和轻量使用，不包装成生产级对象存储。

## Do not

- 不要读取或处理 `.env.local`、`local/`，除非用户明确点名。
- 不要提交真实密码、token、root credentials、private URL、客户数据或个人信息。
- 不要擅自 push 到 `hf` 或 `origin`；不要擅自重启 Space、改 HF Secrets/Variables/Volumes。
- 不要移除 `/console/` 子路径或把 Console 改到根路径；根路径属于 S3 API。
- 不要把未签名浏览器访问 `/` 返回 S3 XML error 解释成故障。
- 不要把 `/_ops/` 扩展成管理、写操作、命令执行、文件读取、SQL、restart 或 secret 返回入口。
- 不要默认开启 `/_admin/`；不要新增 Web terminal、file manager、bucket/policy/root credential 管理或 `librefs` restart，除非用户明确要求并重新评估风险。
- 不要新增 package manager、Node/Python/Rust 项目骨架或 CI 配置来“补测试”，除非用户明确要求。
- 不要把 docs 里的 live 状态写成永久保证；实时状态需要重新回读。

## Validation

完成修改后按范围选择最小验证。不能运行的外部步骤必须在最终汇报中明确说明。

### AGENTS-only changes

1. 确认本轮新增改动只影响 `AGENTS.md` 文件；若已有无关 dirty files，保留并说明。
2. 运行 `git diff --check -- AGENTS.md hfs/AGENTS.md docs/AGENTS.md scripts/AGENTS.md`。
3. 检查文件大小：根 `AGENTS.md` 目标 8-16 KiB，硬上限 25 KiB；子卡片目标 0.5-2 KiB。
4. 不需要远端 Space 验证。

### Documentation-only changes

1. 确认只修改目标 Markdown 或 agent 指令文件。
2. 涉及 endpoint、Space/GitHub repo、Secret 名称、Variable 名称或 live 状态时，对照 `docs/contract-alignment.md`。
3. 需要实时结论时运行 HF/Space 回读命令；否则写成快照或待验证项。

### Runtime glue changes

1. `bash -n hfs/start.sh`。
2. `python3 -m py_compile hfs/ops_service.py hfs/admin_service.py`。
3. 如修改 Nginx，运行 `nginx -t -c "$PWD/hfs/nginx.conf"` 或说明本机无 `nginx`。
4. 运行 `scripts/validate-contract.sh`。
5. 推送到 HF 后再检查 build/runtime logs、`/minio/health/ready`、Console 静态资源、`/_ops/health` 和 admin 预期状态。

### Script changes

1. `bash -n scripts/validate-contract.sh scripts/smoke-s3-curl.sh`。
2. `scripts/validate-contract.sh`。
3. 只有用户明确授权线上验收时，才运行 credentialed `scripts/smoke-s3-curl.sh`。

### README, Dockerfile, LICENSE, hfs-dev changes

1. README front matter 必须保留 `sdk: docker`、`app_port: 7860`、`license: agpl-3.0`。
2. Dockerfile 必须保持 Ubuntu builder/runtime、bundle-only source build、runtime package 最小集合、`EXPOSE 7860` 和 healthcheck。
3. `LICENSE` 文件头必须是 `GNU AFFERO GENERAL PUBLIC LICENSE`。
4. `hfs-dev.toml` 必须保持 Pattern A、`runtime_mode = "bundle-only-build"`、repo-root Space root 和 release pin surface。
5. 推送到 HF 后才做 Space API/logs/health/live smoke 复核。

## Notes for future agents

- 优先读取真实文件、脚本和远端状态；不要根据记忆猜 Hugging Face、libreFS、Nginx 或 GitHub remote 行为。
- 核心风险是部署契约耦合：README front matter、`LICENSE`、`Dockerfile`、`hfs-dev.toml`、`hfs/start.sh`、`hfs/nginx.conf`、ops/admin services、docs 和 scripts 必须一致。
- 本仓库轻量本地验证不编译 upstream libreFS；真实部署结果只能在 HF build/runtime 回读后确认。
