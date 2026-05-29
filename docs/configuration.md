# 配置参考

本文档列出 LibreFS HFS 的 build-time 和 runtime 配置项。

需要逐项查看所有 ENV 的平台、V/S/Volume/本地/不配置分类、推荐级别、默认值和建议值时，见 [环境变量参考](env-reference.md)。

## Hugging Face Space 元数据

根目录 `README.md` 的 front matter 控制 Space 行为：

```yaml
sdk: docker
app_port: 7860
license: agpl-3.0
```

| 字段 | 必需值 | 原因 |
| --- | --- | --- |
| `sdk` | `docker` | 让 Hugging Face 使用 `Dockerfile` 构建。 |
| `app_port` | `7860` | Hugging Face 外部流量进入 Nginx 的端口。 |
| `license` | `agpl-3.0` | libreFS 使用 AGPL-3.0。 |

## Docker Build Arguments

| Build arg | 默认值 | 说明 |
| --- | --- | --- |
| `UBUNTU_VERSION` | `24.04` | builder 和 runtime 都使用的 Ubuntu 版本。 |
| `APP_UID` | `1000` | runtime user id，适配 HF Docker Space。 |
| `APP_GID` | `1000` | runtime group id。 |
| `TARGETARCH` | `amd64` | 构建架构，通常由 Docker BuildKit 注入。 |
| `GO_VERSION` | `1.26.3` | 从 `go.dev` 下载的 Go 版本。 |
| `LIBREFS_REF` | `master` | 从 libreFS 上游拉取的 branch 或 tag；开发默认会跟随 upstream 移动。 |
| `LIBREFS_COMMIT` | `HEAD` | 可选精确 commit 校验；发布态必须设置为具体 upstream commit SHA。 |

当前 libreFS 上游默认分支是 `master`，不是 `main`。如果设置成 `main`，build 会报：

```text
fatal: couldn't find remote ref main
```

## Hugging Face Secrets

| Secret | 必需 | 使用方 | 说明 |
| --- | --- | --- | --- |
| `MINIO_ROOT_USER` | 是 | `hfs/start.sh`、libreFS | S3 root access key 和 Console 用户名。 |
| `MINIO_ROOT_PASSWORD` | 是 | `hfs/start.sh`、libreFS | S3 root secret key 和 Console 密码。 |
| `OPS_TOKEN` | 建议 | ops-service | `/_ops/` 只读诊断入口 token；默认 demo 值只适合快速测试。 |
| `ADMIN_TOKEN` | 开启 admin 时 | admin-service | `/_admin/` 独立 Secret/header；`ADMIN_ENABLED=true` 时必须设置。 |

`hfs/start.sh` 只会在缺少必需 root Secrets（`MINIO_ROOT_USER` 或 `MINIO_ROOT_PASSWORD`）时直接退出。这是有意设计，用来让错误配置尽早暴露。`OPS_TOKEN` 有代码默认值；`ADMIN_TOKEN` 只有在 `ADMIN_ENABLED=true` 后才成为必需项。

## Hugging Face Variables

原则：不要把和代码默认值、upstream 默认值相同的配置同步到 Hugging Face Variables。Variables 只用于表达“这个 Space 明确要覆盖默认行为”。代码默认部署下，HF Variables 可以为空；当前生产环境为了开启 admin，已显式设置 `ADMIN_ENABLED=true`。

| Variable | 必需 | 默认值 | 什么时候设置 |
| --- | --- | --- | --- |
| `PUBLIC_BASE_URL` | 否 | `https://${SPACE_HOST}` | 只有使用自定义域名或需要临时覆盖公开根 URL 时设置。 |
| `LIBREFS_REF` | 否 | `master` | 只有要临时切 upstream branch/tag 时设置。 |
| `LIBREFS_COMMIT` | 否 | `HEAD` | 发布态必须设置为具体 upstream commit SHA；长期 pin 更适合写进 `Dockerfile` 默认值。 |
| `GO_VERSION` | 否 | `1.26.3` | 只有 upstream 明确要求更换 Go 版本时设置。 |
| `ADMIN_ENABLED` | 否 | `false` | 只有明确需要打开 `/_admin/` 时设置为 `true`。 |
| `CONTROL_PLANE_DEFAULT_LANG` | 否 | `en` | 只有需要改变 `/_ops/` 和 `/_admin/` JSON 文案默认语言时设置；支持 `en`、`zh-CN`。 |

Docker Space 会把 Space Variables 作为 build-time `ARG` 传给 Docker build，也会在 runtime 注入为环境变量。因此 `GO_VERSION`、`LIBREFS_REF` 和 `LIBREFS_COMMIT` 可以通过 Space Variables 覆盖 Dockerfile 默认值。

Release reproducibility 口径：

- `LIBREFS_REF=master` + `LIBREFS_COMMIT=HEAD` 是开发默认值，不是 release pin。
- 发布态必须提供具体 `LIBREFS_COMMIT=<upstream commit sha>`，Docker build 会校验实际 checkout 的 `git rev-parse HEAD` 是否一致。
- 当前不改 runtime；Go tarball checksum 校验和 Ubuntu base image digest pin 属于后续 release hardening，不在本轮轻量对齐中引入。

Hugging Face runtime 会提供 `SPACE_HOST`。当前 Space 的公开 host 是：

```text
blueskyxn-librefs-hfs.hf.space
```

代码默认部署的推荐最小状态：

```text
HF Secrets:
- MINIO_ROOT_USER
- MINIO_ROOT_PASSWORD
- OPS_TOKEN

HF Variables:
- empty

HF Volume:
- BlueSkyXN/libreFS-HFS-storage -> /data
```

当前生产环境最近回读状态（2026-05-20）：

```text
HF Secrets:
- MINIO_ROOT_USER
- MINIO_ROOT_PASSWORD
- OPS_TOKEN
- ADMIN_TOKEN

HF Variables:
- ADMIN_ENABLED=true

HF Volume:
- BlueSkyXN/libreFS-HFS-storage -> /data
```

默认值维护规则：

- 代码已有默认值的配置留在 `Dockerfile` / `hfs/start.sh`，不要同步到 HF Variables。
- upstream libreFS 默认值保持 upstream 行为，不在 HF Variables 里重复声明。
- 需要记录“当前理解”和真实 Secret 值时，写到本地 `.env.local`，不要提交。
- 只有自定义域名、临时排障、临时切 branch/tag、或明确需要 commit pin 时，才新增 HF Variables。

## 本地 `.env.local`

可以在仓库根目录维护 `.env.local` 作为本地配置台账。它用于记录：

- HF Space id、公开 host、Storage Bucket 和挂载点。
- `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` 的真实值。
- 关键配置项的默认来源、默认值和是否建议同步到 HF。
- 临时覆盖值的候选项。

`.env.local` 不是 runtime 自动加载文件，也不是部署契约；它只是本地审计和操作前核对用的台账。仓库 `.gitignore` 应显式忽略 `.env.local`，并忽略 `.env` 和 `.env.*`，只允许提交 `.env.example` 这类不含真实 secret 的占位模板。

`.dockerignore` 也应忽略 `.env`、`.env.*` 和 `local/`，避免本地 Docker build context 把私有台账或本地材料带进镜像构建。

可提交的 ENV 字段说明见 [环境变量参考](env-reference.md)。该文档只写 key、平台、分类、默认值和建议值，不写真实地址、账号、密码、token 或其他 Secret value。

## Runtime Environment Variables

`hfs/start.sh` 支持这些可选变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DATA_DIR` | `/data` | libreFS 对象数据目录。 |
| `LIBREFS_API_ADDR` | `:9000` | 内部 S3 API bind address。 |
| `LIBREFS_CONSOLE_ADDR` | `:9001` | 内部 Console bind address。 |
| `NGINX_CONF` | `/etc/nginx/nginx.conf` | Nginx 配置文件路径。 |
| `OPS_HOST` | `127.0.0.1` | ops-service bind host；不要和 Nginx 静态路由不一致。 |
| `OPS_PORT` | `8081` | ops-service port；不要和 Nginx 静态路由不一致。 |
| `OPS_TOKEN` | `librefs_ops_demo_token` | `/_ops/` 诊断 token；公开长期运行建议用 HF Secret 覆盖。 |
| `ADMIN_ENABLED` | `false` | 是否开启 `/_admin/`。 |
| `ADMIN_HOST` | `127.0.0.1` | admin-service bind host；不要和 Nginx 静态路由不一致。 |
| `ADMIN_PORT` | `8082` | admin-service port；不要和 Nginx 静态路由不一致。 |
| `ADMIN_AUDIT_LOG` | `/data/logs/admin-audit.jsonl` | admin action 审计日志。 |
| `ADMIN_FILES_ENABLED` | `false` | 预留状态字段；当前没有 file manager，设置它不会启用文件管理功能。 |
| `ADMIN_FILES_WRITE_ENABLED` | `false` | 预留状态字段；当前没有 file manager 写入能力，设置它不会启用文件写入功能。 |
| `CONTROL_PLANE_DEFAULT_LANG` | `en` | ops/admin JSON 文案默认语言；支持 `en`、`zh-CN`。 |
| `MINIO_SERVER_URL` | 从公开根 URL 推导 | 公开 S3 endpoint。 |
| `MINIO_BROWSER_REDIRECT_URL` | `${MINIO_SERVER_URL}/console/` | 公开 Console URL。 |

除非同步修改 `hfs/nginx.conf`，不要随意修改 `LIBREFS_API_ADDR`、`LIBREFS_CONSOLE_ADDR`、`OPS_HOST`、`OPS_PORT`、`ADMIN_HOST`、`ADMIN_PORT` 和 `NGINX_CONF`。

如果覆盖 `MINIO_SERVER_URL`，值必须包含 `http://` 或 `https://` scheme，`hfs/start.sh` 会去掉多余尾部 `/`。如果覆盖 `MINIO_BROWSER_REDIRECT_URL`，值必须仍然落在 `/console/` 子路径；脚本会补齐末尾 `/`，但不会接受其他 Console 路径。

## 端口

| 端口 | 范围 | 用途 |
| --- | --- | --- |
| `7860` | 公开 / Nginx | Hugging Face Space app port。 |
| `9000` | 容器内部 | libreFS S3 API。 |
| `9001` | 容器内部 | libreFS Web Console。 |
| `8081` | 容器内部 | ops-service。 |
| `8082` | 容器内部 | admin-service。 |

HF Space 外部只暴露 `7860`。

## 路径

| 路径 | owner | 用途 |
| --- | --- | --- |
| `/data` | UID/GID `1000` | libreFS 对象数据和元数据。 |
| `/data/logs` | UID/GID `1000` | admin audit log 和未来日志白名单目录。 |
| `/tmp/nginx/*` | UID/GID `1000` | Nginx 临时目录。 |
| `/usr/local/bin/librefs` | root-owned executable | 编译出来的 libreFS binary。 |
| `/usr/local/bin/librefs-ops-service.py` | root-owned Python file | 只读 ops-service。 |
| `/usr/local/bin/librefs-admin-service.py` | root-owned Python file | 默认关闭的 admin-service。 |
| `/etc/nginx/nginx.conf` | root-owned config | 从仓库复制进去的 Nginx 配置。 |
| `/start.sh` | root-owned executable | 容器启动命令。 |

## Nginx 规则

| 规则 | 行为 |
| --- | --- |
| `location = /console` | 重定向到 `/console/`。 |
| `location = /_ops` | 重定向到 `/_ops/`。 |
| `location /_ops/` | 转发到 `127.0.0.1:8081/`，并剥掉 `/_ops/` 前缀。 |
| `location = /_admin` | 重定向到 `/_admin/`。 |
| `location /_admin/` | 转发到 `127.0.0.1:8082/`，并剥掉 `/_admin/` 前缀。 |
| `location /console/` | 转发到 `127.0.0.1:9001/`，并剥掉 `/console/` 前缀。 |
| Console iframe headers | 隐藏 upstream `X-Frame-Options`，并设置允许 Hugging Face 页面嵌入的 `Content-Security-Policy frame-ancestors`。 |
| `location /` | 其余请求全部转发到 `127.0.0.1:9000`。 |

`/_ops/` 和 `/_admin/` 必须放在 `location /` 前面，否则这些保留路径会被 S3 API 根路径吞掉。

Console proxy 必须使用：

```nginx
proxy_pass http://127.0.0.1:9001/;
```

末尾 `/` 是必需的。没有它时，`/console/static/...` 会被原样转发到上游 Console，导致 JS/CSS 请求返回 HTML，Console 页面无法正常加载。

Console 代理还会处理 iframe 相关 header：

```nginx
proxy_hide_header X-Frame-Options;
add_header Content-Security-Policy "frame-ancestors 'self' https://huggingface.co https://*.huggingface.co" always;
```

这只影响 `/console/` 代理，不改变 S3 API 根路径的 header 行为。

## Ops / Admin 配置

`/_ops/` 是只读诊断面，支持：

- `GET /_ops/`：浏览器聚合 dashboard；脚本或显式 `?format=json` 可返回 JSON 索引。
- `GET /_ops/health`
- `GET /_ops/system`
- `GET /_ops/config`
- `GET /_ops/version`
- `GET /_ops/metrics`

这些是外部公开路径，必须带 `/_ops/` 前缀。`/health`、`/system`、`/config`、`/version`、`/metrics` 只是在 Nginx 把 `/_ops/` 剥掉后传给内部 ops-service 的 handler path，不是公开 URL。

鉴权支持：

```bash
curl -H "X-Ops-Token: $OPS_TOKEN" https://your-space.hf.space/_ops/health
curl -H "Authorization: Bearer $OPS_TOKEN" https://your-space.hf.space/_ops/health
```

浏览器也支持表单登录和临时 query token 引导。`/_ops/?token=<ops-token>` 验证成功后会设置 `Secure; HttpOnly; SameSite=Lax; Path=/_ops` cookie，并跳转到不带 token 的 `/_ops/`。后续浏览器打开 `/_ops/health`、`/_ops/system` 等路径时依赖 cookie 登录态，不需要继续把 token 放在 URL 里。

`?token=` 只适合首次网页登录或临时浏览器调试，不建议写进文档、脚本、截图或分享链接。脚本和自动化应优先使用 `X-Ops-Token` 或 `Authorization: Bearer <token>`。

`/_ops/healthz` 是免 token 的内部轻量 liveness endpoint，只返回 ops 服务存活状态；它不是完整诊断 API，也不应扩展为 system/config/version/metrics。

ops/admin JSON 文案支持 `en` 和 `zh-CN`。语言选择优先级：

1. URL query：`?lang=zh-CN` 或 `?lang=en`
2. Header：`X-Control-Language: zh-CN`
3. Header：`Accept-Language`
4. 环境变量：`CONTROL_PLANE_DEFAULT_LANG`
5. 默认值：`en`

`error`、action `name`、endpoint path 等机器可读字段保持稳定；`message`、`hint`、`label`、`description`、`risk` 和 `notes` 按语言返回，避免管理界面误读操作含义。

`/_ops/config` 只返回 `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD`、`OPS_TOKEN`、`ADMIN_TOKEN` 是否存在，不返回真实值。

`/_admin/` 是独立管理面，默认关闭：

```bash
ADMIN_ENABLED=false
ADMIN_TOKEN=
```

开启时必须设置 `ADMIN_TOKEN`，并通过 `X-Admin-Token` 或 `Authorization: Bearer <token>` 认证。`ADMIN_TOKEN` 是独立配置键和请求头；它的值是否与 `OPS_TOKEN` 相同取决于当前运维策略，代码不强制两者不同。当前白名单 action 只有：

- `POST /_admin/api/actions/run-health-checks`
- `POST /_admin/api/actions/reload-nginx`

`reload-nginx` 需要 JSON body 包含 `{"confirm": true}`，并会写入 `ADMIN_AUDIT_LOG`。当前版本不提供 Web terminal、file manager、任意 shell command、bucket/policy/root credential 管理或 `librefs` restart。

## 凭证处理原则

仓库可以记录 Secret 名称，但不能提交真实 Secret 值。Public Space 的仓库文件是公开可见的。

临时测试时可以通过 HF CLI 轮换凭证：

```bash
hf spaces secrets add BlueSkyXN/libreFS-HFS \
  -s MINIO_ROOT_USER=admin \
  -s MINIO_ROOT_PASSWORD='<new-password>'
```

修改 Secrets 会触发 Space 重启。
