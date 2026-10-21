# CyberVerse 后端对接说明

核对仓库：https://github.com/Lynpoint/CyberVerse
核对提交：13a6a95b47e5e6f0809683458767746ad54d7d7f
重新核对日期：2026-10-20

远程部署、Git 同步、Docker 风险与 Windows 联调，请阅读 [BACKEND_REMOTE_SETUP.md](BACKEND_REMOTE_SETUP.md)。

2026-10-20 协作方案增量修订：保留现有 Flutter HTTP/WS 适配，不重写客户端。你在本机开发前端；若服务器确认为 Windows，后端在 WSL2 Ubuntu 内运行，师弟 backend-dev、你的 frontend-assist、稳定 integration 使用三份独立 clone/配置/数据/依赖环境。对应 API 8081、8082、8080；两个开发分支通过 PR 合入 shiyi-integration，再由发布负责人更新稳定副本。隧道脚本新增 BackendDev / FrontendAssist / Integration Profile，具体连接见远程指南第零、四、七节。目录和端口是协作隔离，共用 adm 不等于安全权限隔离；本次未远程部署。

依据源码：server/internal/api/router.go、frontend/src/services/api.ts、frontend/src/types/index.ts、frontend/src/composables/useChat.ts、frontend/src/composables/useDirectWebRTC.ts。不是根据项目名称猜测接口。

## 已确认接口

| 用途 | 方法与路径 | 说明 |
| --- | --- | --- |
| 健康检查 | GET /api/v1/health | App 设置已实际调用该接口；需要用户提供可用地址 |
| 获取角色 | GET /api/v1/characters | 联系人数据可由此转换 |
| 创建角色 | POST /api/v1/characters | JSON 角色资料；需按部署的 components/provider 配置填充 |
| 修改角色 | PUT /api/v1/characters/{id} | 修改人设、配置等 |
| 删除角色 | DELETE /api/v1/characters/{id} | 真实删除前需加入用户归属校验 |
| 上传形象 | POST /api/v1/characters/{id}/avatar | multipart/form-data 字段名为 avatar |
| 创建会话 | POST /api/v1/sessions | JSON：character_id、mode（standard/omni） |
| 发送文字 | POST /api/v1/sessions/{id}/message | JSON：text；此请求本身不是完整 AI 回复 |
| 关闭会话 | DELETE /api/v1/sessions/{id} | 挂断/离开时释放服务器资源 |
| 事件通道 | /ws/chat/{id} | WebSocket；真实回复、状态和媒体协商需解析事件 |
| 查询历史 | GET /api/v1/characters/{id}/conversations/messages | 可用于恢复服务端消息 |

lib/core/cyberverse_api.dart 提供主要 HTTP 接口；cyberverse_protocol.dart 解析会话与事件；cyberverse_socket.dart 提供 Web/Android WebSocket 传输。会话模式默认省略，由后端决定，也可显式选择 standard/omni；保留 streaming_mode、livekit_token、供应商配置和警告。配有 HTTP 契约及本地 WebSocket 测试。

目前只有健康检查接到 App 界面。新增 tool/check_backend.dart 可请求指定服务器进行文字联调，但没有自动开启 App 的真实通话。本地创建、聊天、通话和生活记录仍是原来的演示/本地功能。

## 后端还需提供的业务能力

1. 账号注册、登录、修改密码、注销、Token 生命周期和角色/会话归属校验。检查的上游路由没有现成的移动 App 用户账号体系。建议在 CyberVerse 前增加业务服务层，按 user_id 隔离角色、音频和历史。
2. 声音样本上传与音色克隆/登记。现有 voice_provider、voice_type 以及 test-voice 用于配置/检查音色，不能等同于上传个人录音并自动克隆。实际能力依赖使用的 TTS 提供商。
3. 素材任务状态、失败重试、异步处理、用户数据删除。
4. 正式隐私政策、真实运营方、保留时限和数据处理方信息。

## 推荐接入顺序

1. 提供运行中的 CyberVerse 服务根地址、健康检查结果、所选模型/供应商配置。电脑通过稳定隧道用 http://127.0.0.1:8080，Android 官方模拟器用 http://10.0.2.2:8080；API 端口随所选环境变化。隧道只绑定电脑回环，Wi-Fi 真机不能直接使用电脑 LAN IP 访问它；USB 的 adb reverse 仅用于 API 调试，正式媒体使用可达的 HTTPS/WSS 与 TURN/LiveKit。详见远程指南第七节。
2. 实现业务账号 API，替换 AppState 中本地鉴权；不要把模型 API 密钥放进 App。
3. 将创建流程改为创建服务器角色 → multipart 上传形象 → 上传/登记音色 → 保存角色配置；处理中显示真实任务状态。保留服务端 id。
4. 从服务器拉取当前用户的角色列表；App 内“创建历史”就是同一批角色的时间排序视图。
5. 聊天先创建 session，连接并订阅 WS，再发送文字。HTTP message 的响应不是完整回复。新增传输层保留 llm_token、transcript、is_final、turn_seq 等字段；界面仍需合并消息、处理打断和重连。退出时 DELETE 会话。
6. 实时媒体根据 streaming_mode 选择 Direct 或 LiveKit，同时检查供应商专用配置。Direct 顺序：客户端 webrtc_ready，服务器 webrtc_config / webrtc_offer，客户端 webrtc_answer，双方 ice_candidate。ICE 使用 sdp_mid、sdp_mline_index。新增代码仅实现消息契约与信令传输，尚无 RTCPeerConnection、媒体轨道、渲染器或 LiveKit SDK。
7. 创建页已加入麦克风权限和运行时授权，支持本地声音样本录制与试听，并在离开录音页或进入后台时停止采集。模拟通话仍不会打开麦克风或摄像头；真实通话还需接入媒体链路、摄像头权限、蓝牙/扬声器路由和真机生命周期测试。

## 上线前应替换

本地 SharedPreferences 账号 → 服务端鉴权；本地规则回复 → 真实会话事件；模拟通话 → WebRTC；样本保存 → 后端上传与克隆服务；调试签名 → 正式签名；HTTP 明文 → HTTPS；演示协议 → 正式经审核的文本。

本项目独立编写 Flutter 前端，没有改动或重新分发 CyberVerse 服务端代码。服务端部署和后续衍生开发请查阅上游 LICENSE。
