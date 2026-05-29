# 环境变量台账参考

本文档是可提交的公开版 ENV 台账。它说明每个变量属于哪个平台、应该放在 `V` 还是 `S`、是否推荐配置、默认值和建议值。真实地址、账号、密码、token、access key、secret key 只允许写在本地 `.env.local`、Hugging Face Secrets、GitHub Secrets 或临时 shell 环境中，不能写进本文档。

`.env.local` 的定位是本机笔记本：它可以记录已知真实值，帮助后续覆盖云端配置；本文档只记录公开说明和占位符。

## 标记说明

| 标记 | 含义 |
| --- | --- |
| `HF` | Hugging Face Space。 |
| `GH` | GitHub repo。 |
| `V` | Variables，适合非敏感开关、版本号、URL 覆盖、构建参数或运行参数。 |
| `S` | Secrets，适合密码、token、access key、secret key、KMS key。 |
| `Volume` | Hugging Face Storage Volume，不属于 `V` 或 `S`。 |
| `本地` | 只留在 `.env.local` 或本机 shell，不同步到云端平台。 |
| `平台注入` | 由平台运行时自动注入，不手动配置。 |
| `不配置` | 不建议写入任何平台，除非以后明确改变部署契约。 |

原则：

- Secret 只能写 key 名称、用途和占位符，不能写真实 value。
- API 根地址、root 账号、root 密码、ops token、admin token 这类本地已知值只写入 `.env.local`，不要写入 docs。
- Hugging Face Secrets 和 GitHub Secrets 只能确认 key 是否存在，不能回读明文 value。
- 不要把和代码默认值相同的内容同步成云端 Variables；Variables 应只表达“明确覆盖默认行为”。
- GitHub repo 未发现必须配置的 Variables 或 Secrets；如果以后增加 GitHub Actions，再按 `GH + V/S` 记录。

## 第 1 层：必需配置

| 变量 | 平台 | 位置 | 推荐 | 默认值 | 建议值 / 可能值 | 用途 | 注意 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `MINIO_ROOT_USER` | `HF` | `S` | 必须 | 无默认，启动时必须有值。 | 强随机 root access key 或已知运维账号。 | libreFS 根用户、Web Console 用户名、S3 root access key。 | 缺少时 `hfs/start.sh` 直接失败；不要放到 `V`。 |
| `MINIO_ROOT_PASSWORD` | `HF` | `S` | 必须 | 无默认，启动时必须有值。 | 强随机 root secret key。 | libreFS 根密码、Web Console 密码、S3 root secret key。 | 缺少时 `hfs/start.sh` 直接失败；不要放到 `V`。 |

## 第 2 层：推荐配置

| 变量 | 平台 | 位置 | 推荐 | 默认值 | 建议值 / 可能值 | 用途 | 注意 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `OPS_TOKEN` | `HF` | `S` | 推荐 | `librefs_ops_demo_token`。 | 强随机 token。 | 保护 `/_ops/` 只读诊断面，支持网页登录、`X-Ops-Token` 和 bearer token。 | 默认值只适合 demo；公开或长期运行应覆盖。 |
| `ADMIN_TOKEN` | `HF` | `S` | 仅开启 admin 时必须 | 无默认。 | 强随机 token。 | 保护 `/_admin/` 管理面，支持 `X-Admin-Token` 和 bearer token。 | 只有 `ADMIN_ENABLED=true` 时需要；不要放到 `V`。 |
| `ADMIN_ENABLED` | `HF` | `V` | 按需推荐 | `false`。 | `true` 或 `false`。 | 控制 `/_admin/` 是否开启。 | 开启前必须同时配置 `ADMIN_TOKEN`。 |
| `CONTROL_PLANE_DEFAULT_LANG` | `HF` | `V` | 按需 | `en`。 | `en` 或 `zh-CN`。 | 控制 `/_ops/` 和 `/_admin/` JSON 文案默认语言。 | 请求参数和请求头仍可临时覆盖语言。 |

## 第 3 层：可选 HF Variables

只有明确要覆盖默认行为时，才把这些变量写入 Hugging Face Variables。

| 变量 | 平台 | 位置 | 推荐 | 默认值 | 建议值 / 可能值 | 用途 | 注意 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `PUBLIC_BASE_URL` | `HF` | `V` | 按需 | `PUBLIC_BASE_URL` > `SPACE_HOST` > `http://localhost:7860`。 | `<hf-space-root-url>` 或自定义域名根地址。 | 指定公开根地址，供启动脚本推导 S3 API 和 Web Console 地址。 | 普通 Hugging Face 子域名部署可为空；自定义域名时再设置。 |
| `MINIO_SERVER_URL` | `HF` | `V` | 按需 | 从公开根地址推导。 | 通常等于 `PUBLIC_BASE_URL`。 | 告诉 libreFS 自己的公开 S3 API 根地址。 | 必须包含 `http://` 或 `https://`；不要带 `/console/`。 |
| `MINIO_BROWSER_REDIRECT_URL` | `HF` | `V` | 按需 | `${MINIO_SERVER_URL}/console/`。 | `${MINIO_SERVER_URL}/console/`。 | 告诉 libreFS Web Console 的公开访问地址。 | 必须落在 `/console/` 子路径，末尾 `/` 应保留。 |
| `GO_VERSION` | `HF` | `V` | 按需 | `1.26.3`。 | `1.26.3` 或上游明确要求的版本。 | 控制 Docker build 阶段下载的 Go 版本。 | 一般使用 `Dockerfile` 默认值；改动后需要 rebuild。 |
| `LIBREFS_REF` | `HF` | `V` | 按需 | `master`。 | `master`、tag 或明确 branch。 | 控制 Docker build 从上游 libreFS 拉取哪个 branch 或 tag。 | 上游默认分支是 `master`，不要未经确认改成 `main`。 |
| `LIBREFS_COMMIT` | `HF` | `V` | 按需 | `HEAD`。 | `HEAD` 或具体 commit SHA。 | 固定上游源码精确提交，避免 rebuild 时静默漂移。 | `HEAD` 表示不固定；具体 SHA 会触发构建期校验。 |
| `UBUNTU_VERSION` | `HF` | `V` | 通常不需要 | `24.04`。 | `24.04`。 | 覆盖 builder 和 runtime 使用的 Ubuntu 基础镜像版本。 | 通常写在 `Dockerfile` 默认值里；不要随手改基础镜像。 |
| `APP_UID` | `HF` | `V` | 通常不需要 | `1000`。 | `1000`。 | 控制容器内 runtime user UID。 | 改动会影响 `/data` 和 `/tmp/nginx` 写权限。 |
| `APP_GID` | `HF` | `V` | 通常不需要 | `1000`。 | `1000`。 | 控制容器内 runtime group GID。 | 改动会影响 `/data` 和 `/tmp/nginx` 写权限。 |
| `TARGETARCH` | `HF` | `V` | 不推荐手动设置 | BuildKit 注入，fallback 为 `amd64`。 | `amd64` 或 `arm64`。 | Docker build 目标架构，决定下载哪个 Go tarball。 | 通常由 Docker BuildKit 注入；手动设置容易和真实构建环境不一致。 |
| `MINIO_SITE_NAME` | `HF` | `V` | 按需 | 上游默认。 | 短站点名。 | 设置 libreFS / MinIO 站点显示名，便于在控制面识别实例。 | 不是鉴权信息；长期固定值更推荐写进 `hfs/start.sh` 默认值。 |
| `MINIO_SITE_REGION` | `HF` | `V` | 按需 | `us-east-1`。 | `us-east-1` 或客户端要求的 region。 | 设置 S3 region，影响部分客户端签名和兼容性。 | 通常保持 `us-east-1`，除非客户端明确要求其他 region。 |
| `MINIO_BROWSER` | `HF` | `V` | 按需 | 上游默认。 | `on` 或 `off`。 | 控制是否启用 Web Console。 | 一般保持 `on`；关闭后 `/console/` 不可用。 |
| `MINIO_BROWSER_REDIRECT` | `HF` | `V` | 按需 | 上游默认。 | `on` 或 `off`。 | 控制浏览器访问相关路径时是否按 libreFS 逻辑重定向到 Web Console。 | 一般保持 `on`；本部署仍要求 Console 在 `/console/` 子路径。 |
| `MINIO_UPDATE` | `HF` | `V` | 通常不需要 | 上游默认。 | `off`。 | 控制是否禁用上游更新提示。 | 更推荐写进 `hfs/start.sh` 默认值。 |
| `MINIO_CALLHOME_ENABLE` | `HF` | `V` | 通常不需要 | 上游默认 `off`。 | `off`。 | 控制是否启用上游 callhome。 | 通常不需要同步到 Hugging Face。 |
| `MINIO_API_ROOT_ACCESS` | `HF` | `V` | 通常不需要 | 上游默认 `on`。 | `on` 或 `off`。 | 控制 root credential 是否可直接访问 S3 和管理 API。 | 要收紧权限时再改 `off`，并准备普通用户和策略。 |
| `MINIO_API_CORS_ALLOW_ORIGIN` | `HF` | `V` | 按需 | 上游默认。 | `*` 或固定 origin 列表。 | 控制浏览器跨域访问允许的来源。 | 公开测试可保持 `*`；对接固定前端域名时再收窄。 |
| `DATA_DIR` | `HF` | `V` | 通常不需要 | `/data`。 | `/data`。 | 对象数据、元数据和默认日志所在目录。 | 必须和 Hugging Face Storage Volume mount 保持一致。 |
| `LIBREFS_API_ADDR` | `HF` | `V` | 通常不需要 | `:9000`。 | `:9000`。 | libreFS 内部 S3 API 监听地址。 | 改动必须同步 `hfs/nginx.conf` 的根路径反代。 |
| `LIBREFS_CONSOLE_ADDR` | `HF` | `V` | 通常不需要 | `:9001`。 | `:9001`。 | libreFS 内部 Web Console 监听地址。 | 改动必须同步 `hfs/nginx.conf` 的 `/console/` 反代。 |
| `NGINX_CONF` | `HF` | `V` | 通常不需要 | `/etc/nginx/nginx.conf`。 | `/etc/nginx/nginx.conf`。 | `hfs/start.sh` 和 `reload-nginx` action 使用的 Nginx 配置路径。 | 改动后必须确保容器内文件存在。 |
| `OPS_HOST` | `HF` | `V` | 通常不需要 | `127.0.0.1`。 | `127.0.0.1`。 | ops-service 内部监听地址。 | 改动必须同步 `hfs/nginx.conf` 的 `/_ops/` 反代。 |
| `OPS_PORT` | `HF` | `V` | 通常不需要 | `8081`。 | `8081`。 | ops-service 内部监听端口。 | 改动必须同步 `hfs/nginx.conf` 的 `/_ops/` 反代。 |
| `ADMIN_HOST` | `HF` | `V` | 通常不需要 | `127.0.0.1`。 | `127.0.0.1`。 | admin-service 内部监听地址。 | 改动必须同步 `hfs/nginx.conf` 的 `/_admin/` 反代。 |
| `ADMIN_PORT` | `HF` | `V` | 通常不需要 | `8082`。 | `8082`。 | admin-service 内部监听端口。 | 改动必须同步 `hfs/nginx.conf` 的 `/_admin/` 反代。 |
| `ADMIN_AUDIT_LOG` | `HF` | `V` | 通常不需要 | `/data/logs/admin-audit.jsonl`。 | `/data/logs/admin-audit.jsonl`。 | admin 写操作审计日志路径。 | 应落在可写且可持久化的目录。 |
| `ADMIN_FILES_ENABLED` | `HF` | `V` | 不推荐 | `false`。 | `false`。 | admin status payload 的预留字段。 | 设置它不会启用 file manager。 |
| `ADMIN_FILES_WRITE_ENABLED` | `HF` | `V` | 不推荐 | `false`。 | `false`。 | admin status payload 的预留字段。 | 设置它不会启用文件写入能力。 |

## 第 4 层：Volume、本地、平台注入和不建议配置项

| 变量 | 平台 | 位置 | 推荐 | 默认值 | 建议值 / 可能值 | 用途 | 注意 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `HF_STORAGE_BUCKET` | `HF` | `Volume` | 推荐只在 `.env.local` 记录 | 无 env 默认。 | `<hf-volume-source>`。 | 本地记录 Hugging Face Storage Bucket 来源。 | Volume 由 Space volume 配置管理，不是 `V` 或 `S`。 |
| `HF_STORAGE_MOUNT` | `HF` | `Volume` | 推荐只在 `.env.local` 记录 | `/data`。 | `/data`。 | 本地记录 Hugging Face Volume 挂载路径。 | 应和 `DATA_DIR` 的有效值保持一致。 |
| `HF_SPACE_ID` | `本地` | `本地` | 推荐只在 `.env.local` 记录 | 无。 | `<owner>/<space-name>`。 | 本机执行 `hf` CLI 命令时复用的 Space repo id。 | 不是容器环境变量，不同步到 `V` 或 `S`。 |
| `HF_SPACE_HOST` | `本地` | `本地` | 推荐只在 `.env.local` 记录 | 无。 | `<space-host>`。 | 本机记录公开 host，方便人工核对和脚本拼接。 | 容器实际使用 Hugging Face 注入的 `SPACE_HOST`。 |
| `S3_ENDPOINT` | `本地` | `本地` | 按需 | `<hf-space-root-url>`。 | `<hf-space-root-url>`。 | 本地 `scripts/smoke-s3-curl.sh` 使用的目标 endpoint。 | 不放 Hugging Face 或 GitHub。 |
| `AWS_REGION` | `本地` | `本地` | 按需 | `us-east-1`。 | `us-east-1`。 | 本地 S3 smoke 脚本签名使用的 region。 | 不放 Hugging Face 或 GitHub。 |
| `AWS_ACCESS_KEY_ID` | `本地` | `本地` | 按需 | 空。 | 通常等于 `MINIO_ROOT_USER`。 | 本地 S3 smoke 脚本兼容 AWS 命名的 access key。 | 可用 `MINIO_ROOT_USER` 代替，避免重复值漂移。 |
| `AWS_SECRET_ACCESS_KEY` | `本地` | `本地` | 按需 | 空。 | 通常等于 `MINIO_ROOT_PASSWORD`。 | 本地 S3 smoke 脚本兼容 AWS 命名的 secret key。 | 可用 `MINIO_ROOT_PASSWORD` 代替，避免重复值漂移。 |
| `S3_SMOKE_BUCKET` | `本地` | `本地` | 按需 | 自动生成。 | 临时 bucket 名。 | 本地 S3 smoke 脚本要创建的临时 bucket 名称。 | 不要使用 `console`、`minio`、`_ops`、`_admin` 等保留路径名称。 |
| `S3_SMOKE_OBJECT` | `本地` | `本地` | 按需 | `smoke.txt`。 | `smoke.txt`。 | 本地 S3 smoke 脚本要上传的临时对象名。 | 不要以 `/` 开头。 |
| `S3_SMOKE_PAYLOAD` | `本地` | `本地` | 按需 | 自动生成时间戳内容。 | 任意短测试文本。 | 本地 S3 smoke 脚本要上传和回读的测试内容。 | 只用于本地 smoke，不放 Hugging Face 或 GitHub。 |
| `SPACE_ID` | `平台注入` | `不配置` | 不要手动配置 | Hugging Face 自动注入。 | 保持空。 | 平台注入的 Space id，ops config 摘要会展示。 | 不要手动放 `V` 或 `S`。 |
| `SPACE_HOST` | `平台注入` | `不配置` | 不要手动配置 | Hugging Face 自动注入。 | 保持空。 | 平台注入的公开 host，`hfs/start.sh` 用它推导公开根 URL。 | 不要手动放 `V` 或 `S`；自定义域名用 `PUBLIC_BASE_URL`。 |
| `MINIO_DOMAIN` | `HF` | `不配置` | 不推荐 | 通常保持空。 | 通常保持空。 | 上游用于 virtual-hosted bucket 访问模型的域名配置。 | HF 子域名部署应保持 path-style，不建议设置。 |
| `MINIO_ADDRESS` | `HF` | `不配置` | 不推荐 | 通常保持空。 | 通常保持空。 | 上游用于控制 S3 API 监听地址的变量。 | 本部署由 `LIBREFS_API_ADDR` 和启动参数控制。 |
| `MINIO_CONSOLE_ADDRESS` | `HF` | `不配置` | 不推荐 | 通常保持空。 | 通常保持空。 | 上游用于控制 Web Console 监听地址的变量。 | 本部署由 `LIBREFS_CONSOLE_ADDR` 和启动参数控制。 |
| `MINIO_CONFIG` | `HF` | `不配置` | 不推荐 | 通常保持空。 | 通常保持空。 | 上游用于改变配置目录或配置来源。 | 会改变启动契约，本部署不需要。 |
| `MINIO_CONFIG_ENV_FILE` | `HF` | `不配置` | 不推荐 | 通常保持空。 | 通常保持空。 | 上游用于从 env file 读取配置。 | 会改变配置来源，本部署不需要。 |
| `MINIO_VOLUMES` | `HF` | `不配置` | 不推荐 | 通常保持空。 | 通常保持空。 | 上游用于指定数据卷列表。 | 本部署由 `DATA_DIR` 控制数据目录。 |
| `MINIO_KMS_SECRET_KEY` | `HF` | `S` | 不推荐，除非启用加密 | 空。 | 强随机 KMS key。 | 服务端加密使用的 KMS key。 | 只有明确启用服务端加密时才配置；key 丢失会导致已加密数据无法读取。 |
| `MINIO_KMS_AUTO_ENCRYPTION` | `HF` | `V` | 不推荐，除非启用加密 | 空。 | `on` 或 `off`。 | 控制是否自动对对象启用服务端加密。 | 只有明确设计好 KMS key 管理和恢复策略时才配置。 |

## GitHub 平台

本仓库未发现必须写入 GitHub 的 Variables 或 Secrets。若以后增加 GitHub Actions，再新增 `GH + V/S` 行，并遵守同样边界：

- GitHub Variables 只放非敏感值。
- GitHub Secrets 只放 secret value，公开文档只写 key 名称。
- 不要把 Hugging Face root 凭证、ops token、admin token 复制到 GitHub，除非 workflow 明确需要并已评估权限边界。

## 云端回读命令

查看 Hugging Face Variables：

```bash
hf spaces variables list <hf-space-id>
```

查看 Hugging Face Secrets 的 key：

```bash
hf spaces secrets list <hf-space-id>
```

查看 Hugging Face Volume：

```bash
hf spaces volumes list <hf-space-id>
```

查看 GitHub Variables：

```bash
gh variable list --repo <owner>/<repo>
```

查看 GitHub Secrets 的 key：

```bash
gh secret list --repo <owner>/<repo>
```

Secrets 只能回读 key，不能回读 value。需要维护真实值时，把它们写入本地 `.env.local`，并确认 `.env.local` 被 `.gitignore` 和 `.dockerignore` 忽略。

同步示例只使用占位符：

```bash
hf spaces secrets add <hf-space-id> \
  -s MINIO_ROOT_USER='<root-user>' \
  -s MINIO_ROOT_PASSWORD='<root-password>'

hf spaces variables add <hf-space-id> \
  -e ADMIN_ENABLED=true
```

不要把真实 secret value、API 根地址、账号、密码、token 写入 README、docs、PR 文案、日志或截图。
