# Photo Avatar video integration

Development date: 2026-10-21. Status: browser end-to-end GPU video verified; physical Android testing remains pending.

- Preserve the working voice integration on API 18080 and TURN 18443.
- Use the separate backend checkout /home/user/cyberverse-workspaces/frontend-assist.
- Backend feature branch: feat/frontend/photo-avatar-video.
- New Docker Compose project: shiyi-avatar-assist. GPU: physical device 1 only.
- Avatar API: 18082; internal inference: 55053; TURN TCP: 18445.
- Mount existing FlashHead checkpoints read-only. Config, data and caches are independent.
- Keep runtime configuration and credentials in ignored .shiyi-avatar/.
- Retain the existing approved Qwen voice provider. Do not install a credential exposed in chat.
- Client photo upload requires explicit consent. No camera or voice cloning is implied.
- Publish reviewed source only. Never publish runtime images, credentials, portraits uploaded by users or local runtime snapshots.

The reviewed Flutter source is shared under apps/shiyi-client on the
legend-James/CyberVerse shiyi-integration branch. This does not imply that
uncommitted backend work or server runtime state has been synchronized.

## 使用入口

师弟在 Windows GPU 服务器本机运行时，优先阅读 `SHARING.md`，使用
`start-server-client.bat`；它只运行客户端并连接本机已有服务，不需要 SSH 连接自己。
下方旧 SSH 入口仅适用于已经配置好管理员授权和个人工具链的另一台开发电脑。

双击项目根目录的 `open-shiyi-avatar-app.bat`。它启动或复用独立的照片视频服务、
WSL 回环桥接和本机 SSH 隧道，并打开 `http://127.0.0.1:7358/`。
启动时会检查源码时间并重建过时的网页，避免一直看到旧预览。
服务器需开机、Tailscale/SSH 可达，Docker Desktop 和 Ubuntu WSL 可运行。
不要关闭 SSH 隧道进程；首次加载 GPU 模型需要等待，不等于服务卡死。

登录后进入联系人，选择“视频聊天”，使用示例肖像或选择本人/已获授权照片。
勾选肖像授权并点击“开始照片视频通话”。连接后自动播放 AI 问候，
可以输入文字，或开启麦克风直接说话。通话画面标注“内容由AI生成”。
这不是照片里真人本人，不是 3D 模型，也没有克隆真人声音。

语音仍使用原来的 API 18080；照片视频单独使用 API 18082。
“我的 → 设置”可分别保存并测试两种服务的地址，按本地账号隔离。
地址字段不是 API Key 字段，不要在客户端填写模型密钥。

## 实际链路

Flutter → 本机回环 SSH 隧道 → Windows/WSL 回环代理 → 独立 Docker API →
Qwen Omni 云端语音对话 + GPU 1 上的 FlashHead Lite → WebRTC 音视频 → Flutter。

- 已复用服务器现有 FlashHead/wav2vec2 权重，只读挂载，不重新下载或训练。
- GPU 用物理 GPU 1 的 UUID 绑定，避免 Docker/WSL 的设备序号歧义误占 GPU 0。
- 模型加载后约占 6.2 GB 显存；实际占用会随负载变化。
- 运行配置在 `.shiyi-avatar/config`，数据和缓存也在该私有目录。不要提交该目录。
- 原有 integration、backend-dev 及共享 infra 容器未改动。并发暂限一个照片视频会话。
- 沿用服务端已配置的通义密钥与国内站端点；没有安装聊天中暴露的第三方密钥。
- 供应商端点必须与密钥地区匹配，只复制密钥而遗漏 DASHSCOPE_BASE_URL 会导致 401。
- 当前 Docker Desktop 新容器端口发布异常，使用 loopback_proxy.py 绕过，未重启共享 Docker。
  API/TURN 仅绑定回环地址，经 SSH 转发；不开放公网端口。

## 验收记录

2026-10-21 在真实 Edge 浏览器中通过原 Flutter 客户端验证：

- 肖像经明确授权后上传，512×512 视频实际解码帧持续增长，人物画面像素随时间变化。
- 观测到约 18–20 FPS，属于本次环境实测，不是性能承诺。
- 收到真实 AI 问候、文字触发的语音回复，以及中文测试音频的识别和回复。
- 音频元素实际播放且未静音，接收音频能量增长，不把字幕或健康检查当作播放成功。
- 手机 390×844 视口显示正常；360/390 中英文授权与固定控件自动测试通过。
- 挂断后 PeerConnection 全部关闭，麦克风轨道 ended，音视频元素清除；重连等待旧会话释放。
- 原 18080 纯语音链路回归通过；Flutter analyze 无问题，96 项测试通过。

可审阅的本机测试记录在 `.toolchain/runtime/avatar-integration/`。
测试中用音频文件替换浏览器测试麦克风，正式客户端仍采集用户授权的麦克风。
对话响应速度受云端服务、VAD、网络和 GPU 生成影响；不保证每次固定延迟。

## 低带宽隧道配置

复测细节较多的肖像时，原后端最低 800 kbps 的拥塞控制和首次 1800 kbps
编码会在本次 TCP 转发上积压，导致延迟增加甚至 ICE 断连。
本分支增加可选的 CYBERVERSE_DIRECT_VIDEO_KBPS，仅对自己的部署配置，
不设置时保持上游默认行为。此部署选择 240 kbps，音频流量另计。
上限同时作用于初始/GCC 码率与编码器首次/自适应码率，避免仅改一处仍突发积压。

build_server.py 在独立 checkout 中应用小范围补丁、执行 direct 包测试，
再用 Go 1.25 + CGO 编译 API，连同匹配的动态加载器及运行库私有打包，
以只读方式挂载到自己的 API 容器；不混用 WSL 与原镜像的不同 glibc 版本。
构建需要 Go、GCC、pkg-config 和 opus/opusfile/soxr 开发库，当前服务器已有。
运行无需修改原 API 镜像，不重启 GPU 模型，也不改师弟的副本。
源码或补丁更改后需重新运行 build_server.py，并仅重建自己的 API 容器。
提高该码率前需确认链路带宽；公网正式部署应使用生产 TURN 网络，避免多层 TCP 转发。

## 安卓真机联调

浏览器手机尺寸验收不等于真机验收。模拟器可用 `10.0.2.2`，真机不能直接用这个地址。
USB 真机可在本机一键入口运行后，开启 USB 调试并授权电脑，再执行：

```powershell
adb devices
adb reverse tcp:18080 tcp:18080
adb reverse tcp:18443 tcp:18443
adb reverse tcp:18082 tcp:18082
adb reverse tcp:18445 tcp:18445
```

在 App 设置中将语音地址设为 `http://127.0.0.1:18080`，
照片视频地址设为 `http://127.0.0.1:18082`，分别测试连接。
需使用包含本次改动的 App 安装包，USB 断开或隧道关闭后转发不可用。
无线/正式发布需 HTTPS、鉴权、用户隔离和正确的 TURN 对外网络部署，
不能直接把当前无生产鉴权的联调端口公开。

## Git 同步边界

远端本次仅在 `frontend-assist` 的 `feat/frontend/photo-avatar-video` 分支添加部署脚本。
未 commit、未 push，师弟的工作目录未切换或覆盖。服务运行不代表 GitHub 已同步。
本次客户端源码已作为独立子目录纳入 fork 的 shiyi-integration 分支；
不改变运行中后端副本的分支或文件。后续修改通过各自功能分支和 PR 协作；
运行配置、肖像数据、密钥、模型权重和本地运行快照均不上传。
