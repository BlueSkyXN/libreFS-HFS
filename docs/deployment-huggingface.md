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

不要把真实凭证提交进仓库。Public Space 的源码文件是公开可见的。

使用 Hugging Face CLI 配置：

```bash
hf spaces secrets add BlueSkyXN/libreFS-HFS \
  -s MINIO_ROOT_USER=admin \
  -s MINIO_ROOT_PASSWORD='<strong-password>'
```

查看已配置的 Secret 名称：

```bash
hf spaces secrets list BlueSkyXN/libreFS-HFS
```

这个命令只显示 key，不显示 value。

## 可选 Variables

| Variable | 默认值 | 什么时候设置 |
| --- | --- | --- |
| `PUBLIC_BASE_URL` | `https://${SPACE_HOST}` | 使用自定义域名或需要覆盖公开 URL 时设置。 |
| `LIBREFS_REF` | `master` | 想固定上游 tag、branch 时设置。 |
| `LIBREFS_COMMIT` | `HEAD` | 想让 Docker build 校验精确 commit 时设置。 |
| `GO_VERSION` | `1.26.3` | 上游 libreFS 要求不同 Go 版本时再改。 |

示例：

```bash
hf spaces variables add BlueSkyXN/libreFS-HFS \
  -v LIBREFS_REF=master \
  -v LIBREFS_COMMIT=HEAD
```

## 存储挂载

当前项目可以不挂载 Hugging Face Storage Bucket。在这种模式下，服务可运行，但 `/data` 是临时目录。

如果需要持久化，把 Hugging Face Storage Bucket 挂载到：

```text
/data
```

查看当前 volume 配置：

```bash
hf spaces volumes list BlueSkyXN/libreFS-HFS
```

如果输出 `No results found`，说明当前对象数据不保证持久。

CLI 提示通常类似：

```bash
hf spaces volumes set BlueSkyXN/libreFS-HFS \
  -v hf://<repo_type>/<repo_id>:/data
```

需要替换成你账号里真实的 bucket URI。

## 推送与重建

推送到 Hugging Face Space remote 后，Space 会自动 rebuild：

```bash
git push origin main
```

确认远端 head：

```bash
git ls-remote origin HEAD refs/heads/main
```

查看 Space 状态：

```bash
curl -fsSL https://huggingface.co/api/spaces/BlueSkyXN/libreFS-HFS \
  | jq '{sha, stage: .runtime.stage, error: .runtime.errorMessage, host}'
```

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
5. 推送仓库文件。
6. 等待 Space stage 变为 `RUNNING`。
7. 检查 `/minio/health/ready`。
8. 打开 `/console/`。
9. 使用 root 凭证登录 Console。
10. 创建 bucket。
11. 上传一个小文件。
12. 用签名 S3 client 或 Console 下载对象。
13. 如果需要公开直链，配置 public read bucket policy，并测试匿名 URL。
