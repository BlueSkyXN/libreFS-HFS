# 文档索引

这个目录记录 LibreFS HFS 的完整说明，包括构建方式、运行架构、Hugging Face Space 配置、S3 使用方法、远端验收流程和常见故障处理。

## 文档列表

| 文档 | 说明 |
| --- | --- |
| [架构说明](architecture.md) | 解释 Docker build、runtime 进程、Nginx 路由和请求流转。 |
| [Hugging Face 部署指南](deployment-huggingface.md) | 记录 Space 部署、Secrets、Variables、rebuild 和日志查看方法。 |
| [配置参考](configuration.md) | 汇总 build args、Space Secrets、Space Variables、runtime env、端口和路径。 |
| [源码逐文件说明](source-walkthrough.md) | 逐项解释仓库文件、运行入口、修改边界和验收命令。 |
| [使用指南](usage.md) | 说明 Web Console、S3 endpoint、S3 client、公开直链和 bucket policy。 |
| [运维与验收](operations.md) | 记录健康检查、smoke test、runtime logs、rebuild 检查和运行风险。 |
| [故障排查](troubleshooting.md) | 汇总本项目真实遇到过的 build/runtime/Console/S3 问题。 |
| [开发状态与下一步计划](development-plan.md) | 汇总当前实现、未完成事项、优先级和近期开发计划。 |

## 当前线上实例

```text
Space 仓库:
https://huggingface.co/spaces/BlueSkyXN/libreFS-HFS

公开 endpoint:
https://blueskyxn-librefs-hfs.hf.space

Web Console:
https://blueskyxn-librefs-hfs.hf.space/console/
```

## 当前能力边界

当前线上实例的公开健康检查和 Console 静态资源可直接复核；涉及 root 凭证的 S3 写入、公开策略和持久化读回，需要在操作时重新执行 smoke test。

- Hugging Face 远端 Docker build 成功。
- 从 Ubuntu + libreFS 源码编译，不使用官方 Docker image。
- `cpu-basic` runtime 可启动。
- Nginx 在 `7860` 上合并 S3 API 和 Web Console。
- Web Console 可在 `/console/` 正常渲染。
- Web Console 登录、S3 SigV4 写入、公开直链和持久化读回需要 root 凭证或测试对象，不能只靠 health check 证明。

## 本地轻量验证

不安装项目依赖、不本地编译 libreFS 时，可以先运行仓库契约检查：

```bash
scripts/validate-contract.sh
```

需要同时检查公开健康端点时：

```bash
scripts/validate-contract.sh --remote
```

需要做凭证型 S3 smoke test 且不想安装 `aws` 或 `mc` 时，可以使用仓库脚本：

```bash
MINIO_ROOT_USER='<access-key>' \
MINIO_ROOT_PASSWORD='<secret-key>' \
scripts/smoke-s3-curl.sh
```

这个脚本会先拒绝已有 bucket，再创建临时 bucket 和对象，验证签名读写、默认匿名拒绝、public read policy 和匿名直链，然后清理临时资源。

## 当前非目标

这个 Space 不是生产级对象存储，不建议承载唯一数据源。

当前 `hf spaces volumes list` 显示已经把 Storage Bucket 挂载到 `/data`。挂载只证明路径具备持久化条件；只有完成“上传对象 -> 重启 Space -> 读取对象 -> rebuild 后再次读取”后，才能把某次数据持久性验收视为通过。
