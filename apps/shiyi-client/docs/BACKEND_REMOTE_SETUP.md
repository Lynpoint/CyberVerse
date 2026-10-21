# 后端联调与共享边界 / Backend integration boundaries

此公开文件替代原开发机的个人部署笔记。SSH 主机地址、账号、公钥、密钥配置、连接排错日志及运行快照不随源码发布。

This public overview intentionally excludes personal SSH details, credentials and runtime snapshots.

## 当前共享方式

- 客户端位于本仓库 `shiyi-integration` 分支的 `apps/shiyi-client`。原有 `frontend` 是上游 Vue 前端，不是这个 Flutter 客户端。
- 师弟的电脑就是 Windows GPU 服务器。请把客户端 clone 到独立目录，安装 Flutter 后在服务器本机浏览器运行，具体步骤见 [SHARING.md](SHARING.md)。
- 本机浏览器通过 API 18080 使用语音，通过 API 18082 使用照片视频；对应 TURN TCP 端口为 18443、18445。先验证 Windows 到 WSL 的回环访问，不要假定端口一定能通。
- 模型密钥保存在服务端；客户端不需要供应商 API Key。源码不包含模型权重或已配置好的后端运行环境。
- 从其他电脑访问时，由管理员为各自账号配置访问授权与 SSH/API/TURN 转发；不要共享 SSH 私钥。

## 三个后端工作副本仍然分开

`backend-dev` 用于后端开发，`frontend-assist` 用于独立协助，`integration` 用于经验证的联调基线。客户端另开 checkout，不在这三个运行目录中切分支、强制拉取或复制覆盖。

GitHub 同步不等于服务器部署。提交客户端不会修改运行中的 Docker 容器，也不会启动、更新或重启 GPU 推理。运行配置、模型、数据、密钥、缓存和运行镜像不进入 Git。

## 开发与生产

当前服务仅用于受控联调，照片视频并发暂为一个。不要公开无生产鉴权的 API 或 TURN 端口。公开产品还需要 HTTPS/WSS、真实用户鉴权、用户隔离、配额、数据删除与生产媒体网络。

照片视频实现及已验证范围见 [AVATAR_VIDEO.md](AVATAR_VIDEO.md)。浏览器验收不等于 Android 真机验收，模型权重及第三方素材仍需按各自许可和授权使用。
