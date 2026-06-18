# www.cyberverse.cc 域名部署

## 适用范围

本文档用于把 CyberVerse 前端以**静态文件**方式部署到 `www.cyberverse.cc`，并通过 Nginx 将 `/api/` 和 `/ws/` 反向代理到本机后端 `127.0.0.1:8080`。

访问 `https://www.cyberverse.cc/` 时，前端路由默认重定向到 `/kanshan` 页面。

**说明**：本文档**不是** `make frontend`（Vite 开发服 `:5173`）的部署方式；对外域名应使用 `make frontend-build` 后的 `frontend/dist`，由 Nginx 提供静态文件。

## 构建前端

在服务器仓库根目录执行：

```bash
make frontend-build
```

该目标默认使用：

```bash
VITE_WS_BASE=wss://www.cyberverse.cc
```

如需临时覆盖域名：

```bash
make frontend-build FRONTEND_DOMAIN=example.com
```

## 发布静态文件（推荐路径）

示例配置使用 **`/var/www/cyberverse-cc`** 作为站点根目录，避免把 `root` 指到 `/root/...` 导致 **www-data 无法读文件**（权限问题）。

```bash
sudo mkdir -p /var/www/cyberverse-cc
sudo rsync -a --delete frontend/dist/ /var/www/cyberverse-cc/
```

之后每次重新构建，再执行一次 `rsync` 即可更新线上前端。

## 安装 Nginx 站点配置

```bash
sudo cp infra/nginx.www.cyberverse.cc.conf /etc/nginx/sites-available/www.cyberverse.cc
sudo ln -sf /etc/nginx/sites-available/www.cyberverse.cc /etc/nginx/sites-enabled/www.cyberverse.cc
sudo nginx -t
sudo systemctl reload nginx
```

如果服务器使用 `/etc/nginx/conf.d/`，改用：

```bash
sudo cp infra/nginx.www.cyberverse.cc.conf /etc/nginx/conf.d/www.cyberverse.cc.conf
sudo nginx -t
sudo systemctl reload nginx
```

### HTTPS 与证书路径

仓库中的 [`infra/nginx.www.cyberverse.cc.conf`](../../../infra/nginx.www.cyberverse.cc.conf) 包含：

- **`listen 80`**：HTTP
- **`listen 443 ssl http2`**：HTTPS，默认证书路径为 Let’s Encrypt：

  `/etc/letsencrypt/live/www.cyberverse.cc/fullchain.pem`
  `/etc/letsencrypt/live/www.cyberverse.cc/privkey.pem`

若你使用**阿里云上传的证书**，请编辑站点文件，把上述两行改为你的 `.pem` / `.key` 实际路径，再 `nginx -t` 与 `reload`。

**常见误区**：若配置里**只有 `listen 80` 没有 `listen 443`**，浏览器访问 `https://www.cyberverse.cc` 时，请求会落到 Nginx 的**默认 SSL 虚拟主机**，页面即为 **「Welcome to nginx!」**——这不是反代失败，而是 **443 上没有为你的域名配置站点**。

## HTTPS（Let’s Encrypt）

生产环境应启用 HTTPS。推荐顺序：

1. 若尚未申请 Let’s Encrypt 证书，`nginx -t` 会因找不到 `ssl_certificate` 路径而失败。请先从已安装到系统的站点文件中**删除**第二个 `server` 块（仅含 `listen 443 ssl` 的那段），只保留 `listen 80`，确保 `nginx -t` 与 `reload` 成功。
2. 使用 Certbot 申请证书（示例）：

```bash
sudo certbot certonly --webroot -w /var/www/cyberverse-cc -d www.cyberverse.cc -d cyberverse.cc
```

或使用交互方式让 Certbot 改 Nginx（需已存在可访问的 HTTP 站点）：

```bash
sudo certbot --nginx -d www.cyberverse.cc -d cyberverse.cc
```

3. 证书就绪后，将**完整**的 [`infra/nginx.www.cyberverse.cc.conf`](../../../infra/nginx.www.cyberverse.cc.conf) 再次 `cp` 到站点路径（或手动补上 `listen 443` 段），确认 `ssl_certificate` 路径与实际一致，再执行：

```bash
sudo nginx -t && sudo systemctl reload nginx
```

若暂时只为 `www` 签证书，请只用 `https://www.cyberverse.cc` 访问；根域名 `cyberverse.cc` 需单独加入证书 SAN 或再签一张。

HTTPS 生效后，前端会通过 `wss://www.cyberverse.cc/ws/...` 连接 WebSocket。

## 验证

```bash
curl -I http://www.cyberverse.cc/
curl -I https://www.cyberverse.cc/
curl http://www.cyberverse.cc/api/v1/health
```

浏览器访问：

```text
https://www.cyberverse.cc/
```

## 故障排查

### 1. `https://` 打开是「Welcome to nginx!」

- **原因**：443 未使用本仓库的 `server_name` 与 `root` / 反代配置（常为旧配置只有 80）。
- **处理**：确认已部署包含 **`listen 443 ssl`** 的站点配置；执行 `sudo nginx -T 2>/dev/null | grep -E 'server_name|ssl_certificate|listen'` 检查实际加载的配置。

### 2. 403 Forbidden 或空白页

- **原因**：`root` 指向的目录 **www-data 不可读**（例如仍在使用 `/root/CyberVerse/frontend/dist` 且未放宽权限）。
- **处理**：采用本文「发布静态文件」中的 **`/var/www/cyberverse-cc`** + `rsync`。

### 3. 改了配置不生效

- 执行 `sudo nginx -t` 确认无语法错误后 **`sudo systemctl reload nginx`**。
- 确认没有**另一份** `default` / 其他站点在 `listen 443 default_server` 抢占了你的域名（可用 `nginx -T` 排查）。

### 4. 与 `make frontend` 的区别

- `make frontend`：本机开发，默认只监听 `localhost:5173`，**不是**本文档的 Nginx 静态部署。
- 域名对外访问：请使用 **`make frontend-build` + Nginx**（或自行反代到 dev，不推荐生产）。

### 5. 语音 / Direct WebRTC 一直 `connection state: failed`

直连模式（`streaming_mode: direct`）下，浏览器依赖 **TURN over TCP**（默认端口见 `cyberverse_config.yaml` 的 `turn_port`，常见为 **8443**）穿透 NAT。

- 在 **`cyberverse_config.yaml`** 中设置 **`ice_public_ip`** 为外网可访问的 **`https` 站点域名**（如 `www.cyberverse.cc`）或公网 IP。**不要留空**：留空时服务端会把 TURN 配成 `127.0.0.1`，外网浏览器永远连不上。
- 在 **轻量应用服务器防火墙 / 安全组** 放行 **TCP `turn_port`**（例如 **8443**）入站。
- 修改后需 **重启 `cyberverse-server`**（例如重新执行 `make server`）。
