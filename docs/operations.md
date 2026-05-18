# 运维与验收

本文档记录线上服务的状态检查、健康检查、Console 验收、S3 smoke test、日志查看和运行风险。

## 当前线上服务

```text
Endpoint:
https://blueskyxn-librefs-hfs.hf.space

Console:
https://blueskyxn-librefs-hfs.hf.space/console/
```

## 检查 Space 状态

```bash
curl -fsSL https://huggingface.co/api/spaces/BlueSkyXN/libreFS-HFS \
  | jq '{sha, stage: .runtime.stage, error: .runtime.errorMessage, host}'
```

健康状态应类似：

```json
{
  "stage": "RUNNING",
  "error": null,
  "host": "https://blueskyxn-librefs-hfs.hf.space"
}
```

## 健康检查

```bash
curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready \
  -o /dev/null \
  -w 'health_http=%{http_code}\n'
```

预期：

```text
health_http=200
```

## Console 静态资源检查

这个检查用于发现最常见的反代问题：`/console/` HTML 能打开，但 JS/CSS 被返回成 `text/html`，导致页面空白。

检查 JS：

```bash
curl -fsSI https://blueskyxn-librefs-hfs.hf.space/console/static/js/main.45669c2e.js
```

预期 header：

```text
content-type: text/javascript
```

检查 CSS：

```bash
curl -fsSI https://blueskyxn-librefs-hfs.hf.space/console/static/css/main.e60e4760.css
```

预期 header：

```text
content-type: text/css
```

注意：上游 libreFS 更新后，asset 文件名可能变化。如果精确文件名不存在，先打开 `/console/`，从 HTML 中取当前 `static/js` 和 `static/css` 路径再测。

## Console 登录检查

打开：

```text
https://blueskyxn-librefs-hfs.hf.space/console/
```

预期：

1. 浏览器进入 `/console/login`。
2. 登录页正常渲染。
3. 使用 root 凭证可登录。
4. 登录后进入 `/console/browser`。
5. 能看到 Object Browser、Buckets 等管理界面。

未登录时 `/console/api/v1/session` 返回 `403` 是正常现象。登录后应返回 `200`。

## S3 API Smoke Test

最小 S3 验收应覆盖：

1. 签名 `ListBuckets`。
2. 创建临时 bucket。
3. 上传对象。
4. 签名下载对象。
5. 配置公开策略前，匿名读取返回 `403`。
6. 配置 public read bucket policy。
7. 匿名 HTTP 直链读取返回 `200`。
8. 清理 policy、object、bucket。

最近一次远端 smoke test 已确认以上链路全部通过。

## 日志

查看 build logs：

```bash
hf spaces logs BlueSkyXN/libreFS-HFS --build --tail 200
```

查看 runtime logs：

```bash
hf spaces logs BlueSkyXN/libreFS-HFS --tail 200
```

成功启动时 runtime logs 应包含：

```text
nginx: configuration file /etc/nginx/nginx.conf test is successful
libreFS Object Storage Server
API: https://blueskyxn-librefs-hfs.hf.space
WebUI: https://blueskyxn-librefs-hfs.hf.space/console/
```

## 重启

使用 CLI 重启：

```bash
hf spaces restart BlueSkyXN/libreFS-HFS
```

修改 Secrets 或 Variables 也可能触发 rebuild 或 restart。

## 持久化检查

当前已知状态：

```text
storage: null
volumes: No results found
```

重新检查：

```bash
hf spaces volumes list BlueSkyXN/libreFS-HFS
```

如果没有 volume，数据不持久。当前用途可以接受这个限制，但不要把对象当成长期唯一副本。

如果后续挂载 Storage Bucket 到 `/data`，需要做持久化验收：

1. 上传对象。
2. 重启 Space。
3. 再次读取对象。
4. rebuild Space。
5. 再次读取对象。

这些检查都通过后，才能认为 `/data` 持久化满足预期。

## 运行风险矩阵

| 风险 | 影响 | 当前状态 | 处理方式 |
| --- | --- | --- | --- |
| 未挂载持久化 storage | 对象可能丢失 | 当前接受 | 重要文件保留其他副本；需要持久化时挂载 `/data`。 |
| HF Space sleep/restart | 可能短时不可用 | 预期行为 | 作为轻量服务使用。 |
| libreFS 上游 `master` 变化 | rebuild 行为可能变化 | 部分受控 | 需要稳定时设置 `LIBREFS_COMMIT`。 |
| Console 子路径回归 | Console 页面空白 | 当前已修复 | 检查 JS/CSS MIME 和登录页。 |
| bucket policy 配错 | 私有对象被公开 | 用户侧风险 | 使用最小 policy，设置后复查。 |
| `cpu-basic` 资源限制 | 上传/下载慢，吞吐低 | 预期行为 | 重负载时升级硬件并压测。 |

## 每次推送后的建议检查

```bash
git ls-remote origin HEAD refs/heads/main

curl -fsSL https://huggingface.co/api/spaces/BlueSkyXN/libreFS-HFS \
  | jq '{sha, stage: .runtime.stage, error: .runtime.errorMessage}'

curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready \
  -o /dev/null \
  -w 'health_http=%{http_code}\n'
```

然后打开：

```text
https://blueskyxn-librefs-hfs.hf.space/console/
```
