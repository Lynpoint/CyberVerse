# 客户端交接与 GitHub 协作

更新日期：2026-10-21。师弟的电脑就是 Windows GPU 服务器。客户端纳入现有 fork 的 `shiyi-integration` 分支，路径为 `apps/shiyi-client`；原后端目录和 `main` 保持不变。

## 师弟在服务器本机运行（优先读这里）

请在服务器 Windows 的独立目录下载客户端，不要在正在运行的 `backend-dev`、`frontend-assist` 或 `integration` 中切分支、拉取或复制覆盖。以下示例下载到 `C:\ShiyiWorkspaces\client-integration`。命令在服务器的 Windows PowerShell 执行，不是在 WSL 或 Conda 环境中执行。

```powershell
git clone --filter=blob:none --sparse --single-branch --branch shiyi-integration https://github.com/legend-James/CyberVerse.git C:\ShiyiWorkspaces\client-integration
cd C:\ShiyiWorkspaces\client-integration
git sparse-checkout set apps/shiyi-client
cd apps/shiyi-client
```

先安装兼容的 Flutter SDK，并把 Flutter 的 bin 放入 PATH；当前开发版本为 Flutter 3.47.7 / Dart 3.13.5，项目最低 Dart 3.12。仅运行网页需要 Git、Flutter、Edge 或 Chrome，不需要为客户端再安装 Conda、CUDA、模型权重或第二套后端。构建 Android 才需要 Android SDK、JDK 17 及相应许可证。

双击客户端目录中的 `start-server-client.bat`，或执行以下命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-server-client.ps1
```

脚本只检查已有后端、获取客户端依赖并启动浏览器，不创建、重启或关闭任何后端、容器或 GPU 推理进程。默认网页端口为 7359，避免占用原来的 7358；端口占用可加 `-Port 7360`。需要自己操作标准命令时：

```powershell
flutter doctor
flutter pub get
flutter run -d edge --web-hostname=127.0.0.1 --web-port=7359
```

App 的“我的 → 设置”中，语音地址填 `http://127.0.0.1:18080`，照片视频地址填 `http://127.0.0.1:18082`。这是在服务器本机使用 localhost，不需要师弟 SSH 连接自己。服务器 Windows 到 WSL/Docker 的回环转发仍须可用，可先检查：

```powershell
curl.exe http://127.0.0.1:18080/api/v1/health
curl.exe http://127.0.0.1:18082/api/v1/health
Test-NetConnection 127.0.0.1 -Port 18443
Test-NetConnection 127.0.0.1 -Port 18445
```

API 健康且 inference_connected 为 true 才说明对应推理已连接；TURN TCP 检查只说明端口可达，不代替真实音视频验收。失败时检查已有服务与 Windows/WSL 转发，不要通过重跑完整部署、关闭防火墙或重启共享容器解决。网页运行终端需保持打开。麦克风权限应在打开网页的服务器浏览器中允许；远程桌面使用时还需确认音频设备重定向。

更新这个独立客户端副本时，先在仓库根目录运行 `git status --short`，确认没有未提交修改，再执行 `git pull --ff-only`。不要把这些命令应用到正在开发或提供服务的后端副本。

## 给师弟什么

- 只体验界面：发送最新版 `build/app/outputs/flutter-apk/app-release.apk`，约 100.5 MiB。当前尚未完成 Android 真机验收。
- 修改代码或联调：共享私有 GitHub 源码仓库，并邀请师弟的 GitHub 账号。没有 GitHub 时可先发送精简源码 ZIP。
- 不要直接压缩整个项目目录：工具链、依赖缓存、构建结果、旧安装包都不是源码。
- `deliverables` 中有旧包，不要把旧包误当成最新照片视频版本。

在项目根目录执行以下命令可重新生成精简源码包，输出在 `outputs`。脚本仅创建临时 Git 文件清单，不会初始化客户端仓库、提交或上传代码。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-source.ps1
```

`.gitignore` 已排除本地工具链、构建缓存、安装包、环境密钥、签名文件及运行资料，但忽略规则不等于完整的敏感信息审计。首次上传前仍应检查所有待提交文件。当前文档和部署脚本包含本机路径、私网地址、部署约定；建议先使用私有仓库。

## 另建私有客户端仓库（可选，不是本次方案）

当前使用现有公开 fork 的子目录，不需要执行本节。只有未来决定拆成独立私有仓库时才使用下面的步骤。

1. 登录自己的 GitHub，新建客户端仓库，例如 `shiyi-client`，选择 **Private**。不要勾选自动添加 README、许可证或 .gitignore，现有项目已有这些内容中的一部分。
2. 在仓库 Settings 的 Collaborators 中邀请师弟，等他接受。私有仓库不能只发网址让未授权的人下载。
3. 在客户端根目录的 PowerShell 执行以下命令。下面的地址是占位符，必须换成自己刚创建的仓库地址。

```powershell
cd E:\Python_Project\CyberVerseApp
git init -b main
git add .
git status --short
git diff --cached --stat
# 检查文件列表，确认没有密钥、私人素材、缓存和安装包后再继续。
git commit -m "Initial Shiyi client source"
git remote add origin https://github.com/YOUR_ACCOUNT/shiyi-client.git
git push -u origin main
```

首次 Git 登录按凭据管理器提示完成；不要把 GitHub Token、SSH 私钥或模型密钥发到聊天中。如果 Git 要求提交者身份，设置自己的 `user.name` 和 `user.email`，不要使用他人的身份。上面的初始化只适用于当前尚未初始化的目录，后续不要重复执行。

## 其他电脑独立运行（备用）

先安装 Git 和兼容的 Flutter SDK（当前开发环境 Flutter 3.47.7 / Dart 3.13.5，项目最低 Dart 3.12）。Windows 网页预览需要 Edge 或 Chrome；构建 Android 还需要 Android SDK、JDK 17 及相应许可证。无需为纯客户端界面安装 CUDA、后端 Conda 环境或下载模型权重。

```powershell
git clone https://github.com/YOUR_ACCOUNT/shiyi-client.git
cd shiyi-client
flutter --version
flutter doctor
flutter pub get
flutter run -d edge --web-port=7358
```

新电脑先使用上面的标准 Flutter 命令。现有 `.bat` 和 `scripts/env.ps1` 为原开发机的 `.toolchain` 环境准备，源码包不包含该工具链。浏览器预览保持终端运行，按终端给出的地址访问；如端口占用，换一个空闲端口。

需要在浏览器首次调试时生成 Android 平台配套工具的情况，由 Flutter 工具管理，不要复制原开发机的 `android/local.properties`。

## 真实语音、照片视频联调

源码或 APK 仅包含客户端，不包含可独立运行的推理服务器和模型密钥。真实通话还需要服务器服务在线。师弟在服务器本机使用时遵循开头步骤，不需要你的 SSH 私钥。

当前默认使用本机端口 18080（语音）和 18082（照片视频）。只有客户端运行在其他电脑上时，才需要那台电脑自己的 SSH 授权及隧道，或未来部署的安全测试入口。只建立 HTTP 转发不足以保证 WebRTC 媒体连接，TURN 转发也要按 `AVATAR_VIDEO.md` 配置。手机访问不能直接照搬电脑的 localhost。

模型 API Key 继续保存在服务器端，无需填写到客户端。照片视频目前限一个并发会话，联调前协调使用时间。

## 两个人如何避免互相影响

- 各自在自己电脑 clone，自己的修改先提交到各自的功能分支，通过 Pull Request 合入主分支。不要两个人编辑同一服务器目录。
- 本次客户端与后端在同一个 fork 中分目录管理。客户端在 `apps/shiyi-client`，原有 `frontend`、`server`、`inference` 不覆盖。Git push 不会自动更新服务器工作目录或重启任何服务。
- 后端沿用已有 `backend-dev`、`frontend-assist`、`integration` 分工：师弟开发后端，前端协助在独立副本修改，经过验证才更新联调服。
- Git push 只同步已提交的源文件，不同步环境密钥、运行数据、模型权重或正在运行的进程。
- APK 可单独通过微信发送，或作为仓库 Release 的附件；不要将安装包和构建目录提交到源码历史。
