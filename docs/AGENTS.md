# docs navigation card

`docs/` 是 LibreFS HFS 的公开说明和运维事实源。修改任何文档前先读根 `AGENTS.md`、本卡，以及需要同步的目标文档；涉及实时状态时优先看 `docs/contract-alignment.md`。

## Local invariants

- 区分代码默认值和当前生产配置：例如 `ADMIN_ENABLED` 代码默认是 `false`，当前生产状态必须用 HF CLI 或 Space API 回读后再写。
- Secret 文档只能写 key 名称和 presence，不写 `MINIO_ROOT_PASSWORD`、`OPS_TOKEN`、`ADMIN_TOKEN` 等 value。
- Health check 只证明进程/路由可用，不能写成 S3 写入、public policy 或持久化验收通过。
- Volume 挂载只证明 `/data` 具备持久化条件；持久化结论必须来自上传、重启、读取、rebuild 后再读取。
- ops/admin 支持 `en` 和 `zh-CN`；机器字段如 `error`、endpoint path、action `name` 保持稳定，本地化字段是 `message`、`hint`、`label`、`description`、`risk`、`notes`。
- 公开 ops API 必须写完整 `/_ops/...` 路径；裸 `/health`、`/system`、`/config`、`/version`、`/metrics` 只表示 Nginx 剥前缀后的内部 handler path。
- `?token=` 只用于 ops 浏览器首次登录或临时调试；文档应优先写 header/bearer 脚本调用，以及成功网页登录后使用 `HttpOnly` cookie 的语义。

## Local rules

- 改代码契约、远端配置或生产快照时，先更新 `docs/contract-alignment.md`，再同步 `README.md` 和相关 docs。
- 改 endpoint、Console URL、S3 URL、ops/admin 路由、网页登录态或 token 传递方式时，同步检查 `README.md`、`configuration.md`、`operations.md`、`architecture.md`、`source-walkthrough.md`。
- `troubleshooting.md` 只记录真实遇到或高概率故障；不写未验证的猜测。

## Do not

- 不要把一次 spot check 写成长期保证。
- 不要把 `/_ops/` 写成管理面，或把 `/_admin/` 写成默认开启。
- 不要承诺生产级对象存储能力。

## Validation

- 文档-only 修改：`git diff --check -- README.md docs AGENTS.md`。
- 涉及运行契约：`scripts/validate-contract.sh`。
- 涉及实时状态、HF Variables/Secrets/Volume 或 runtime sha：用根 `AGENTS.md` 中的 HF/Space 回读命令复核；Secrets 只能确认 key，不能回显 value。
