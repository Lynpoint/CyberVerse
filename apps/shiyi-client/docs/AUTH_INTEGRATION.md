# 时忆 1.2 登录接入说明

当前交付的 APK / Web 默认使用本地演示服务，没有发送真实短信，没有读取微信资料。用户选择先补齐可体验流程，因此本版将演示实现和真实 HTTP 适配层分开。

## 当前可体验

- 手机号：+86、11 位号码校验 → 勾选协议 → 获取随机 6 位演示验证码 → 验证登录。验证码直接显示在页面，5 分钟有效，60 秒重发间隔，5 次错误后失效。重发会废弃上一次验证码，验证成功后不可重放。更换号码需重新获取。
- 微信：勾选协议 → 微信登录 → 时忆内部授权体验面板 → 确认体验或取消。面板明确不是微信官方授权页。授权票据 3 分钟有效、单次使用。
- 手机号、微信体验、本地密码账号数据分开保存，同一方式再次登录会恢复自己的联系人和消息。首次社交演示登录提供 3 位示例伙伴；正式远端身份不会自动注入示例伙伴。
- 不支持密码的手机号 / 微信账号不显示“修改密码”。“删除当前本地账号”仅删除本机资料，不等同于注销远端账号。

## 启用真实适配层

`lib/core/auth_gateway.dart` 定义 AuthGateway、DemoAuthGateway 和 HttpAuthGateway，`AppState` 负责消费认证后的身份。未配置地址时选择演示模式；配置地址后选择 HTTP 模式，接口失败不会回退到演示成功。

```powershell
. ./scripts/env.ps1
flutter build apk --release --target-platform android-arm64 --split-per-abi --dart-define=SHIYI_AUTH_BASE_URL=https://login.example.com
flutter build web --release --no-web-resources-cdn --dart-define=SHIYI_AUTH_BASE_URL=https://login.example.com
```

使用自己部署的 HTTPS 业务服务替换示例地址。只允许不含凭据、查询或片段的 HTTPS 基地址。设置页面的 CyberVerse 地址只用于数字人服务，和登录服务地址是两个独立配置。

## 拟定的业务服务契约

下面是本项目新增的拟定契约，不是 CyberVerse 上游现成接口；当前没有部署此服务。所有请求为 POST，JSON，15 秒超时；以下路径追加至配置的基地址。短信发送接口应在服务端实施冷却、每日限额和防滥用策略。

| 路径 | 请求 | 200 响应 |
| --- | --- | --- |
| /v1/auth/sms/send | phone, purpose=login | challenge_id, retry_after（秒） |
| /v1/auth/sms/verify | phone, code, challenge_id | user_id, nickname, access_token |
| /v1/auth/wechat/start | {} | challenge_id, authorization_url |
| /v1/auth/wechat/status | challenge_id | status=pending / approved / cancelled / expired；approved 同时包含 user_id, nickname, access_token |
| /v1/auth/wechat/cancel | challenge_id | {} |

400/401 显示验证失败，429 显示稍后重试，其他非 2xx 显示服务不可用。正式短信响应即使意外携带演示字段也不会在客户端展示验证码。

微信适配层采用“业务服务托管授权页 → 浏览器授权 → 回 App 检查状态”的流程：authorization_url 必须与业务服务同源、使用 HTTPS；该页面由服务端发起微信 OAuth 或展示官方扫码页。用户返回后点击“我已完成授权”，App 仅在服务器返回 approved 和有效身份字段时进入主页。

服务端必须生成不可预测且短期有效的 challenge_id，校验 OAuth state，按平台交换 code 并核对身份；状态查询票据不能使用公开递增 ID。用户取消授权应使票据失效，客户端只保留本次交互票据。AppSecret、短信密钥和微信 code 的服务端交换逻辑不得放入 Flutter。

## 仍需准备及联调

1. 微信开放平台审核、匹配产品形态的 AppID 与授权域名、服务端回调地址；短信签名、模板及供应商配置。
2. 部署上述业务服务并测试成功、拒绝、超时、重复点击、频率限制和取消场景；Web 服务需要设置正确的 CORS。
3. 若要求 Android 直接唤起微信客户端的一键原生授权，仍需接入微信 SDK、设置包名/正式签名/回调 Activity；本版浏览器托管方案不冒充原生 SDK 授权。
4. 本版 accessToken 仅保存在内存，退出即清除，不写入 SharedPreferences。正式版本仍需补上安全存储、刷新与失效处理、远端注销，以及数字人接口的鉴权和归属校验。现有用户名密码仍是本机 Demo，不能当作远端服务凭据。
5. 将隐私政策替换为包含真实运营主体和供应商的正式版本；完成安卓真机联调。

## 验证范围

自动化测试覆盖演示验证码生命周期、错误次数、重发废弃、授权取消/过期/重放、协议限制、账号恢复隔离、HTTP 请求契约与失败、令牌不落盘，以及 320px/390px 宽度下两条登录路径。MockClient 测试并不代表真实微信或短信联调完成。
