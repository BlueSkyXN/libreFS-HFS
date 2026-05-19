# Repository agent instructions

## Purpose

本仓库是 LibreFS HFS 的 Hugging Face Docker Space 部署包装层。仓库不 vendored libreFS 源码；远端 Docker build 从 `https://github.com/libreFS/libreFS.git` 拉源码并编译 `librefs`，runtime 用 Nginx 在公开端口 `7860` 合并 S3 API 和 Web Console。

核心契约：Ubuntu builder/runtime、远端源码构建、不使用 libreFS 官方 Docker image、外部只暴露 `7860`、S3 API 在 `/`、Web Console 在 `/console/`。

## Codex startup behavior

- Codex 通常从仓库根目录启动；本文件是 repo-local 启动期主规则和目录 router。
- 当前仓库只有根 `AGENTS.md`，没有子目录 `AGENTS.md`，也没有 `AGENTS.override.md`。
- 未来如果目标路径或其父目录新增 `AGENTS.md`，修改对应子树前必须先执行 `cat <path>/AGENTS.md` 读取本地规则。
- 如果路径上出现多层 `AGENTS.md`，从浅到深读取；冲突时更靠近目标文件的规则优先。
- 如果发现同目录 `AGENTS.override.md`，停止修改并让用户确认 override 策略，不要继续改会被屏蔽的普通 `AGENTS.md`。
- 不要把 README 或 docs 当作自动加载的项目指令；关键部署约束、命令和验证标准必须在本文件里复述。

## Directory map

| Path | Responsibility | Local AGENTS.md | Read when |
| --- | --- | ---: | --- |
| `README.md` | HF Space metadata、项目入口、endpoint、Secrets、能力状态 | No | 修改 front matter、公开地址、状态表、health check、文档索引时 |
| `LICENSE` | 仓库许可证文本，应对齐 libreFS 上游 AGPL-3.0 | No | 修改 license metadata、合规说明或合并许可证文件时 |
| `Dockerfile` | 远端 build/runtime 镜像契约、Go 下载、源码编译、runtime packages、healthcheck | No | 修改 base image、build args、上游源码 ref、UID/GID、runtime packages、`HEALTHCHECK` 时 |
| `start.sh` | 容器启动入口；校验 Secrets、推导公开 URL、启动并监控 libreFS/Nginx | No | 修改环境变量、端口、URL 推导、进程管理、signal handling 时 |
| `nginx.conf` | 单端口反向代理；`/` -> S3 API，`/console/` -> Web Console | No | 修改路由、proxy header、buffering、timeout、body size、Console 子路径、iframe/CSP header 时 |
| `.dockerignore` | Docker build context 过滤，避免本地状态进入 Hugging Face build | No | 修改 build context 或临时文件忽略规则时 |
| `.gitattributes` | Hugging Face 仓库展示/LFS 类型规则 | No | 修改 HF 文件类型或大文件规则时 |
| `.gitignore` | 本地 Git 忽略规则 | No | 修改 `.data/`、logs、临时文件忽略规则时 |
| `docs/` | 架构、配置、部署、使用、运维、故障排查和源码逐文件说明 | No | 修改任何运行契约后同步文档，或用户明确要求更新说明时 |
| `.codex/` | 本地 Codex 工作区占位目录，当前没有跟踪文件 | No | 只有用户要求维护本地 agent/skill 配置时 |

## On-demand cat protocol

当前没有本地子卡片。未来如果目标路径或其父目录出现 `AGENTS.md`：

1. 修改前先运行 `cat <path>/AGENTS.md`。
2. 如果路径上有多个 `AGENTS.md`，按从根到目标目录的顺序读取。
3. 只把子卡片用于它覆盖的子树，不要把局部规则泛化到整个仓库。
4. 如果发现同目录 `AGENTS.override.md`，停止修改并让用户确认 override 策略。

## Git remotes and branch policy

当前仓库有两个远端，职责不同：

| Remote | URL | Role |
| --- | --- | --- |
| `origin` | `https://huggingface.co/spaces/BlueSkyXN/libreFS-HFS` | Hugging Face Space 部署仓库；推送 `main` 会触发 Space rebuild |
| `github` | `https://github.com/BlueSkyXN/libreFS-HFS.git` | GitHub 远端仓库；用于备份、协作、同步 GitHub 侧变化 |

Rules:

- 默认先读 `git status --short --branch` 和 `git remote -v`，不要假设当前分支或远端。
- 不要擅自 `git push origin main`；这会触发 Hugging Face Space rebuild。
- 不要擅自 push 到 `github`；用户只说“合并/审查”时先完成本地合并建议或本地提交。
- 合并远端变化前，先比较 `origin/main`、`github/main` 和本地 `main`，并保留用户未提交修改；提交前必须确认 staged 范围。
- 如果 GitHub 远端修改 `LICENSE`，必须确认仍是 `GNU Affero General Public License v3.0`，因为 libreFS 上游和 README 都是 AGPL-3.0。

## Commands

本仓库没有 `package.json`、`Makefile`、`pyproject.toml`、CI workflow 或统一本地 test script。不要编造 install/build/test 命令。下面命令来自当前文件、Dockerfile、`start.sh`、Hugging Face CLI help 和 docs。

| Command | Purpose | Scope | Sandbox notes |
| --- | --- | --- | --- |
| `git status --short --branch` | 查看当前分支和未提交改动 | local repo | 只读；默认可运行 |
| `git remote -v` | 确认 `origin` / `github` 远端职责 | local repo | 只读；默认可运行 |
| `git diff --check` | 检查 whitespace/error marker | local repo | 只读；默认可运行 |
| `mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi && nginx -t -c "$PWD/nginx.conf"` | 本地校验 Nginx 配置语法 | `nginx.conf` | 需要本机安装 `nginx`；不启动服务 |
| `nginx -t -c "$NGINX_CONF"` | runtime 启动前校验 Nginx 配置 | container runtime | 容器内命令；需先创建 `/tmp/nginx/*` 临时目录 |
| `curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready -o /dev/null -w 'health_http=%{http_code}\n'` | 检查公开健康端点 | remote Space | 需要网络；预期 `health_http=200` |
| `curl -fsSL https://huggingface.co/api/spaces/BlueSkyXN/libreFS-HFS` | 查看 Space runtime 状态 JSON | remote Space | 需要网络；可接 `jq '{sha, stage: .runtime.stage, error: .runtime.errorMessage, host}'` |
| `git ls-remote origin HEAD refs/heads/main` | 推送后确认 Hugging Face remote head | Git remote | 只读但需要网络；只在需要比对远端时运行 |
| `curl -fsSI https://blueskyxn-librefs-hfs.hf.space/console/static/js/main.45669c2e.js` | 检查 Console JS MIME | remote Space | 需要网络；asset 文件名可能随上游变化 |
| `curl -fsSI https://blueskyxn-librefs-hfs.hf.space/console/static/css/main.e60e4760.css` | 检查 Console CSS MIME | remote Space | 需要网络；asset 文件名可能随上游变化 |
| `curl -fsSI https://blueskyxn-librefs-hfs.hf.space/console/ \| tr -d '\r' \| grep -Ei '^(x-frame-options\|content-security-policy):'` | 检查 Console iframe header | remote Space | 需要网络；修复后不应暴露 `x-frame-options`，CSP 应包含 `frame-ancestors` |
| `hf spaces logs BlueSkyXN/libreFS-HFS --build --tail 200` / `hf spaces logs BlueSkyXN/libreFS-HFS --tail 200` | 查看 build/runtime logs | remote Space | 需要 Hugging Face CLI、网络、可能需要登录状态 |
| `hf spaces volumes list BlueSkyXN/libreFS-HFS` | 检查是否挂载 Storage Bucket | remote Space | 需要 Hugging Face CLI、网络、可能需要登录状态 |

Mutating Hugging Face commands such as `hf spaces secrets add`、`hf spaces variables add`、`hf spaces volumes set`、`hf spaces restart` must not be run unless the user explicitly asks for that live operation.

Current `hf` help: `spaces variables add` uses `-e` / `--env`; `spaces volumes set` uses `-v` / `--volume`; docs examples use `spaces secrets add -s`.

## Global rules

- 默认使用中文沟通；代码、命令、配置键、路径和专有名词保持英文。
- 本仓库是公开 HF Space 部署包。可记录 Secret 名称，但不要提交真实 `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD`、token 或 key。
- 本仓库不是上游 libreFS 源码仓库；不要 vendor、复制或手写大段 libreFS 源码。
- 当前部署策略明确要求 Ubuntu builder + Ubuntu runtime，不使用 libreFS 官方 Docker image。改这个策略前必须得到用户明确确认。
- libreFS upstream 默认 ref 当前写为 `master`。不要把 `LIBREFS_REF` 改成 `main`，除非先用只读命令确认上游默认分支已变化，并同步更新 docs。
- `LIBREFS_COMMIT=HEAD` 表示不 pin 精确 commit；如果改成具体 commit，Docker build 中的 `git rev-parse HEAD` 校验必须保留。
- `README.md` front matter 的 `sdk: docker` 和 `app_port: 7860` 是 HF Space 行为契约。`app_port` 必须与 `nginx.conf` 的 `listen 7860` 和 Dockerfile `EXPOSE 7860` 保持一致。
- `license: agpl-3.0`、`LICENSE` 文件和上游 libreFS 许可证必须保持一致。不要把许可证降级或改成普通 GPL。
- Runtime 以 UID/GID `1000` 运行，但 Dockerfile 必须兼容 UID/GID 已存在的情况；不要退回无条件 `useradd -m -u 1000 user`。
- Runtime 不应依赖 root 权限；新增 runtime 写入路径时必须确保 UID/GID `1000` 可写。
- `/data` 是对象数据目录；没有挂载 Hugging Face Storage Bucket 时数据不保证持久。
- Hugging Face Space 外部只暴露 `7860`。`9000` 和 `9001` 是容器内部端口，不要在文档或配置里描述成外部直连端口。
- S3 client 应使用 path-style addressing；HF Space 子域名下不要推荐 virtual-hosted bucket URL。
- 避免建议或创建名为 `console`、`minio` 的公开 bucket，因为这些路径与 Console 和健康检查路由冲突。
- 对外说明要保守：适合测试、临时共享和轻量使用，不建议作为生产对象存储。

## File-specific rules

### `README.md`

- README 同时是 HF Space card；front matter 会影响远端构建与展示。
- 保留 `sdk: docker`、`app_port: 7860`、`license: agpl-3.0`，除非有明确证据和用户确认。
- 可以写公开 endpoint、Console URL、Secret/Variable 名称和占位符；不要写真实 secret value，也不要把一次 spot check 写成长期保证。
- 修改 health check、endpoint 或 public object URL 示例时，同步 `docs/usage.md` 和 `docs/operations.md`。

### `LICENSE`

- `LICENSE` 应是 `GNU Affero General Public License v3.0`，对齐上游 libreFS。
- 如果从 GitHub remote 合入普通 `GNU General Public License v3.0`，应修正为 AGPL-3.0。
- 不要手写许可证文本；需要刷新时从上游 libreFS 或 FSF 官方文本核对。

### `Dockerfile`

- 保留多阶段结构：builder 编译 `/out/librefs`，runtime 只复制 `librefs`、`nginx.conf`、`start.sh`。
- Builder 依赖保持最小：`ca-certificates`、`curl`、`git`、`tar`。
- Go 通过 `GO_VERSION` 下载官方 tarball；修改时同步 `README.md` 和 `docs/configuration.md`。
- `TARGETARCH` 当前只接受 `amd64|arm64`；扩展前确认 Go tarball 名称和 HF buildx 行为。
- 保留 `go build -trimpath -buildvcs=false -ldflags="-s -w"` 和 BuildKit cache mount。
- Runtime 只安装必需包：`bash`、`ca-certificates`、`curl`、`nginx`、`tini`。
- `HEALTHCHECK` 应继续访问 `http://127.0.0.1:7860/minio/health/ready`。

### `start.sh`

- 保持 `set -Eeuo pipefail`。
- 启动前必须校验 `MINIO_ROOT_USER` 和 `MINIO_ROOT_PASSWORD`，缺失时直接失败。
- 公开 URL 优先级：`PUBLIC_BASE_URL` > `SPACE_HOST` > `http://localhost:7860`。
- `MINIO_SERVER_URL` 必须去掉末尾 `/`；`MINIO_BROWSER_REDIRECT_URL` 必须以 `/console/` 结尾。
- 执行 `nginx -t -c "$NGINX_CONF"` 前必须创建 `/tmp/nginx/*` 临时目录。
- libreFS 和 Nginx 必须都被监控；任一进程退出时容器应退出并清理另一个进程。修改 signal handling 后检查 `tini`、`INT`、`TERM`。

### `nginx.conf`

- 保留 `listen 7860`，除非同时修改 HF `app_port`、Dockerfile `EXPOSE` 和文档。
- `location = /console` 继续重定向到 `/console/`。
- `location /console/` 的 `proxy_pass` 必须是 `http://127.0.0.1:9001/;`，末尾 `/` 用来剥掉 `/console/` 前缀。
- `location /` 继续转发到 `http://127.0.0.1:9000`，这是 S3 API 根路径。
- 保留 `client_max_body_size 0`、buffering off 和必要 forwarded headers。
- WebSocket/upgrade header 只应用在 Console 代理中；S3 API location 保持简单连接行为。
- Console iframe header 处理只放在 `/console/`，不要扩展到 S3 API 根路径。

### `docs/`

- 改运行契约后优先同步 `docs/source-walkthrough.md`、`docs/configuration.md`、`docs/operations.md`。
- `docs/troubleshooting.md` 只记录真实遇到或高概率故障，不要加入未验证的猜测型故障。
- 文档不参与 runtime，但在 Hugging Face Space 仓库里任何提交都可能触发 rebuild；最终汇报要说明是否只是文档变更。

## Do not

- 不要提交真实密码、token、access key、secret key、root 凭证或 `.data/` 对象数据。
- 不要执行会修改远端 Space 的 `hf spaces ...` 命令，除非用户明确要求。
- 不要擅自 `git push origin main`；推送会触发 Hugging Face Space rebuild。
- 不要擅自 `git push github main`；GitHub remote 也需要用户明确要求。
- 不要把 `LIBREFS_REF` 改成 `main` 来“修复”构建，除非先确认上游确实切换默认分支。
- 不要移除 `/console/` 子路径或把 Console 改到根路径；根路径属于 S3 API。
- 不要把 `/minio/health/ready` 当成业务页面；它是 health endpoint。
- 不要把未签名浏览器访问 `/` 返回 S3 XML error 解释成故障；签名 S3 请求和公开 policy 对象 URL 才是预期访问方式。
- 不要承诺 `/data` 持久化，除非已经挂载 HF Storage Bucket 并完成重启与 rebuild 后读取验证。
- 不要新增 package manager、Node/Python/Rust 项目骨架或 CI 配置来“补测试”，除非用户明确要求。
- 不要把 docs 里的 live 状态描述成永久保证；实时状态必须回读确认。

## Validation

完成修改后，按修改范围选择最小验证。不能运行的外部步骤必须在最终汇报里明确说明。

### AGENTS-only changes

1. 确认改动只影响 `AGENTS.md`。
2. 运行 `git diff --check -- AGENTS.md`。
3. 检查根 `AGENTS.md` 目标 8-16 KiB，硬上限 25 KiB。
4. 不需要远端 Space 验证。

### Documentation-only changes

1. 检查改动是否只影响目标 Markdown 或 agent 指令文件。
2. 确认 endpoint、Space/GitHub repo、Secret 名称、Variable 名称与现有 docs 一致。
3. 文档提到运行状态时避免写成未验证的实时结论；需要实时结论时运行远端状态命令。

### `README.md` front matter changes

1. 确认 `sdk: docker` 仍存在。
2. 确认 `app_port: 7860` 与 `nginx.conf`、Dockerfile 保持一致。
3. 确认 `license: agpl-3.0` 与 `LICENSE` 一致。
4. 推送后使用 Space API 检查 `stage` 和 `error`。

### `LICENSE` changes

1. 确认文件头是 `GNU AFFERO GENERAL PUBLIC LICENSE`。
2. 确认 README front matter 仍是 `license: agpl-3.0`。
3. 如来自远端合并，说明是否修正了错误的 GPL/AGPL 差异。

### `Dockerfile` changes

1. 只读检查 diff，确认仍是 Ubuntu builder/runtime 和源码构建路径。
2. 推送后查看 HF build logs。
3. Space 进入 `RUNNING` 后检查 `/minio/health/ready` 和 Console 静态资源。
4. 需要完整功能验收时，执行签名 S3 smoke test。

### `start.sh` changes

1. 确认缺少 root Secret 时会明确失败。
2. 确认公开 URL 推导、`MINIO_SERVER_URL` 去尾 `/`、`MINIO_BROWSER_REDIRECT_URL` 以 `/console/` 结尾。
3. 推送后检查 runtime logs，确认 Nginx config test、API URL 和 WebUI URL 正确。

### `nginx.conf` changes

1. 运行 `nginx -t -c "$PWD/nginx.conf"` 或等价容器内检查。
2. 检查 `/console` -> `/console/`、Console JS/CSS MIME、Console iframe header、`/minio/health/ready`。
3. 如涉及上传路径、buffering 或 timeout，补充大文件上传/下载 smoke test。

## Notes for future agents

- 优先读取真实文件、真实文档和真实远端状态；不要根据记忆猜 Hugging Face、libreFS、Nginx 或 GitHub remote 行为。
- 核心风险是部署契约耦合：`README.md` front matter、`LICENSE`、`Dockerfile`、`start.sh`、`nginx.conf` 和 docs 必须互相一致。
- 当前服务适合测试、临时共享和轻量使用；不要包装成生产级对象存储。
- 用户通常希望任务落到实际文件和验证结果；如果无法验证远端步骤，直接列出未验证项和原因。
