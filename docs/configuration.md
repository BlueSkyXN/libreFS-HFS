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

| Variable | 必需 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `PUBLIC_BASE_URL` | 否 | `https://${SPACE_HOST}` | 公开根 URL。 |
| `LIBREFS_REF` | 否 | `master` | build-time source ref。 |
| `LIBREFS_COMMIT` | 否 | `HEAD` | build-time commit assertion。 |
| `GO_VERSION` | 否 | `1.26.3` | build-time Go version。 |

Hugging Face runtime 会提供 `SPACE_HOST`。当前 Space 的公开 host 是：

```text
blueskyxn-librefs-hfs.hf.space
```

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
| `location /` | 其余请求全部转发到 `127.0.0.1:9000`。 |

Console proxy 必须使用：

```nginx
proxy_pass http://127.0.0.1:9001/;
```

末尾 `/` 是必需的。没有它时，`/console/static/...` 会被原样转发到上游 Console，导致 JS/CSS 请求返回 HTML，Console 页面无法正常加载。

## 凭证处理原则

仓库可以记录 Secret 名称，但不能提交真实 Secret 值。Public Space 的仓库文件是公开可见的。

临时测试时可以通过 HF CLI 轮换凭证：

```bash
hf spaces secrets add BlueSkyXN/libreFS-HFS \
  -s MINIO_ROOT_USER=admin \
  -s MINIO_ROOT_PASSWORD='<new-password>'
```

修改 Secrets 会触发 Space 重启。
