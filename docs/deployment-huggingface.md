# Hugging Face 部署指南

本文档说明如何在 Hugging Face Space 上部署、配置、重建和验证 LibreFS HFS。

## Space 仓库

```text
https://huggingface.co/spaces/BlueSkyXN/libreFS-HFS
```

Space 必须使用 Docker SDK。根目录 `README.md` 的 front matter 必须包含：

```yaml
sdk: docker
app_port: 7860
```

## 必需 Secrets

在 Space Settings 中配置：

| Secret | 示例 | 必需 |
| --- | --- | --- |
| `MINIO_ROOT_USER` | `admin` | 是 |
| `MINIO_ROOT_PASSWORD` | 强随机密码 | 是 |
| `OPS_TOKEN` | 强随机值 | 建议 |
| `ADMIN_TOKEN` | 强随机值 | 仅开启 admin 时 |

不要把真实凭证提交进仓库。Public Space 的源码文件是公开可见的。

使用 Hugging Face CLI 配置：

```bash
hf spaces secrets add BlueSkyXN/libreFS-HFS \
  -s MINIO_ROOT_USER=admin \
  -s MINIO_ROOT_PASSWORD='<strong-password>' \
  -s OPS_TOKEN='<strong-ops-token>'
```

如果当前生产策略需要开启 `/_admin/`，还需要设置：

```bash
hf spaces secrets add BlueSkyXN/libreFS-HFS \
  -s ADMIN_TOKEN='<strong-admin-token>'
hf spaces variables add BlueSkyXN/libreFS-HFS \
  -e ADMIN_ENABLED=true
```

查看已配置的 Secret 名称：

```bash
hf spaces secrets list BlueSkyXN/libreFS-HFS
```

这个命令只显示 key，不显示 value。

## 可选 Variables

代码默认部署不需要配置 HF Variables。不要把和代码默认值或 upstream 默认值相同的变量同步到 Hugging Face；这会让云端配置看起来像有很多“特殊设置”，实际只是噪音。当前生产环境为了开启 admin，已显式设置 `ADMIN_ENABLED=true`。

| Variable | 默认值 | 什么时候设置 |
| --- | --- | --- |
| `PUBLIC_BASE_URL` | `https://${SPACE_HOST}` | 使用自定义域名或需要覆盖公开 URL 时设置。 |
| `LIBREFS_REF` | `master` | 临时切换上游 tag、branch 时设置。 |
| `LIBREFS_COMMIT` | `HEAD` | 开发默认不 pin；发布态必须设置具体 upstream commit SHA，Docker build 会直接 fetch/checkout 该 commit 并校验实际 checkout。 |
| `GO_VERSION` | `1.26.3` | 上游 libreFS 要求不同 Go 版本时再改。 |
| `ADMIN_ENABLED` | `false` | 只有明确需要开启 `/_admin/` 时设置为 `true`。 |
| `CONTROL_PLANE_DEFAULT_LANG` | `en` | 需要改变 `/_ops/` 和 `/_admin/` JSON 文案默认语言时设置；支持 `en`、`zh-CN`。 |

Docker Space 会把 Variables 传给 Docker build 作为 build args，也会在 runtime 注入为环境变量。

仅在确实需要覆盖默认值时再使用，例如临时 pin upstream commit：

```bash
hf spaces variables add BlueSkyXN/libreFS-HFS \
  -e LIBREFS_REF=master \
  -e LIBREFS_COMMIT='<upstream-commit-sha>'
```

检查当前 Variables 是否保持精简：

```bash
hf spaces variables list BlueSkyXN/libreFS-HFS
```

代码默认预期是：

```text
No results found.
```

当前生产环境最近回读为 2026-05-29 快照：

```text
ADMIN_ENABLED=true
PUBLIC_BASE_URL=https://blueskyxn-librefs-hfs.hf.space
MINIO_SERVER_URL=https://blueskyxn-librefs-hfs.hf.space
MINIO_BROWSER_REDIRECT_URL=https://blueskyxn-librefs-hfs.hf.space/console/
GO_VERSION=1.26.3
LIBREFS_REF=master
LIBREFS_COMMIT=e194bd779f36fdc08f310d2819d9356f0c1f991b
MINIO_SITE_NAME=librefs-hfs
MINIO_SITE_REGION=us-east-1
MINIO_BROWSER=on
MINIO_BROWSER_REDIRECT=on
MINIO_UPDATE=off
MINIO_CALLHOME_ENABLE=off
MINIO_API_ROOT_ACCESS=on
MINIO_API_CORS_ALLOW_ORIGIN=*
```

其中 `LIBREFS_COMMIT` 是有效的发布态 upstream commit pin；`GO_VERSION`、`LIBREFS_REF` 和若干 MinIO 变量与当前默认值重复，属于后续可清理的配置噪音。清理 Variables 会改变线上配置，应作为单独 live operation 执行。如果只做临时排障，排障结束后建议关闭或移除 `ADMIN_ENABLED`，让 `/_admin/` 回到代码默认关闭状态。

本地可以维护 `.env.local` 记录真实 secret 值、当前 host、Storage Bucket、默认值说明和临时覆盖候选。`.env.local` 必须被 Git ignore，不应提交。

## 存储挂载

当前项目建议挂载 Hugging Face Storage Bucket 到 `/data`。没有挂载时，服务可运行，但 `/data` 是临时目录。

如果需要持久化，把 Hugging Face Storage Bucket 挂载到：

```text
/data
```

查看当前 volume 配置：

```bash
hf spaces volumes list BlueSkyXN/libreFS-HFS
```

当前线上 Space 回读应类似：

```text
type    source                          mount_path  read_only
bucket  BlueSkyXN/libreFS-HFS-storage   /data       False
```

如果输出 `No results found`，说明对象数据不保证持久。

CLI 提示通常类似：

```bash
hf spaces volumes set BlueSkyXN/libreFS-HFS \
  -v hf://buckets/<namespace>/<bucket-name>:/data
```

需要替换成你账号里真实的 Storage Bucket URI。`buckets` 类型默认可读写，适合挂载到 libreFS 的 `/data`。

## 推送与重建

当前本地 checkout 的 Hugging Face remote 名称是 `hf`，GitHub remote 名称是 `origin`。推送到 Hugging Face Space remote 后，Space 会自动 rebuild：

```bash
git push hf main
```

确认远端 head：

```bash
git ls-remote hf HEAD refs/heads/main
```

查看 Space 状态：

```bash
curl -fsSL https://huggingface.co/api/spaces/BlueSkyXN/libreFS-HFS \
  | jq '{sha, stage: .runtime.stage, error: .runtime.errorMessage, host}'
```

如果匿名 Space API 返回 `401`，先用 health endpoint、`hf spaces logs` 和 HF Variables/Secrets/Volume CLI 回读确认状态；不要把匿名 API 失败当成 runtime 故障。

常见 stage：

| Stage | 含义 |
| --- | --- |
| `BUILDING` | Docker image 正在构建。 |
| `BUILD_ERROR` | Docker build 失败，需要看 build logs。 |
| `APP_STARTING` | image 已构建，容器正在启动。 |
| `RUNTIME_ERROR` | 容器启动后退出或 readiness 失败。 |
| `RUNNING` | 应用正在运行。 |

## 日志

查看 build logs：

```bash
hf spaces logs BlueSkyXN/libreFS-HFS --build --tail 200
```

查看 runtime logs：

```bash
hf spaces logs BlueSkyXN/libreFS-HFS --tail 200
```

成功启动时，runtime logs 应包含：

```text
nginx: configuration file /etc/nginx/nginx.conf test is successful
libreFS Object Storage Server
API: https://blueskyxn-librefs-hfs.hf.space
WebUI: https://blueskyxn-librefs-hfs.hf.space/console/
```

## 首次部署检查清单

1. 确认 Space 使用 Docker SDK。
2. 确认 `README.md` 里有 `app_port: 7860`。
3. 配置 `MINIO_ROOT_USER`。
4. 配置 `MINIO_ROOT_PASSWORD`。
5. 配置 `OPS_TOKEN`。
6. 如果需要生产环境开启 admin，配置 `ADMIN_TOKEN` 和 `ADMIN_ENABLED=true`。
7. 推送仓库文件。
8. 等待 Space stage 变为 `RUNNING`。
9. 检查 `/minio/health/ready`。
10. 用 `OPS_TOKEN` 检查 `/_ops/health`。
11. 如果已开启 admin，用 `ADMIN_TOKEN` 检查 `/_admin/api/status`；如果未开启，确认 `/_admin/` 返回 `404 admin_disabled`。
12. 打开 `/console/`。
13. 使用 root 凭证登录 Console。
14. 创建 bucket。
15. 上传一个小文件。
16. 用签名 S3 client 或 Console 下载对象。
17. 如果需要公开直链，配置 public read bucket policy，并测试匿名 URL。
