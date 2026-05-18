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

# LibreFS on Hugging Face Space

这个 Space 用于在 Hugging Face Docker Space 上运行 libreFS。部署策略是：

- 基础镜像从 `ubuntu:24.04` 开始。
- 构建阶段安装 Go 并从 `https://github.com/libreFS/libreFS.git` 拉源码编译。
- 运行阶段仍然是 `ubuntu:24.04`，不使用 libreFS 官方 Docker image。
- Nginx 监听 Hugging Face 对外暴露的 `7860`，再把内部 `9000` 和 `9001` 合并到单端口。

## 路由

| 外部路径 | 内部服务 | 用途 |
| --- | --- | --- |
| `/` | `127.0.0.1:9000` | S3 API 和 HTTP object path-style 直链 |
| `/console/` | `127.0.0.1:9001` | libreFS Web Console |

示例：

```text
Web Console:
https://<space-subdomain>.hf.space/console/

S3 endpoint:
https://<space-subdomain>.hf.space

Public object URL:
https://<space-subdomain>.hf.space/<bucket>/<object>
```

注意：`/console/` 被 Web Console 占用，所以不要把 `console` 当作需要公开直链访问的 bucket 名。

## Hugging Face 配置

在 Space Settings 里配置：

| 类型 | 名称 | 说明 |
| --- | --- | --- |
| Secret | `MINIO_ROOT_USER` | libreFS root user |
| Secret | `MINIO_ROOT_PASSWORD` | libreFS root password |
| Variable，可选 | `PUBLIC_BASE_URL` | 外部访问地址，例如 `https://<space-subdomain>.hf.space` |
| Variable，可选 | `LIBREFS_REF` | 构建的 libreFS branch 或 tag，默认 `main` |
| Variable，可选 | `LIBREFS_COMMIT` | 可选的源码 commit 校验值，默认 `HEAD` 不校验 |
| Variable，可选 | `GO_VERSION` | 构建用 Go 版本，默认 `1.26.3` |

Hugging Face 会在运行时提供 `SPACE_HOST`，所以通常不需要设置 `PUBLIC_BASE_URL`。如果挂了自定义域名，建议显式设置 `PUBLIC_BASE_URL`。

## 持久化

Hugging Face Space 默认磁盘是临时的。这个项目作为对象存储使用时，必须把 Hugging Face Storage Bucket 以读写方式挂载到：

```text
/data
```

`/data` 只在运行时可用，不能在 Dockerfile 构建阶段依赖它。未挂载 Storage Bucket 时服务仍可能启动，但上传对象会随 Space 重启、重建或停止而丢失；这种状态只适合一次性试跑，不应视为可用部署。

## 远程部署验证

推送到 Hugging Face Space 后，先在 Space 的 `Logs` 里确认：

- 镜像 build 阶段完成 libreFS 源码拉取和 `go build`。
- 运行阶段没有 `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` 缺失报错。
- libreFS API 显示为公开地址根路径。
- WebUI 显示为公开地址的 `/console/` 子路径。

然后访问：

```text
https://<space-subdomain>.hf.space/console/
```

S3 client endpoint 使用：

```text
https://<space-subdomain>.hf.space
```

## 已知边界

- Hugging Face Docker Space 外部只暴露一个 app port，因此这里必须用 Nginx 合并 S3 API 和 Web Console。
- Console 子路径代理是最需要实测的部分。当前配置通过 `MINIO_BROWSER_REDIRECT_URL=<base>/console/` 让 libreFS 设置 Console subpath。
- 这适合轻量测试、临时共享和非关键数据场景，不适合作为生产对象存储基础设施。
