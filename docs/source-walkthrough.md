# 源码逐文件说明

这个项目是一个 Hugging Face Docker Space 部署包。仓库本身不包含 libreFS 源码；`Dockerfile` 会在 Hugging Face 远端 build 阶段从 `https://github.com/libreFS/libreFS.git` 拉取源码并编译二进制。

当前目标很明确：

- 使用 Ubuntu build/runtime 镜像。
- 从 libreFS upstream 源码构建。
- 不使用 libreFS 官方 Docker image。
- 只对外暴露 Hugging Face Space 的 `7860` 端口。
- 通过 Nginx 把 S3 API 和 Web Console 合并到同一个外部域名。
- 默认数据目录为 `/data`；当前 `hf spaces volumes list` 显示已挂载 Storage Bucket，但仍需按操作验收确认数据读回。

## 文件总览

| 文件 | 是否参与远端运行 | 作用 |
| --- | --- | --- |
| `README.md` | 是 | Hugging Face Space card metadata 和项目入口说明。 |
| `Dockerfile` | 是 | 定义远端 build 和 runtime 镜像。 |
| `start.sh` | 是 | 容器启动入口，负责设置 URL 环境变量、启动 libreFS 和 Nginx。 |
| `nginx.conf` | 是 | 单端口反向代理配置，把 `/` 和 `/console/` 分发到不同内部端口。 |
| `.dockerignore` | 是 | 控制 Docker build context，避免把本地临时文件送到远端 build。 |
| `.gitattributes` | 是 | Hugging Face 仓库的 LFS 类型规则。 |
| `.gitignore` | 否 | 本地 Git 忽略规则。 |
| `docs/*.md` | 否 | 文档，不参与 runtime，但会触发 Space rebuild。 |

## `README.md`

`README.md` 有两个职责。

第一，它提供 Hugging Face Space 所需的 front matter：

```yaml
---
title: LibreFS HFS
emoji: 🗄️
colorFrom: gray
colorTo: blue
sdk: docker
app_port: 7860
license: agpl-3.0
---
```

关键字段：

| 字段 | 含义 | 修改影响 |
| --- | --- | --- |
| `sdk: docker` | 告诉 HF 使用 Docker Space。 | 改错会导致 Space 不再按 Dockerfile 构建。 |
| `app_port: 7860` | 告诉 HF 外部流量转发到容器内 `7860`。 | 必须和 `nginx.conf` 的 `listen 7860` 一致。 |
| `license: agpl-3.0` | 对齐 libreFS 的 AGPL-3.0 许可证。 | 只影响仓库展示和合规标识。 |

第二，它作为快速入口，列出当前线上地址、必需 secrets、主要文档和健康检查命令。不要在 `README.md` 写真实密码；只写 secret 名称和占位符。

## `Dockerfile`

`Dockerfile` 是本项目最重要的部署契约。它分为 builder stage 和 runtime stage。

### Build Arguments

| 参数 | 默认值 | 作用 |
| --- | --- | --- |
| `UBUNTU_VERSION` | `24.04` | builder 和 runtime 都使用的 Ubuntu 版本。 |
| `APP_UID` | `1000` | runtime 用户 UID，贴合 HF Space 推荐用户。 |
| `APP_GID` | `1000` | runtime 用户 GID。 |
| `TARGETARCH` | `amd64` | Docker buildx 注入的目标架构。 |
| `GO_VERSION` | `1.26.3` | builder 阶段下载的 Go 版本。 |
| `LIBREFS_REF` | `master` | libreFS upstream branch/tag。 |
| `LIBREFS_COMMIT` | `HEAD` | 可选 commit pin，用于确保源码版本完全固定。 |

### Builder Stage

builder stage 使用 `ubuntu:${UBUNTU_VERSION}`，然后安装最小依赖：

- `ca-certificates`
- `curl`
- `git`
- `tar`

它不会使用 `golang:*` base image，而是在 Ubuntu 内下载官方 Go tarball。这样可以满足“原始 Ubuntu 镜像 + 源码构建”的部署策略。

源码拉取逻辑是：

```dockerfile
RUN git init . \
    && git remote add origin https://github.com/libreFS/libreFS.git \
    && git fetch --depth 1 origin "${LIBREFS_REF}" \
    && git checkout --detach FETCH_HEAD \
    && if [ "${LIBREFS_COMMIT}" != "HEAD" ]; then test "$(git rev-parse HEAD)" = "${LIBREFS_COMMIT}"; fi
```

这里用 `fetch --depth 1` 控制 build 成本。`LIBREFS_REF` 默认是 `master`，因为 libreFS upstream 默认分支不是 `main`。

编译命令是：

```dockerfile
go build -trimpath -buildvcs=false -ldflags="-s -w" -o /out/librefs .
```

关键点：

- `-trimpath` 减少 build path 泄漏和不必要差异。
- `-buildvcs=false` 避免 Go VCS metadata 影响构建。
- `-ldflags="-s -w"` 减小二进制体积。
- cache mount 只在 Docker build 内部使用，不会写入仓库。

### Runtime Stage

runtime stage 同样使用 `ubuntu:${UBUNTU_VERSION}`，只安装运行需要的包：

- `bash`
- `ca-certificates`
- `curl`
- `nginx`
- `tini`

UID/GID 处理逻辑是防御性的：

```dockerfile
if ! getent group "${APP_GID}" >/dev/null; then groupadd -g "${APP_GID}" app; fi
if ! getent passwd "${APP_UID}" >/dev/null; then useradd -m -u "${APP_UID}" -g "${APP_GID}" user; fi
```

这样可以避免 HF base 环境里已经存在 UID `1000` 时触发 `useradd: UID 1000 is not unique`。

runtime 只复制三个文件：

| 来源 | 目标 | 权限 |
| --- | --- | --- |
| `/out/librefs` | `/usr/local/bin/librefs` | `0755` |
| `nginx.conf` | `/etc/nginx/nginx.conf` | `0644` |
| `start.sh` | `/start.sh` | `0755` |

容器最终以 `USER ${APP_UID}:${APP_GID}` 运行，不依赖 root runtime 权限。

### Healthcheck

Docker healthcheck 访问：

```text
http://127.0.0.1:7860/minio/health/ready
```

这个请求经过 Nginx 进入 libreFS S3 API。远端公开健康检查等价地址是：

```text
https://blueskyxn-librefs-hfs.hf.space/minio/health/ready
```

## `start.sh`

`start.sh` 是 runtime 入口，由 Dockerfile 的 `CMD ["/start.sh"]` 调用。

### 启动前校验

脚本首先要求两个 secret 已存在：

```bash
: "${MINIO_ROOT_USER:?Set MINIO_ROOT_USER as a Hugging Face Space secret}"
: "${MINIO_ROOT_PASSWORD:?Set MINIO_ROOT_PASSWORD as a Hugging Face Space secret}"
```

缺少任意一个都会直接退出。这比让 libreFS 以不明确状态启动更容易排障。

### 默认路径和端口

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DATA_DIR` | `/data` | libreFS 数据目录。 |
| `LIBREFS_API_ADDR` | `:9000` | S3 API 内部监听地址。 |
| `LIBREFS_CONSOLE_ADDR` | `:9001` | Console 内部监听地址。 |
| `NGINX_CONF` | `/etc/nginx/nginx.conf` | Nginx 配置路径。 |

外部只访问 `7860`，`9000` 和 `9001` 不直接暴露给 Hugging Face 外部网络。

### Public URL 推导

脚本按以下优先级决定公开根地址：

1. `PUBLIC_BASE_URL`
2. `SPACE_HOST`
3. `http://localhost:7860`

然后导出：

| 变量 | 作用 |
| --- | --- |
| `MINIO_SERVER_URL` | S3 API 对外根地址，用于签名 URL、redirect 和 Console 调用。 |
| `MINIO_BROWSER_REDIRECT_URL` | Console 对外地址，默认是 `${MINIO_SERVER_URL}/console/`。 |

这里强制把 URL 末尾 `/` 处理清楚，是为了减少 Console 登录跳转和静态资源路径问题。

### 进程模型

脚本启动两个后台进程：

```bash
librefs server "$DATA_DIR" \
  --address "$LIBREFS_API_ADDR" \
  --console-address "$LIBREFS_CONSOLE_ADDR" &

nginx -c "$NGINX_CONF" -g "daemon off;" &
```

随后循环监控两个 PID：

- 任一进程退出，容器退出。
- 收到 `INT` 或 `TERM`，同时关闭 libreFS 和 Nginx。
- `tini` 作为 PID 1，负责更可靠地转发信号和回收进程。

## `nginx.conf`

`nginx.conf` 解决 Hugging Face Docker Space 只能对外暴露一个 app port 的限制。

内部端口：

| 内部服务 | 地址 |
| --- | --- |
| libreFS S3 API | `127.0.0.1:9000` |
| libreFS Console | `127.0.0.1:9001` |
| Nginx | `0.0.0.0:7860` |

外部路由：

| 外部路径 | 内部目标 | 说明 |
| --- | --- | --- |
| `/` | `http://127.0.0.1:9000` | S3 API 和公开对象直链。 |
| `/console/` | `http://127.0.0.1:9001/` | Web Console。 |
| `/console` | `308 /console/` | 规范化 Console URL。 |

### Console `proxy_pass` 的尾部斜杠

Console 路由必须保留：

```nginx
proxy_pass http://127.0.0.1:9001/;
```

这里的尾部 `/` 很关键。没有它时，`/console/static/...` 可能会被错误转发成 Console 后端无法识别的路径，最终表现为 JS/CSS MIME type 错误或 Console 空白。

### S3 API 放在根路径

S3 API 保留在根路径是为了让公开对象直链保持最简单：

```text
https://blueskyxn-librefs-hfs.hf.space/<bucket>/<object>
```

如果把 Console 放到根路径，S3 endpoint 就需要迁移到子路径；这会影响 S3 client、签名 URL 和直链语义，不符合当前目标。

### 代理 Header

Nginx 会传递：

- `Host`
- `X-Real-IP`
- `X-Forwarded-For`
- `X-Forwarded-Proto`
- `X-Forwarded-Host`
- `X-Forwarded-Port`

这些 header 影响 Console redirect、公开 URL 推导和反向代理后的请求识别。修改时要同步验证 Console 登录、S3 signed request 和公开对象 URL。

Console 代理层还会隐藏 upstream `X-Frame-Options`，并添加 `Content-Security-Policy frame-ancestors`，用于允许 Hugging Face Space 页面通过 iframe 嵌入 Console。这个处理只放在 `/console/`，不要扩展到 S3 API 根路径，避免影响对象访问语义。

## `.dockerignore`

`.dockerignore` 用来减少 Docker build context，避免把本地状态送到 HF 远端 build。

当前忽略：

| 规则 | 含义 |
| --- | --- |
| `.git` | 不把本地 Git 历史送入 Docker build context。 |
| `.gitignore` | runtime 不需要。 |
| `.DS_Store` | macOS 本地文件。 |
| `*.log` | 本地日志。 |
| `.env` / `.env.*` | 本地环境和 secret 台账。 |
| `.data` | 本地测试数据目录。 |
| `local` | 本地材料目录，不进入 build context。 |
| `tmp` / `temp` | 临时目录。 |

不要把 `README.md`、`Dockerfile`、`start.sh`、`nginx.conf` 或 `docs/` 加进 `.dockerignore`。其中 `README.md` 是 Space 元数据来源，`Dockerfile`/`start.sh`/`nginx.conf` 是构建和运行必需文件。

## `.gitignore`

`.gitignore` 只影响本地 Git 工作区，不影响已经被 Git 跟踪的文件，也不直接影响 Docker build。

当前忽略：

| 规则 | 含义 |
| --- | --- |
| `.DS_Store` | macOS Finder 元数据。 |
| `.data/` | 本地临时数据目录。 |
| `*.log` | 本地日志。 |
| `.env` / `.env.*` | 本地环境和 secret 台账；`.env.example` 可提交。 |
| `/local` | 本地材料目录，不参与仓库提交。 |

如果需要本地模拟数据，优先放在 `.data/`；本地材料放在 `local/`。两者都不要提交到 Space 仓库。

## `.gitattributes`

`.gitattributes` 主要保留 Hugging Face 仓库常见的大文件 LFS 规则，例如模型、压缩包、数据文件和 tensor 文件。

当前项目理论上不应该提交这些大文件。保留这份规则的目的有两个：

1. 如果误提交大二进制，HF/Git LFS 更容易正确处理。
2. 和 Hugging Face Space 仓库的默认习惯保持一致。

不要把普通文本配置、shell 脚本或 Markdown 文档加到 LFS 规则里。

## `docs/`

`docs/` 是项目的长期说明目录。文档本身不参与容器 runtime，但在 Hugging Face Space 仓库里，任何提交都会触发 rebuild。

当前文档职责：

| 文档 | 职责 |
| --- | --- |
| `docs/README.md` | 文档索引和线上实例状态。 |
| `docs/architecture.md` | 架构、请求流和运行模型。 |
| `docs/deployment-huggingface.md` | HF Space 部署、Secrets、Variables、日志和首次检查。 |
| `docs/configuration.md` | 所有 build/runtime 配置项。 |
| `docs/usage.md` | Console、S3 client、公开直链和 bucket policy 使用方式。 |
| `docs/operations.md` | 健康检查、smoke test、日志、重启和风险矩阵。 |
| `docs/troubleshooting.md` | 已遇到过的真实故障和判断方法。 |
| `docs/source-walkthrough.md` | 仓库逐文件说明和修改边界。 |

## 修改边界

### 改 `Dockerfile` 后必须验证

- HF build 是否成功。
- Space runtime 是否进入 `RUNNING`。
- `/minio/health/ready` 是否返回 `200`。
- Console `/console/` 是否能加载静态资源。
- S3 signed request 是否仍可用。

### 改 `start.sh` 后必须验证

- 缺少 secret 时是否明确失败。
- `PUBLIC_BASE_URL` / `SPACE_HOST` 推导是否正确。
- `MINIO_SERVER_URL` 是否没有多余尾部 `/`。
- `MINIO_BROWSER_REDIRECT_URL` 是否以 `/console/` 结尾。
- libreFS 和 Nginx 任一退出时容器是否能退出。

### 改 `nginx.conf` 后必须验证

- 根路径仍是 S3 API。
- `/console` 会跳转到 `/console/`。
- `/console/static/...` 返回正确 JS/CSS MIME。
- `/console/` 响应不再暴露 `X-Frame-Options: DENY`，并包含允许 Hugging Face 页面嵌入的 `frame-ancestors`。
- 上传大文件不会被 Nginx buffering 或 body size 限制拦住。

### 改 `README.md` front matter 后必须验证

- HF Space 仍识别为 Docker Space。
- `app_port` 仍为 `7860`。
- Space 页面 metadata 正常显示。

## 当前验收命令

查看远端 Space 状态：

```bash
curl -fsSL https://huggingface.co/api/spaces/BlueSkyXN/libreFS-HFS
```

健康检查：

```bash
curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready
```

查看 build/runtime logs：

```bash
hf spaces logs BlueSkyXN/libreFS-HFS --build --tail 200
hf spaces logs BlueSkyXN/libreFS-HFS --tail 200
```

查看是否挂载 Storage Bucket：

```bash
hf spaces volumes list BlueSkyXN/libreFS-HFS
```

当前 `hf spaces volumes list` 显示已挂载 `BlueSkyXN/libreFS-HFS-storage` 到 `/data`。挂载状态仍应通过上传对象、重启 Space、读取对象、rebuild 后再次读取来验收。
