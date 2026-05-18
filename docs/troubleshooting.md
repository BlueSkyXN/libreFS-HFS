# 故障排查

本文档记录本项目真实遇到过或高概率遇到的 build、runtime、Console、S3 问题，以及对应处理方法。

## `useradd: UID 1000 is not unique`

### 现象

Build logs 出现：

```text
useradd: UID 1000 is not unique
```

### 原因

Ubuntu base image 或 Hugging Face build/runtime 环境里已经存在 UID `1000` 用户。

### 处理

不要直接写：

```dockerfile
useradd -m -u 1000 user
```

当前 Dockerfile 会先检查 UID/GID 是否存在，存在就复用，不存在才创建：

```dockerfile
if ! getent passwd "${APP_UID}" >/dev/null; then
    useradd -m -u "${APP_UID}" -g "${APP_GID}" user;
fi
```

## `fatal: couldn't find remote ref main`

### 现象

Build logs 出现：

```text
fatal: couldn't find remote ref main
```

### 原因

当前 libreFS 上游仓库 `https://github.com/libreFS/libreFS.git` 默认分支是 `master`，不是 `main`。

### 处理

使用：

```dockerfile
ARG LIBREFS_REF=master
```

如果怀疑上游分支变了，用下面命令确认：

```bash
git ls-remote --symref https://github.com/libreFS/libreFS.git HEAD
```

## 缺少 `MINIO_ROOT_USER`

### 现象

Runtime status 出现：

```text
/start.sh: line 4: MINIO_ROOT_USER: Set MINIO_ROOT_USER as a Hugging Face Space secret
```

### 原因

Space 没有配置必需 root credential Secrets。

### 处理

```bash
hf spaces secrets add BlueSkyXN/libreFS-HFS \
  -s MINIO_ROOT_USER=admin \
  -s MINIO_ROOT_PASSWORD='<strong-password>'
```

然后等待 Space 自动重启。

## Console 空白或 MIME type 错误

### 现象

浏览器 console 出现：

```text
Refused to execute script ... MIME type ('text/html') is not executable
Refused to apply style ... MIME type ('text/html') is not a supported stylesheet MIME type
```

### 原因

Nginx 把 `/console/static/...` 原样转发给上游 Console，导致上游按 HTML fallback 返回。

### 处理

`location /console/` 必须使用带末尾 `/` 的 `proxy_pass`：

```nginx
location /console/ {
    proxy_pass http://127.0.0.1:9001/;
}
```

验证：

```bash
curl -fsSI https://blueskyxn-librefs-hfs.hf.space/console/static/js/main.45669c2e.js
```

预期：

```text
content-type: text/javascript
```

## `/console/api/v1/session` 返回 `403`

### 现象

浏览器或 logs 中看到：

```text
GET /console/api/v1/session 403
```

### 判断

未登录时这是正常现象。Console 会探测 session endpoint，没有有效 session cookie 时返回 `403`。

登录后该 endpoint 应返回 `200`。

## 根路径 `/` 返回 `400 application/xml`

### 现象

```bash
curl -I https://blueskyxn-librefs-hfs.hf.space/
```

返回：

```text
HTTP/2 400
content-type: application/xml
```

### 判断

这是正常现象。浏览器或普通 `curl` 访问 S3 root 没有签名，会得到 S3 XML error。

需要用签名 S3 client 执行 `ListBuckets`，或者访问已经配置公开策略的对象 URL。

## 公开对象 URL 返回 `403 AccessDenied`

### 现象

```text
<Error><Code>AccessDenied</Code><Message>Access Denied.</Message>
```

### 原因

bucket 或 object 没有公开读权限。

### 处理

给目标 bucket 或 prefix 设置允许匿名 `s3:GetObject` 的 bucket policy。

示例：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": ["*"]
      },
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::public/*"]
    }
  ]
}
```

## `hf spaces volumes list` 显示 `No results found`

### 含义

Space 没有挂载 Hugging Face Storage Bucket。服务仍然可以运行，但 `/data` 不保证持久。

### 影响

对象可能在 Space 重启、重建、迁移或停止后丢失。

### 当前决策

当前用途接受这个限制。重要文件仍应保留在其他持久位置。

## `WARN: Detected GOMAXPROCS(2) < NumCPU(16)`

### 含义

libreFS 发现 Go runtime 的可用并发低于检测到的 CPU 数。

### 影响

这不是功能错误。在 `cpu-basic` 上轻量使用可以忽略。

### 后续处理

如果后续关注吞吐：

1. 升级 Space hardware。
2. 做上传/下载压测。
3. 再考虑调整 Go runtime 相关环境变量。

## Build 很慢

### 原因

libreFS 的 Go dependency graph 很大。首次构建需要下载 Go 和大量 Go modules。

### 判断

只要 build logs 仍在下载依赖或执行 `go build`，不一定是失败。

后续 build 通常会复用 cache，除非 Dockerfile、build args 或上游源码变化。

## Space `RUNNING` 但 S3 client 失败

优先检查：

1. endpoint 是否是 `https://blueskyxn-librefs-hfs.hf.space`。
2. client 是否使用 path-style addressing。
3. access key 是否等于 `MINIO_ROOT_USER`。
4. secret key 是否等于 `MINIO_ROOT_PASSWORD`。
5. region 是否使用 `us-east-1` 或 client 所需的占位 region。
6. health endpoint 是否返回 `200`。
7. runtime logs 里是否有对应 S3 error。

## Space `BUILD_ERROR`

查看 build logs：

```bash
hf spaces logs BlueSkyXN/libreFS-HFS --build --tail 200
```

Hugging Face API 的 `runtime.errorMessage` 有时只是 BuildKit 摘要，真正的失败点通常要看完整 build logs。

## Space `RUNTIME_ERROR`

查看 runtime logs：

```bash
hf spaces logs BlueSkyXN/libreFS-HFS --tail 200
```

本项目常见 runtime 原因：

- 缺少 `MINIO_ROOT_USER`
- 缺少 `MINIO_ROOT_PASSWORD`
- Nginx config 无法通过 `nginx -t`
- 内部端口配置不一致
- `/data` 或 `/tmp/nginx` 权限异常
