# 文档索引

这个目录记录 LibreFS HFS 的完整说明，包括构建方式、运行架构、Hugging Face Space 配置、S3 使用方法、远端验收流程和常见故障处理。

## 文档列表

| 文档 | 说明 |
| --- | --- |
| [架构说明](architecture.md) | 解释 Docker build、runtime 进程、Nginx 路由和请求流转。 |
| [Hugging Face 部署指南](deployment-huggingface.md) | 记录 Space 部署、Secrets、Variables、rebuild 和日志查看方法。 |
| [配置参考](configuration.md) | 汇总 build args、Space Secrets、Space Variables、runtime env、端口和路径。 |
| [使用指南](usage.md) | 说明 Web Console、S3 endpoint、S3 client、公开直链和 bucket policy。 |
| [运维与验收](operations.md) | 记录健康检查、smoke test、runtime logs、rebuild 检查和运行风险。 |
| [故障排查](troubleshooting.md) | 汇总本项目真实遇到过的 build/runtime/Console/S3 问题。 |

## 当前线上实例

```text
Space 仓库:
https://huggingface.co/spaces/BlueSkyXN/libreFS-HFS

公开 endpoint:
https://blueskyxn-librefs-hfs.hf.space

Web Console:
https://blueskyxn-librefs-hfs.hf.space/console/
```

## 已验证能力

当前线上实例已经验证：

- Hugging Face 远端 Docker build 成功。
- 从 Ubuntu + libreFS 源码编译，不使用官方 Docker image。
- `cpu-basic` runtime 可启动。
- Nginx 在 `7860` 上合并 S3 API 和 Web Console。
- Web Console 可在 `/console/` 正常渲染。
- Web Console 可登录并进入 Object Browser。
- S3 SigV4 `ListBuckets`、创建 bucket、上传对象、读取对象可用。
- bucket policy 放开匿名 `s3:GetObject` 后，HTTP 直链可用。

## 当前非目标

这个 Space 不是生产级对象存储，不建议承载唯一数据源。

当前部署可以不挂载 Hugging Face Storage Bucket。如果不挂载，`/data` 内的数据应视为临时数据，适合测试、临时共享和短期直链，不适合作长期保存。
