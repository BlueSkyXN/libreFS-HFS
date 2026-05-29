# hfs navigation card

`hfs/` 放本仓库的 Hugging Face Space runtime glue。按 HFS 开发范式，本仓库属于 Pattern A，repo root 仍是 Space root；多服务运行胶水集中在本目录，避免和 Space metadata、文档、验证脚本混在根目录。

## Local invariants

- `start.sh` 是容器入口，最终仍由 Dockerfile 复制到 `/start.sh` 并通过 `CMD ["/start.sh"]` 执行。
- `nginx.conf` 是容器内 `/etc/nginx/nginx.conf` 的来源，必须继续监听 `7860`。
- `ops_service.py` 和 `admin_service.py` 运行时分别复制为 `/usr/local/bin/librefs-ops-service.py` 和 `/usr/local/bin/librefs-admin-service.py`。
- 公开路由保持：S3 API 在 `/`，Console 在 `/console/`，只读诊断在 `/_ops/`，默认关闭管理面在 `/_admin/`。
- `/_ops/` 只读；`/_admin/` 默认关闭，写 action 必须白名单、显式 `confirm=true` 并写审计日志。

## Local rules

- 修改本目录任一文件后，同步检查根 `Dockerfile`、`scripts/validate-contract.sh`、`docs/contract-alignment.md` 和 `docs/source-walkthrough.md`。
- 修改端口、路径、header、进程监管或鉴权语义时，同步检查 `README.md`、`docs/architecture.md`、`docs/configuration.md` 和 `docs/operations.md`。
- 新增 runtime glue 文件时，明确它是否需要被 Dockerfile 复制进镜像，并把路径写进 `scripts/validate-contract.sh`。

## Do not

- 不要把 `README.md` 或 `Dockerfile` 搬进本目录；Pattern A 的 Space root 仍是仓库根。
- 不要在本目录放 `.env.local`、真实 token、root credentials、本地数据或临时运行产物。
- 不要把 `/_ops/` 扩展成管理、命令执行、文件读取、重启或 secret 返回入口。
- 不要默认开启 `/_admin/`，也不要新增 terminal、file manager、bucket/policy/root credential 管理或 `librefs` restart。

## Validation

- 语法：`bash -n hfs/start.sh`，`python3 -m py_compile hfs/ops_service.py hfs/admin_service.py`。
- Nginx：`mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi && nginx -t -c "$PWD/hfs/nginx.conf"`。
- 契约：`scripts/validate-contract.sh`。
