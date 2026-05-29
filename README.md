---
title: LibreFS HFS
emoji: 🗄️
colorFrom: gray
colorTo: blue
sdk: docker
app_port: 7860
pinned: false
license: agpl-3.0
---

# LibreFS HFS

LibreFS HFS 是一个面向 Hugging Face Docker Space 的 libreFS 部署包装项目，用于在 HF Space 上运行一个轻量级、S3-compatible 的对象存储服务。

本项目的部署策略是：

- 从 `ubuntu:24.04` 原始镜像开始。
- Docker build 阶段安装 Go，并从 `https://github.com/libreFS/libreFS.git` 拉取源码编译。
- Runtime 阶段仍然使用 `ubuntu:24.04`。
- 不使用 libreFS 官方 Docker image。
- 仓库根目录同时作为 Hugging Face Space root 和 GitHub 维护 root；`hfs-dev.toml` 声明 Pattern A / `source-fetch`，多服务 runtime glue 集中在 `hfs/`。
- 使用 Nginx 把 libreFS 的 S3 API 和 Web Console 合并到 Hugging Face Space 对外暴露的单端口 `7860`。

## 当前线上地址

```text
Space 仓库:
https://huggingface.co/spaces/BlueSkyXN/libreFS-HFS

公开 endpoint:
https://blueskyxn-librefs-hfs.hf.space

Web Console:
https://blueskyxn-librefs-hfs.hf.space/console/
```

## 当前能力状态

| 能力 | 状态 | 说明 |
| --- | --- | --- |
| S3-compatible API | 可用 | 公开域名根路径 `/` 转发到 libreFS S3 API。 |
| Web Console | 可用 | `/console/` 转发到 libreFS Web Console；公开页面、静态资源和 iframe header 已回读正常，登录需 root 凭证复测。 |
| 只读 Ops | 可用 / 需 token | `/_ops/` 提供浏览器诊断面板，并提供 `/_ops/health`、`/_ops/system`、`/_ops/config`、`/_ops/version`、`/_ops/metrics` API；默认使用 `OPS_TOKEN` 保护，只返回非敏感摘要。 |
| Admin 管理面 | 代码默认关闭 / 当前线上已开启 | 代码默认 `ADMIN_ENABLED=false`；当前 HF Variable 为 `ADMIN_ENABLED=true`，访问 `/_admin/` 需要 `ADMIN_TOKEN`，只提供白名单 action。 |
| 签名上传/下载 | 需凭证验收 | 设计上走 AWS SigV4 path-style；仓库提供 `scripts/smoke-s3-curl.sh`，涉及 Secret 的 smoke test 需在操作时重新执行。 |
| HTTP 直链 | 条件可用 | bucket policy 允许匿名 `s3:GetObject` 后可直链访问。 |
| 持久化 | 已挂载 / 需验收 | 当前 `hf spaces volumes list` 显示 Storage Bucket 挂载到 `/data`；仍需上传、重启、rebuild 后读取验证。 |
| 生产对象存储 | 不建议 | HF Space 是应用托管环境，不是专用对象存储基础设施。 |

## 公开路由

Hugging Face Docker Space 只对外暴露一个 app port。本项目用 Nginx 在 `7860` 上统一接入，再分流到 libreFS 的两个内部端口。

| 公开路径 | 内部服务 | 用途 |
| --- | --- | --- |
| `/` | `127.0.0.1:9000` | S3 API 和 path-style 对象 URL。 |
| `/_ops/` | `127.0.0.1:8081` | 只读诊断面板和 API；需要 `OPS_TOKEN`。 |
| `/_admin/` | `127.0.0.1:8082` | 默认关闭的管理面；开启后需要独立 `ADMIN_TOKEN`。 |
| `/console/` | `127.0.0.1:9001` | libreFS / MinIO-compatible Web Console。 |

不要创建名为 `console`、`minio`、`_ops`、`_admin` 的公开 bucket。这些路径被 Web Console、health、ops 和 admin 路由保留。

## 必需的 Hugging Face Secrets

在 Space Settings 里配置：

| 类型 | 名称 | 必需 | 说明 |
| --- | --- | --- | --- |
| Secret | `MINIO_ROOT_USER` | 是 | libreFS root user，同时用于 Console 登录和 S3 root access key。 |
| Secret | `MINIO_ROOT_PASSWORD` | 是 | libreFS root password，同时用于 Console 登录和 S3 root secret key。 |
| Secret | `OPS_TOKEN` | 建议 | `/_ops/` 只读诊断入口 token；不设置时使用 demo 默认值，公开长期运行建议覆盖。 |
| Secret | `ADMIN_TOKEN` | 仅开启 admin 时 | `/_admin/` 独立 Secret/header；只有 `ADMIN_ENABLED=true` 时需要。 |

## 可选的 Hugging Face Variables

| 类型 | 名称 | 默认值 | 说明 |
| --- | --- | --- | --- |
| Variable | `PUBLIC_BASE_URL` | 从 `SPACE_HOST` 推导 | 公开访问根地址；使用自定义域名时建议显式设置。 |
| Variable | `LIBREFS_REF` | `master` | Docker build 阶段拉取的 libreFS branch 或 tag。 |
| Variable | `LIBREFS_COMMIT` | `HEAD` | 开发默认不 pin；发布态必须设置具体 upstream commit SHA，build 会校验实际 checkout。 |
| Variable | `GO_VERSION` | `1.26.3` | Docker build 阶段下载的 Go 版本。 |
| Variable | `ADMIN_ENABLED` | `false` | 是否开启 `/_admin/`；默认保持关闭。 |
| Variable | `CONTROL_PLANE_DEFAULT_LANG` | `en` | `/_ops/` 和 `/_admin/` JSON 文案默认语言；支持 `en`、`zh-CN`。 |

## 当前生产配置快照

最近回读时间：2026-05-20。实时状态以命令重新查询为准。

| 项目 | 当前值 / 状态 |
| --- | --- |
| GitHub `origin/main` | 用 `git ls-remote --heads origin main` 回读。 |
| Hugging Face `hf/main` | 用 `git ls-remote --heads hf main` 回读。 |
| Space stage | `RUNNING` |
| HF Variables | `ADMIN_ENABLED=true` |
| HF Secrets | `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD`、`OPS_TOKEN`、`ADMIN_TOKEN` 已配置；HF 不回显 value。 |
| HF Volume | `BlueSkyXN/libreFS-HFS-storage -> /data`，`read_only=False` |

## 文档入口

详细文档拆分在 `docs/` 目录：

- [文档索引](docs/README.md)
- [架构说明](docs/architecture.md)
- [Hugging Face 部署指南](docs/deployment-huggingface.md)
- [配置参考](docs/configuration.md)
- [环境变量参考](docs/env-reference.md)
- [源码逐文件说明](docs/source-walkthrough.md)
- [使用指南](docs/usage.md)
- [运维与验收](docs/operations.md)
- [故障排查](docs/troubleshooting.md)
- [开发状态与下一步计划](docs/development-plan.md)

## 快速健康检查

```bash
curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready
```

预期结果：

```text
HTTP 200，响应体为空
```

## 快速 Ops 检查

浏览器打开只读诊断面板：

```text
https://blueskyxn-librefs-hfs.hf.space/_ops/
```

首次网页登录可临时使用：

```text
https://blueskyxn-librefs-hfs.hf.space/_ops/?token=<ops-token>
```

token 验证成功后，服务会设置 `HttpOnly` cookie 并跳转到不带 token 的 `/_ops/`；后续浏览器访问 `/_ops/health`、`/_ops/system` 等不需要继续把 token 放在 URL 里。不要把带 `?token=` 的链接写入文档、截图或分享链接。

```bash
OPS_TOKEN='<ops-token>' \
curl -fsS -H "X-Ops-Token: $OPS_TOKEN" \
  https://blueskyxn-librefs-hfs.hf.space/_ops/health
```

外部 ops API 路径必须带 `/_ops/` 前缀：

```text
/_ops/health
/_ops/system
/_ops/config
/_ops/version
/_ops/metrics
```

`/_ops/config` 只返回非敏感配置和 Secret 是否存在，不返回 `MINIO_ROOT_PASSWORD`、`OPS_TOKEN` 或 `ADMIN_TOKEN` 原文。

`/_ops/` 和 `/_admin/` 支持中文/英文文案。脚本可用 `?lang=zh-CN` 或 `X-Control-Language: zh-CN` 指定语言，浏览器会按 `Accept-Language` 自动选择；未指定时默认英文。

## 快速访问

打开 Web Console：

```text
https://blueskyxn-librefs-hfs.hf.space/console/
```

S3-compatible client 的 endpoint：

```text
https://blueskyxn-librefs-hfs.hf.space
```

公开对象直链格式：

```text
https://blueskyxn-librefs-hfs.hf.space/<bucket>/<object>
```

公开直链需要 bucket policy 显式允许匿名 `s3:GetObject`。

## 已知边界

- 当前 `hf spaces volumes list` 显示 `/data` 已挂载 Hugging Face Storage Bucket；如果后续移除挂载，上传对象可能在 Space 重启、重建、迁移或停止后丢失。
- 当前生产环境已显式开启 `/_admin/`。如果需要恢复默认安全姿态，应把 HF Variable `ADMIN_ENABLED` 改回 `false` 或移除。
- 当前 `cpu-basic` 硬件适合功能测试和轻量使用，不适合高吞吐对象存储。
- 未签名浏览器直接访问根路径 `/` 可能返回 S3 XML error，这是正常现象；签名 S3 请求和配置了 policy 的对象直链才是预期访问方式。
- 本仓库 license 使用 AGPL-3.0，因为 libreFS 本身是 AGPL-3.0。
