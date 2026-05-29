# 运维与验收

本文档记录线上服务的状态检查、健康检查、Console 验收、S3 smoke test、日志查看和运行风险。

## 当前线上服务

```text
Endpoint:
https://blueskyxn-librefs-hfs.hf.space

Console:
https://blueskyxn-librefs-hfs.hf.space/console/
```

最近生产回读时间：2026-05-29。实时状态以本页命令重新查询为准；`origin/main`、`hf/main` 和 Space runtime sha 都可能在合并或推送后立即过期。

## 检查 Space 状态

```bash
curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready \
  -o /dev/null \
  -w 'health_http=%{http_code}\n'
```

健康状态应类似：

```text
health_http=200
```

Hugging Face Space API 如果返回 `401`，说明当前访问方式需要认证；不要把匿名 API 失败直接解释成 Space 不可用。可改用已登录的 HF CLI 查看日志和 Variables/Secrets/Volume。

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

## 本地契约检查

不本地 build libreFS 时，先运行仓库自带的轻量检查：

```bash
scripts/validate-contract.sh
```

这会检查：

- Markdown 和配置 diff 是否存在 whitespace 或 conflict marker。
- `hfs/start.sh` Bash 语法。
- `hfs/ops_service.py` 和 `hfs/admin_service.py` Python 语法。
- `README.md` front matter 是否仍是 Docker Space、`app_port: 7860` 和 AGPL-3.0。
- `Dockerfile` 是否保持 Ubuntu builder/runtime、远端源码构建和 `7860` healthcheck。
- `hfs/nginx.conf` 是否保持 `/_ops/`、`/_admin/`、`/console/`、S3 根路径、iframe header 和单端口契约。
- 本机如果安装了 `nginx`，会运行 `nginx -t -c "$PWD/hfs/nginx.conf"`。

需要顺手检查公开 health endpoint 时：

```bash
scripts/validate-contract.sh --remote
```

## Ops 诊断入口

`/_ops/` 是只读诊断面，默认需要 `OPS_TOKEN`。公开长期运行建议在 HF Secrets 中覆盖默认 demo token。

浏览器聚合面板：

```text
https://blueskyxn-librefs-hfs.hf.space/_ops/
```

首次网页登录可以临时打开：

```text
https://blueskyxn-librefs-hfs.hf.space/_ops/?token=<ops-token>
```

token 验证成功后，服务会设置 `Secure; HttpOnly; SameSite=Lax; Path=/_ops` cookie，并跳转回不带 token 的 `/_ops/`。后续浏览器打开 `/_ops/health`、`/_ops/system`、`/_ops/config`、`/_ops/version` 或 `/_ops/metrics` 会复用 cookie 登录态。脚本/API 请求不接受 query token 鉴权，必须使用 header、bearer token 或浏览器 cookie。退出登录使用：

```text
https://blueskyxn-librefs-hfs.hf.space/_ops/logout
```

不要长期使用、记录或分享带 `?token=` 的 URL；token 可能进入浏览器历史、外部代理日志、截图或聊天记录。容器内 Nginx access log 不记录 query string，ops-service 日志会 redact `token=` 值，并且 ops 响应带 `Referrer-Policy: no-referrer`；脚本和自动化继续使用 header。

常用检查：

```bash
OPS_TOKEN='<ops-token>'

curl -fsS -H "X-Ops-Token: $OPS_TOKEN" \
  https://blueskyxn-librefs-hfs.hf.space/_ops/health

curl -fsS -H "X-Ops-Token: $OPS_TOKEN" \
  https://blueskyxn-librefs-hfs.hf.space/_ops/system

curl -fsS -H "X-Ops-Token: $OPS_TOKEN" \
  https://blueskyxn-librefs-hfs.hf.space/_ops/config
```

外部 API 必须带 `/_ops/` 前缀；裸 `/health`、`/system`、`/config`、`/version`、`/metrics` 不是公开 URL，只是内部 handler path。

`/_ops/config` 只返回非敏感配置摘要和 Secret 是否存在，不返回 Secret 原文。`/_ops/metrics` 返回 Prometheus text format，但仍需要 token。

ops/admin JSON 文案支持中文和英文。脚本或管理页面可以显式传：

```bash
curl -fsS -H "X-Ops-Token: $OPS_TOKEN" \
  -H "X-Control-Language: zh-CN" \
  "https://blueskyxn-librefs-hfs.hf.space/_ops/config"

curl -fsS -H "X-Admin-Token: $ADMIN_TOKEN" \
  "https://blueskyxn-librefs-hfs.hf.space/_admin/api/actions?lang=zh-CN"
```

未显式传语言时，服务会按 `Accept-Language` 选择；没有浏览器语言时默认英文。机器可读的 `error` 和 action `name` 保持英文稳定，管理界面应展示 `message`、`label`、`description` 和 `risk`。

## Admin 管理入口

`/_admin/` 的代码默认值是关闭：

```text
ADMIN_ENABLED=false
```

默认关闭时：

```bash
curl -i https://blueskyxn-librefs-hfs.hf.space/_admin/
```

预期返回 `404`。

只有明确需要受控管理能力时，才在 HF Secrets/Variables 中设置：

```text
ADMIN_ENABLED=true
ADMIN_TOKEN=<strong-random-token>
```

当前生产环境已经设置 `ADMIN_ENABLED=true` 并配置 `ADMIN_TOKEN`。因此线上无 token 访问应返回 `401 unauthorized`，带有效 `ADMIN_TOKEN` 访问 `/_admin/api/status` 应返回 `enabled: true`。

当前白名单 action：

```bash
curl -fsS -H "X-Admin-Token: $ADMIN_TOKEN" \
  https://blueskyxn-librefs-hfs.hf.space/_admin/api/status

curl -fsS -H "X-Admin-Token: $ADMIN_TOKEN" \
  https://blueskyxn-librefs-hfs.hf.space/_admin/api/actions

curl -fsS -X POST -H "X-Admin-Token: $ADMIN_TOKEN" \
  https://blueskyxn-librefs-hfs.hf.space/_admin/api/actions/run-health-checks

curl -fsS -X POST -H "X-Admin-Token: $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"confirm": true}' \
  https://blueskyxn-librefs-hfs.hf.space/_admin/api/actions/reload-nginx
```

当前版本不提供 Web terminal、file manager、任意 shell command、bucket/policy/root credential 管理或 `librefs` restart。admin action 会写入 `/data/logs/admin-audit.jsonl`。

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

## Console iframe header 检查

Hugging Face Space 项目页会把 app 放进 `huggingface.co` 页面里的 iframe。Console upstream 如果返回 `X-Frame-Options: DENY`，浏览器会拒绝展示，表现为 Space 页面里 Console 加载失败。

检查：

```bash
curl -fsSI https://blueskyxn-librefs-hfs.hf.space/console/ \
  | tr -d '\r' \
  | grep -Ei '^(x-frame-options|content-security-policy):'
```

预期：

- 不应出现 `x-frame-options`。
- 应出现包含 `frame-ancestors` 的 `content-security-policy`。
- `frame-ancestors` 应允许 `https://huggingface.co`。

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

这组检查需要 root 凭证和临时测试对象。公开 health check、Console 静态资源或 Space `RUNNING` 只能证明服务入口正常，不能替代签名 S3 smoke test。

仓库提供一个不依赖 `aws`、`mc` 或其他第三方 CLI 的 curl 版本：

```bash
MINIO_ROOT_USER='<access-key>' \
MINIO_ROOT_PASSWORD='<secret-key>' \
scripts/smoke-s3-curl.sh
```

脚本会使用 `curl --aws-sigv4` 执行：

1. 签名 `ListBuckets`。
2. 确认临时 bucket 不存在，避免误操作已有 bucket。
3. 创建临时 bucket。
4. 上传临时对象。
5. 签名下载并比对对象内容。
6. 验证配置公开策略前匿名读取返回 `403`。
7. 写入 public read bucket policy。
8. 验证匿名 HTTP 直链返回对象内容。
9. 清理 policy、object 和 bucket。

可选覆盖项：

```bash
S3_ENDPOINT='https://blueskyxn-librefs-hfs.hf.space'
AWS_REGION='us-east-1'
S3_SMOKE_BUCKET='librefs-hfs-smoke-manual'
S3_SMOKE_OBJECT='smoke.txt'
S3_SMOKE_PAYLOAD='hello from smoke test'
```

这个脚本会修改线上对象存储状态，只应在确认 root 凭证和临时 bucket 名称后运行。脚本会拒绝 HEAD 已存在的 bucket，但仍建议使用自动生成的临时 bucket 名。它不验证 `/data` 在 restart 或 rebuild 后的持久化读回。

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
librefs-hfs ops service listening on 127.0.0.1:8081
librefs-hfs admin service listening on 127.0.0.1:8082
```

## 重启

使用 CLI 重启：

```bash
hf spaces restart BlueSkyXN/libreFS-HFS
```

修改 Secrets 或 Variables 也可能触发 rebuild 或 restart。

## 环境配置维护

代码默认部署的建议配置模型是：

```text
HF Secrets:
- MINIO_ROOT_USER
- MINIO_ROOT_PASSWORD
- OPS_TOKEN

HF Variables:
- empty

HF Volume:
- BlueSkyXN/libreFS-HFS-storage -> /data
```

当前生产环境最近回读为：

```text
HF Secrets:
- MINIO_ROOT_USER
- MINIO_ROOT_PASSWORD
- OPS_TOKEN
- ADMIN_TOKEN

HF Variables:
- ADMIN_ENABLED=true
- PUBLIC_BASE_URL=https://blueskyxn-librefs-hfs.hf.space
- MINIO_SERVER_URL=https://blueskyxn-librefs-hfs.hf.space
- MINIO_BROWSER_REDIRECT_URL=https://blueskyxn-librefs-hfs.hf.space/console/
- GO_VERSION=1.26.3
- LIBREFS_REF=master
- LIBREFS_COMMIT=e194bd779f36fdc08f310d2819d9356f0c1f991b
- MINIO_SITE_NAME=librefs-hfs
- MINIO_SITE_REGION=us-east-1
- MINIO_BROWSER=on
- MINIO_BROWSER_REDIRECT=on
- MINIO_UPDATE=off
- MINIO_CALLHOME_ENABLE=off
- MINIO_API_ROOT_ACCESS=on
- MINIO_API_CORS_ALLOW_ORIGIN=*

HF Volume:
- BlueSkyXN/libreFS-HFS-storage -> /data
```

`LIBREFS_COMMIT` 是有效的 release pin；`GO_VERSION`、`LIBREFS_REF` 和若干 MinIO 变量与当前默认值重复，属于后续可清理的配置噪音。清理 Variables 会改变线上配置，应作为单独 live operation 执行。

维护原则：

1. 和代码默认值一致的内容不要配置成 HF Variables。
2. upstream libreFS 默认值不要在 HF Variables 里重复声明。
3. Secret 真实值只保存在 HF Secrets 和本地 `.env.local`，不要提交进仓库。
4. `.env.local` 是本地台账，不是 runtime 自动加载文件；它用于记录默认值、覆盖候选和不能从 HF 回读的 secret value。
5. 只有自定义域名、临时排障、临时切 upstream ref 或明确 commit pin 时，才新增 HF Variables。

检查云端是否保持精简：

```bash
hf spaces variables list BlueSkyXN/libreFS-HFS
hf spaces secrets list BlueSkyXN/libreFS-HFS
hf spaces volumes list BlueSkyXN/libreFS-HFS
```

代码默认只启用 ops 时的预期：

```text
variables: No results found.
secrets: MINIO_ROOT_USER, MINIO_ROOT_PASSWORD, OPS_TOKEN
volume: BlueSkyXN/libreFS-HFS-storage -> /data
```

当前生产启用了 admin，并且当前回读到一个具体 `LIBREFS_COMMIT` 发布 pin，因此 `variables` 不应为空，`secrets` 也应包含 `ADMIN_TOKEN`。HF CLI 不回显 Secret value，只能回读 key；需要确认 value 是否同步时，用本地 `.env.local` 的 token 调线上 `/_ops/` 或 `/_admin/` 验证。

## 持久化检查

当前已知状态（以 `hf spaces volumes list` 回读为准）：

```text
type: bucket
source: BlueSkyXN/libreFS-HFS-storage
mount_path: /data
read_only: False
```

重新检查：

```bash
hf spaces volumes list BlueSkyXN/libreFS-HFS
```

如果没有 volume，数据不持久。当前线上 Space 应保持 `BlueSkyXN/libreFS-HFS-storage` 挂载到 `/data`。

挂载 Storage Bucket 到 `/data` 后，需要做持久化验收：

1. 上传对象。
2. 重启 Space。
3. 再次读取对象。
4. rebuild Space。
5. 再次读取对象。

这些检查都通过后，才能认为 `/data` 持久化满足预期。

## 运行风险矩阵

| 风险 | 影响 | 当前状态 | 处理方式 |
| --- | --- | --- | --- |
| 未挂载持久化 storage | 对象可能丢失 | 当前 `hf spaces volumes list` 显示已挂载 `/data` bucket | 如发现 volume 缺失，先停止写入并恢复挂载。 |
| HF Space sleep/restart | 可能短时不可用 | 预期行为 | 作为轻量服务使用。 |
| libreFS 上游 `master` 变化 | 未 pin 的 rebuild 行为可能变化 | 部分受控 | 发布态必须设置具体 `LIBREFS_COMMIT=<upstream commit sha>`；设置后 Docker build 会直接 fetch/checkout 该 commit，`master + HEAD` 只算开发默认。 |
| Console 子路径回归 | Console 页面空白 | 当前已修复 | 检查 JS/CSS MIME 和登录页。 |
| bucket policy 配错 | 私有对象被公开 | 用户侧风险 | 使用最小 policy，设置后复查。 |
| `cpu-basic` 资源限制 | 上传/下载慢，吞吐低 | 预期行为 | 重负载时升级硬件并压测。 |

## 每次推送后的建议检查

```bash
git ls-remote hf HEAD refs/heads/main

curl -fsSL https://huggingface.co/api/spaces/BlueSkyXN/libreFS-HFS \
  | jq '{sha, stage: .runtime.stage, error: .runtime.errorMessage}'

curl -fsS https://blueskyxn-librefs-hfs.hf.space/minio/health/ready \
  -o /dev/null \
  -w 'health_http=%{http_code}\n'
```

如果 Space API 对当前网络返回 `401`，先用 health endpoint、`hf spaces logs` 和 HF Variables/Secrets/Volume CLI 回读确认状态；不要把匿名 API 失败当成 runtime 故障。

然后打开：

```text
https://blueskyxn-librefs-hfs.hf.space/console/
```
