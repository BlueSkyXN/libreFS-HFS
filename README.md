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
| Web Console | 可用 | `/console/` 转发到 libreFS Web Console，已验证可登录。 |
| 签名上传/下载 | 可用 | 已验证 AWS SigV4 path-style 基本读写。 |
| HTTP 直链 | 可用 | bucket policy 允许匿名 `s3:GetObject` 后可直链访问。 |
| 持久化 | 可选 | 当前不挂 HF Storage Bucket 也能运行，但数据不保证持久。 |
| 生产对象存储 | 不建议 | HF Space 是应用托管环境，不是专用对象存储基础设施。 |

## 公开路由

Hugging Face Docker Space 只对外暴露一个 app port。本项目用 Nginx 在 `7860` 上统一接入，再分流到 libreFS 的两个内部端口。

| 公开路径 | 内部服务 | 用途 |
| --- | --- | --- |
| `/` | `127.0.0.1:9000` | S3 API 和 path-style 对象 URL。 |
| `/console/` | `127.0.0.1:9001` | libreFS / MinIO-compatible Web Console。 |

不要创建名为 `console` 的公开 bucket。`/console/` 是 Web Console 保留路径。

## 必需的 Hugging Face Secrets

在 Space Settings 里配置：

| 类型 | 名称 | 必需 | 说明 |
| --- | --- | --- | --- |
| Secret | `MINIO_ROOT_USER` | 是 | libreFS root user，同时用于 Console 登录和 S3 root access key。 |
| Secret | `MINIO_ROOT_PASSWORD` | 是 | libreFS root password，同时用于 Console 登录和 S3 root secret key。 |

## 可选的 Hugging Face Variables

| 类型 | 名称 | 默认值 | 说明 |
| --- | --- | --- | --- |
| Variable | `PUBLIC_BASE_URL` | 从 `SPACE_HOST` 推导 | 公开访问根地址；使用自定义域名时建议显式设置。 |
| Variable | `LIBREFS_REF` | `master` | Docker build 阶段拉取的 libreFS branch 或 tag。 |
| Variable | `LIBREFS_COMMIT` | `HEAD` | 可选 commit pin；设置后 build 会校验实际 checkout 的 commit。 |
| Variable | `GO_VERSION` | `1.26.3` | Docker build 阶段下载的 Go 版本。 |

## 文档入口

详细文档拆分在 `docs/` 目录：

- [文档索引](docs/README.md)
- [架构说明](docs/architecture.md)
- [Hugging Face 部署指南](docs/deployment-huggingface.md)
- [配置参考](docs/configuration.md)
- [源码逐文件说明](docs/source-walkthrough.md)
- [使用指南](docs/usage.md)
- [运维与验收](docs/operations.md)
- [故障排查](docs/troubleshooting.md)

## 快速健康检查

```bash
curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready
```

预期结果：

```text
HTTP 200，响应体为空
```

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

- 如果没有把 Hugging Face Storage Bucket 挂载到 `/data`，上传对象可能在 Space 重启、重建、迁移或停止后丢失。
- 当前 `cpu-basic` 硬件适合功能测试和轻量使用，不适合高吞吐对象存储。
- 未签名浏览器直接访问根路径 `/` 可能返回 S3 XML error，这是正常现象；签名 S3 请求和配置了 policy 的对象直链才是预期访问方式。
- 本仓库 license 使用 AGPL-3.0，因为 libreFS 本身是 AGPL-3.0。
