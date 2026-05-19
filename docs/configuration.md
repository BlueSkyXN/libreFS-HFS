# 配置参考

本文档列出 LibreFS HFS 的 build-time 和 runtime 配置项。

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
| `LIBREFS_REF` | `master` | 从 libreFS 上游拉取的 branch 或 tag。 |
| `LIBREFS_COMMIT` | `HEAD` | 可选精确 commit 校验。 |

当前 libreFS 上游默认分支是 `master`，不是 `main`。如果设置成 `main`，build 会报：

```text
fatal: couldn't find remote ref main
```

## Hugging Face Secrets

| Secret | 必需 | 使用方 | 说明 |
| --- | --- | --- | --- |
| `MINIO_ROOT_USER` | 是 | `start.sh`、libreFS | S3 root access key 和 Console 用户名。 |
| `MINIO_ROOT_PASSWORD` | 是 | `start.sh`、libreFS | S3 root secret key 和 Console 密码。 |

`start.sh` 会在缺少任一 Secret 时直接退出。这是有意设计，用来让错误配置尽早暴露。

## Hugging Face Variables

原则：不要把和代码默认值、upstream 默认值相同的配置同步到 Hugging Face Variables。Variables 只用于表达“这个 Space 明确要覆盖默认行为”。当前默认部署下，HF Variables 可以为空。

| Variable | 必需 | 默认值 | 什么时候设置 |
| --- | --- | --- | --- |
| `PUBLIC_BASE_URL` | 否 | `https://${SPACE_HOST}` | 只有使用自定义域名或需要临时覆盖公开根 URL 时设置。 |
| `LIBREFS_REF` | 否 | `master` | 只有要临时切 upstream branch/tag 时设置。 |
| `LIBREFS_COMMIT` | 否 | `HEAD` | 只有要在 HF Variables 层做精确 commit pin 时设置；长期 pin 更适合写进 `Dockerfile` 默认值。 |
| `GO_VERSION` | 否 | `1.26.3` | 只有 upstream 明确要求更换 Go 版本时设置。 |

Docker Space 会把 Space Variables 作为 build-time `ARG` 传给 Docker build，也会在 runtime 注入为环境变量。因此 `GO_VERSION`、`LIBREFS_REF` 和 `LIBREFS_COMMIT` 可以通过 Space Variables 覆盖 Dockerfile 默认值。

Hugging Face runtime 会提供 `SPACE_HOST`。当前 Space 的公开 host 是：

```text
blueskyxn-librefs-hfs.hf.space
```

当前线上 Space 的推荐最小状态：

```text
HF Secrets:
- MINIO_ROOT_USER
- MINIO_ROOT_PASSWORD

HF Variables:
- empty

HF Volume:
- BlueSkyXN/libreFS-HFS-storage -> /data
```

默认值维护规则：

- 代码已有默认值的配置留在 `Dockerfile` / `start.sh`，不要同步到 HF Variables。
- upstream libreFS 默认值保持 upstream 行为，不在 HF Variables 里重复声明。
- 需要记录“当前理解”和真实 Secret 值时，写到本地 `.env.local`，不要提交。
- 只有自定义域名、临时排障、临时切 branch/tag、或明确需要 commit pin 时，才新增 HF Variables。

## 本地 `.env.local`

可以在仓库根目录维护 `.env.local` 作为本地配置台账。它用于记录：

- HF Space id、公开 host、Storage Bucket 和挂载点。
- `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` 的真实值。
- 关键配置项的默认来源、默认值和是否建议同步到 HF。
- 临时覆盖值的候选项。

`.env.local` 不是 runtime 自动加载文件，也不是部署契约；它只是本地审计和操作前核对用的台账。仓库 `.gitignore` 应忽略 `.env` 和 `.env.*`，只允许提交 `.env.example` 这类不含真实 secret 的占位模板。

`.dockerignore` 也应忽略 `.env`、`.env.*` 和 `local/`，避免本地 Docker build context 把私有台账或本地材料带进镜像构建。

## Runtime Environment Variables

`start.sh` 支持这些可选变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DATA_DIR` | `/data` | libreFS 对象数据目录。 |
| `LIBREFS_API_ADDR` | `:9000` | 内部 S3 API bind address。 |
| `LIBREFS_CONSOLE_ADDR` | `:9001` | 内部 Console bind address。 |
| `NGINX_CONF` | `/etc/nginx/nginx.conf` | Nginx 配置文件路径。 |
| `MINIO_SERVER_URL` | 从公开根 URL 推导 | 公开 S3 endpoint。 |
| `MINIO_BROWSER_REDIRECT_URL` | `${MINIO_SERVER_URL}/console/` | 公开 Console URL。 |

除非同步修改 `nginx.conf`，不要随意修改 `LIBREFS_API_ADDR`、`LIBREFS_CONSOLE_ADDR` 和 `NGINX_CONF`。

如果覆盖 `MINIO_SERVER_URL`，值必须包含 `http://` 或 `https://` scheme，`start.sh` 会去掉多余尾部 `/`。如果覆盖 `MINIO_BROWSER_REDIRECT_URL`，值必须仍然落在 `/console/` 子路径；脚本会补齐末尾 `/`，但不会接受其他 Console 路径。

## 端口

| 端口 | 范围 | 用途 |
| --- | --- | --- |
| `7860` | 公开 / Nginx | Hugging Face Space app port。 |
| `9000` | 容器内部 | libreFS S3 API。 |
| `9001` | 容器内部 | libreFS Web Console。 |

HF Space 外部只暴露 `7860`。

## 路径

| 路径 | owner | 用途 |
| --- | --- | --- |
| `/data` | UID/GID `1000` | libreFS 对象数据和元数据。 |
| `/tmp/nginx/*` | UID/GID `1000` | Nginx 临时目录。 |
| `/usr/local/bin/librefs` | root-owned executable | 编译出来的 libreFS binary。 |
| `/etc/nginx/nginx.conf` | root-owned config | 从仓库复制进去的 Nginx 配置。 |
| `/start.sh` | root-owned executable | 容器启动命令。 |

## Nginx 规则

| 规则 | 行为 |
| --- | --- |
| `location = /console` | 重定向到 `/console/`。 |
| `location /console/` | 转发到 `127.0.0.1:9001/`，并剥掉 `/console/` 前缀。 |
| Console iframe headers | 隐藏 upstream `X-Frame-Options`，并设置允许 Hugging Face 页面嵌入的 `Content-Security-Policy frame-ancestors`。 |
| `location /` | 其余请求全部转发到 `127.0.0.1:9000`。 |

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

## 凭证处理原则

仓库可以记录 Secret 名称，但不能提交真实 Secret 值。Public Space 的仓库文件是公开可见的。

临时测试时可以通过 HF CLI 轮换凭证：

```bash
hf spaces secrets add BlueSkyXN/libreFS-HFS \
  -s MINIO_ROOT_USER=admin \
  -s MINIO_ROOT_PASSWORD='<new-password>'
```

修改 Secrets 会触发 Space 重启。
