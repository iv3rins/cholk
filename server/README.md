# Cholk account server

账号后端 + 受限 OpenAI 流式代理。零运行时依赖：只用 Node 内置的 `node:http`、
`node:sqlite`、`node:crypto`，没有 `dependencies`，不需要 `npm install`。

- 账号：注册 / 登录 / 登出，密码用 scrypt 加盐哈希，令牌只存 SHA-256 摘要。
- 代理：客户端持 Cholk 令牌访问，服务端换成固定的上游密钥。真实上游密钥永不下发到客户端。

## 环境要求

**Node.js 22.13 或更高**（`package.json` 的 `engines.node` 为 `>=22.13`）。

`node:sqlite` 在 Node 22 中是需要 `--experimental-sqlite` 的模块，从 **22.13.0** 起才默认可用。
低于该版本启动会直接失败；`npm start` / `npm test` 用 `--disable-warning=ExperimentalWarning`
静默该模块的 ExperimentalWarning，功能不受影响。

已验证版本：Node **v22.23.3**、npm 10.9.9（Windows）。测试与运行都不需要构建步骤。

## 快速开始

```bash
cd server
cp .env.example .env        # 然后填入真实的 OPENAI_API_KEY 等
# 项目没有 dotenv 依赖，shell 里加载环境变量：
#   bash:        set -a; . ./.env; set +a
#   PowerShell:  见下方“加载 .env”
npm start
```

PowerShell 加载 `.env`（跳过空行与 `#` 注释）：

```powershell
Get-Content .env | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' } | ForEach-Object {
  $name, $value = $_ -split '=', 2
  Set-Item -Path "env:$($name.Trim())" -Value $value.Trim()
}
npm start
```

默认监听 `http://127.0.0.1:3000`，把这个地址填到 Cholk 的「服务器与账号」。首次注册前需设置 `ALLOW_REGISTRATION=true`；如果 Web 客户端与服务不同源，将客户端页面的源加入 `CORS_ORIGINS`。启动日志会显示监听地址和注册开关状态。

## 环境变量

以下均按 `src/app.js` 的 `loadConfig()` 与 `src/index.js` 的实际行为。

| 变量 | 默认值 | 必填 | 说明 |
| --- | --- | --- | --- |
| `OPENAI_API_KEY` | 无 | **是** | 固定上游密钥。缺失时启动即抛 `OPENAI_API_KEY is required`。只存在服务端，不写日志、不回传客户端。 |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | 否 | 必须是以 `/v1` 结尾的 http(s) URL；**不允许**含用户名密码、查询串或 `#`，否则启动失败。实际请求路径为 `<base>/models`、`<base>/chat/completions`。 |
| `HOST` | `127.0.0.1` | 否 | 监听地址。对外暴露前请自行加 TLS 终止。 |
| `PORT` | `3000` | 否 | 监听端口，整数 0–65535；`0` 表示随机端口。 |
| `DATABASE_PATH` | `<server>/data/accounts.db` | 否 | SQLite 文件路径，`data/` 已 gitignore。`test` 用 `:memory:`。 |
| `ALLOW_REGISTRATION` | `false` | 否 | 只接受 `true` / `false` / 未设置，其他值启动即失败。`false` 时 `POST /auth/register` 返回 403。 |
| `CORS_ORIGINS` | 空 | 否 | 逗号分隔的**精确**浏览器源（如 `https://cholk.example`），必须是 `http(s)://host[:port]` 且与请求 `Origin` 全等。留空 = 完全不发 CORS 头，预检一律 403。 |
| `TOKEN_TTL_SECONDS` | `2592000`（30 天） | 否 | 会话有效期，正整数。登录时会顺带清理已过期会话。 |
| `AUTH_RATE_LIMIT` | `10` | 否 | 每个客户端 IP 在窗口内允许的 `/auth/register`、`/auth/login` 次数，两者独立计数。 |
| `AUTH_RATE_WINDOW_MS` | `60000` | 否 | 上述限流窗口，正整数毫秒。 |
| `UPSTREAM_TIMEOUT_MS` | `30000` | 否 | 等待对话上游响应头的超时。对话开始后持续转发；模型列表仍受超时限制。 |
| `MAX_BODY_BYTES` | `1048576`（1 MiB） | 否 | 请求体上限，超出返回 413。 |
| `SCRYPT_COST` | `16384` | 否 | scrypt 的 `N`。**仅测试会覆盖成 1024**；生产保持默认。改大后旧哈希仍可校验（cost 存在哈希串里）。 |

所有整数型变量只接受纯数字字符串，非法值或越界都会让启动直接失败，而不是静默降级。

## API 契约

除 `OPTIONS` 预检外，所有响应带 `Cache-Control: no-store`。错误统一为
`{"error":{"message":<code>,"type":...,"code":<code>}}`。

### `POST /auth/register`

请求体 `{"username": "...", "password": "..."}`，`Content-Type: application/json`。

- 成功：`200` → `{"username": "alice", "token": "<43 字符 base64url>"}`，注册后直接签发会话，响应体**只有**这两个字段。
- 用户名：1–64 字符，仅 `A-Za-z0-9_.@-`；密码 8–256 字符。
- 失败：`403 registration_disabled`（`ALLOW_REGISTRATION` 未开）、`400 invalid_credentials`、`409 username_taken`、`415 content_type_json_required`、`429 rate_limit_exceeded`。

### `POST /auth/login`

同一请求体格式。成功 `200` → `{"username": "alice", "token": "..."}`；用户名或密码错误统一返回 `401 invalid_credentials`（未知用户也做等代价哈希运算，减少用户名计时泄露）。其余失败码同上，但没有 409。

### `POST /auth/logout`

请求头 `Authorization: Bearer <token>`。成功 `204`，无响应体，且只吊销这一个令牌（同用户其他会话不受影响）。
无头/格式错/令牌已失效：`401 authentication_required`。令牌须为 43 个 base64url 字符。

### `GET /v1/models`

请求头 `Authorization: Bearer <Cholk token>`。校验通过后，服务端用**固定上游密钥**请求
`<OPENAI_BASE_URL>/models`，把上游响应体与状态原样转发（200）。

上游非 2xx、网络错误或超时：返回 `502 upstream_unavailable`，客户端 401 时不触达上游。

### `POST /v1/chat/completions`

请求头 `Authorization: Bearer <Cholk token>`，`Content-Type: application/json`。

- **必须** `"stream": true`，否则 `400 stream_true_required`。
- `model` 非空字符串（≤200），`messages` 必须是数组，否则 `400 invalid_chat_request`。
- 服务端**只**转发白名单字段：`model, messages, temperature, top_p, max_tokens, max_completion_tokens, stop, presence_penalty, frequency_penalty, logit_bias, logprobs, top_logprobs, n, seed, user, response_format, tools, tool_choice, parallel_tool_calls, reasoning_effort, service_tier, stream_options`，外加固定 `stream: true`。
  客户端塞进来的 `base_url`、`url`、`api_key` 之类一律丢弃——这类字段会被静默去掉而不是报错。
- 成功：`200`，`Content-Type: text/event-stream`，`Cache-Control: no-cache, no-transform`，`X-Accel-Buffering: no`。上游每个 SSE 分片一到就写回客户端，不做整段缓冲。
- 客户端断开或服务端关闭：服务端取消正在等待响应或正在转发的上游请求。
- 上游非 2xx / 网络错误 / 超时：`502 upstream_unavailable`。

### 其他

未知路径、带查询串的路径：`404 not_found`。非 `OPTIONS` 的 CORS 预检来源不匹配：`403 cors_origin_denied`。

## 测试

```bash
npm test     # node --test test/*.test.js
npm run check  # 语法检查
```

测试**完全离线**：每个用例在 `127.0.0.1:0` 起一个假的 HTTP 上游，用临时 `:memory:`
或系统临时目录的 SQLite，绝不访问真实上游、真实密钥或固定端口。覆盖：

- 注册/登录签发 `{username, token}`、错误密码 401、登出 204 且只吊销该令牌。
- 首个 SSE 事件实时到达，建立连接后的对话可以超过响应头超时。
- 客户端在上游响应头到达前或转发期间断开，服务端均会中止上游。
- 落盘库内无明文密码、无明文令牌（直接查 `users` / `sessions` 表）。
- 注册默认关闭、重复用户名 409、限流、CORS 白名单、令牌过期。

Windows 上 SQLite 会持有文件句柄，清理临时目录前先 `await app.close()`。
