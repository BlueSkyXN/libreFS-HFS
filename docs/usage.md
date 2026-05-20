# 使用指南

本文档说明如何使用 LibreFS HFS 的 Web Console、S3 endpoint、S3-compatible client 和 HTTP 直链。

## Endpoint

```text
S3 endpoint:
https://blueskyxn-librefs-hfs.hf.space

Web Console:
https://blueskyxn-librefs-hfs.hf.space/console/
```

S3 client 建议使用 path-style addressing。Hugging Face Space 子域名下不适合 virtual-hosted bucket URL。

## Web Console

打开：

```text
https://blueskyxn-librefs-hfs.hf.space/console/
```

登录信息来自：

- `MINIO_ROOT_USER`
- `MINIO_ROOT_PASSWORD`

登录后应能看到 Object Browser、Buckets、Policies、Identity、Monitoring 等菜单。

常见 Console 操作：

1. 创建 bucket。
2. 上传对象。
3. 浏览对象。
4. 创建 access key。
5. 设置 bucket policy。
6. 查看 bucket 元数据。

## S3 Client 配置

任何 S3-compatible client 都应使用：

```text
Endpoint: https://blueskyxn-librefs-hfs.hf.space
Access key: MINIO_ROOT_USER 的值
Secret key: MINIO_ROOT_PASSWORD 的值
Region: us-east-1
Addressing style: path-style
```

## 使用 MinIO Client 或 libreFS Client

如果使用 MinIO `mc` 或 libreFS `lc`，先配置 alias：

```bash
mc alias set librefs-hfs \
  https://blueskyxn-librefs-hfs.hf.space \
  "$MINIO_ROOT_USER" \
  "$MINIO_ROOT_PASSWORD"
```

创建 bucket：

```bash
mc mb librefs-hfs/public
```

上传文件：

```bash
mc cp ./example.txt librefs-hfs/public/example.txt
```

下载文件：

```bash
mc cp librefs-hfs/public/example.txt ./downloaded-example.txt
```

列出 bucket：

```bash
mc ls librefs-hfs
```

## 使用 AWS CLI

AWS CLI 可以通过 `--endpoint-url` 访问：

```bash
aws --endpoint-url https://blueskyxn-librefs-hfs.hf.space s3 ls
```

上传：

```bash
aws --endpoint-url https://blueskyxn-librefs-hfs.hf.space \
  s3 cp ./example.txt s3://public/example.txt
```

下载：

```bash
aws --endpoint-url https://blueskyxn-librefs-hfs.hf.space \
  s3 cp s3://public/example.txt ./downloaded-example.txt
```

如果 client 默认使用 virtual-hosted addressing 并报错，需要切到 path-style addressing。

## HTTP 公开直链

对象 URL 格式：

```text
https://blueskyxn-librefs-hfs.hf.space/<bucket>/<object>
```

示例：

```text
https://blueskyxn-librefs-hfs.hf.space/public/example.txt
```

未配置公开策略时，匿名访问会返回 `403 AccessDenied`。这是正常行为。

## Public Read Bucket Policy

如果 bucket 名为 `public`，最小匿名读取策略如下：

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

可以用 Console 的 bucket policy editor 设置，也可以用 `mc`：

```bash
mc anonymous set-json public-read-policy.json librefs-hfs/public
```

## 预期 HTTP 行为

| 请求 | 预期结果 |
| --- | --- |
| `GET /minio/health/ready` | `200`，响应体为空。 |
| 未签名 `GET /` | S3 XML error，例如 `400 Bad Request`；这是正常浏览器根路径行为。 |
| 签名 `GET /` | `200 ListAllMyBucketsResult`。 |
| 未签名 `GET /private-bucket/object` | `403 AccessDenied`。 |
| 设置公开策略后未签名 `GET /public-bucket/object` | `200`，返回对象内容。 |

## Bucket 命名建议

避免使用这些 bucket 名称：

- `console`
- `minio`
- `_ops`
- `_admin`

原因：

- `/console/` 是 Web Console 保留路径。
- `/minio/...` 被健康检查和管理 API 使用。
- `/_ops/` 是只读诊断入口。
- `/_admin/` 是默认关闭的管理入口。

推荐使用：

```text
public
temp
share
uploads
artifacts
```

## Ops/Admin 入口

`/_ops/` 是给维护者使用的只读诊断入口，不是对象访问路径。它需要 `OPS_TOKEN`：

```bash
curl -fsS -H "X-Ops-Token: $OPS_TOKEN" \
  "https://blueskyxn-librefs-hfs.hf.space/_ops/health?lang=zh-CN"
```

`/_admin/` 是受控管理入口，代码默认关闭。当前生产环境已设置 `ADMIN_ENABLED=true`，因此需要 `ADMIN_TOKEN` 才能访问：

```bash
curl -fsS -H "X-Admin-Token: $ADMIN_TOKEN" \
  "https://blueskyxn-librefs-hfs.hf.space/_admin/api/actions?lang=zh-CN"
```

当前 admin 只提供 `run-health-checks` 和 `reload-nginx` 两个白名单 action；没有 Web terminal、file manager、bucket policy 管理或 root credential 管理。

## 数据持久性

当前 `hf spaces volumes list` 显示已经把 Hugging Face Storage Bucket 挂载到 `/data`。如果后续移除挂载，上传文件应视为临时数据。

即使存在挂载，也建议在关键变更后做一次“上传对象 -> 重启 Space -> 读取对象 -> rebuild 后再次读取”的验收，再把对象当作已通过持久化验证的数据。

重要文件请同时保存在其他持久位置，例如：

- 本地磁盘
- GitHub Release assets
- Hugging Face Dataset
- 其他对象存储
- 挂载到 `/data` 的 Hugging Face Storage Bucket
