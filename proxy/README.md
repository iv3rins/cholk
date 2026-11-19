# deepseek-proxy

这是一个很薄的数据转发代理，用来把 Web 端和 Flutter 客户端的请求转发给 DeepSeek API。它不实现聊天逻辑，不保存会话，也不做账号体系。它只做三件事：校验客户端令牌、把服务端保存的 DeepSeek API Key 放进上游请求、把上游响应原样流式转发回来。

代理只放行 DeepSeek 兼容接口，包括 `/models`、`/anthropic/v1/*` 和 `/v1/tools/*`。它不是一个通用的开放代理，所以即使地址泄露，也不能用来访问任意上游服务。

## 快速开始

需要 Node.js 20.6 或更高版本（推荐 Node 22）。项目没有第三方依赖，不需要执行 `npm install`。

```bash
cp .env.example .env
# 编辑 .env，填入 DEEPSEEK_API_KEY 和一个足够长的 PROXY_TOKEN
node --env-file=.env src/index.mjs
```

也可以直接使用环境变量启动：

```bash
DEEPSEEK_API_KEY=sk-xxx PROXY_TOKEN=long-random-token node src/index.mjs
```

服务默认在所有网络接口监听 8787 端口。本机可通过 `http://127.0.0.1:8787` 访问。健康检查地址 `/healthz` 无需鉴权。

## 客户端如何接入

Flutter 客户端不需要改代码。在设置里把「API 地址」改成代理地址，例如 `http://127.0.0.1:8787` 或 `https://chat.example.com`，然后在「API Key」里填写 `PROXY_TOKEN`。客户端发出的 `x-api-key` 或 `Authorization: Bearer` 会被代理当作客户端令牌校验，随后被服务端真实 Key 替换，不会继续传给上游。

Flutter Web 的本地模拟联调见[开发与验证手册](../docs/DEVELOPMENT.md)。

如果 Web 静态文件和代理放在同一个域名下，浏览器请求就是同源的，不需要处理 CORS。代理也支持跨域部署，通过 `ALLOWED_ORIGINS` 配置允许的来源，开发阶段可以用 `*`。

## 转发范围

代理只接受下面这些路径。其他路径一律返回 404。

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/models` | 校验 Key 或列出模型 |
| POST | `/anthropic/v1/messages` | 流式对话，SSE 原样转发 |
| POST | `/anthropic/v1/files` | 上传附件 |
| DELETE | `/anthropic/v1/files/{id}` | 删除附件 |
| POST | `/v1/tools/asr` | 语音识别 |
| POST | `/v1/tools/tts` | 语音合成 |

请求和响应都按字节转发，不改写 JSON。对于 `text/event-stream`，代理会设置 `Cache-Control: no-cache, no-transform` 和 `X-Accel-Buffering: no`，并在收到每个数据块时立即写出，不会等完整回答生成完才返回。请求侧强制使用 `Accept-Encoding: identity`，避免 SSE 被压缩后产生额外缓冲。

## 配置

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `PORT` | `8787` | 监听端口 |
| `DEEPSEEK_API_KEY` | 无，必填 | 真实 DeepSeek API Key，只保存在服务端 |
| `PROXY_TOKEN` | 空 | 客户端令牌。为空时代理不鉴权，只适合本机开发 |
| `DEEPSEEK_API_ORIGIN` | `https://api.deepseek.com` | 上游地址，可指向兼容网关 |
| `MAX_BODY_MB` | `80` | 请求体上限，需要覆盖 64 MiB 附件和 multipart 开销 |
| `ALLOWED_ORIGINS` | `*` | 允许的 Web 来源，以逗号分隔。空值与 `*` 都允许任意来源 |

## 部署

最简单的做法是用 Docker 构建一个单文件镜像：

```bash
docker build -t deepseek-proxy .
docker run --rm -p 8787:8787 --env-file .env deepseek-proxy
```

也可以使用项目里的 `docker-compose.yml`：

```bash
docker compose up -d --build
```

不要把 8787 直接暴露到公网。建议用 Caddy、Nginx 或云负载均衡在前面终止 TLS，并把代理放在内网。Caddy 同源托管的配置大致如下：

```caddyfile
chat.example.com {
    handle /anthropic/* {
        reverse_proxy 127.0.0.1:8787 {
            flush_interval -1
        }
    }
    handle /v1/tools/* {
        reverse_proxy 127.0.0.1:8787 {
            flush_interval -1
        }
    }
    handle /models {
        reverse_proxy 127.0.0.1:8787
    }
    handle /healthz {
        reverse_proxy 127.0.0.1:8787
    }
    handle {
        root * /srv/deepseek-web
        try_files {path} /index.html
        file_server
    }
}
```

`flush_interval -1` 用来关闭 Caddy 的响应缓冲，SSE 才能逐块到达浏览器。使用 Nginx 时对应的是 `proxy_buffering off`、较长的 `proxy_read_timeout` 和足够大的 `client_max_body_size`。

## 安全边界

代理只将服务端 Key 写入发往上游的 `x-api-key` 和 `Authorization` 请求头。客户端使用 `PROXY_TOKEN`，代理用定时安全比较校验令牌。

这仍然只是一个单令牌代理，不区分用户，也没有配额、审计和账号体系。如果准备公开给多人使用，至少要在前面加一层限流和访问控制，或者把 `PROXY_TOKEN` 换成真正的用户鉴权。代理默认不记录请求体和响应体，只输出方法、路径、状态码和耗时，避免把对话内容写进日志。

## 已知限制

请求体在通过大小检查后才转发。代理在内存中读取请求体，默认上限 80 MiB，超限返回 413。上游连接空闲超过 5 分钟时中止。

## 本地 mock 上游

`dev/mock-upstream.mjs` 是一个只用于界面预览的假上游。它实现了 `/models`、`/anthropic/v1/messages`、上传和语音接口，消息接口会按真实协议逐步发送 thinking、搜索、文本和引用事件。启动方式是 `node dev/mock-upstream.mjs`，默认监听 8788。把代理的 `DEEPSEEK_API_ORIGIN` 指向它，再配合 Flutter Web 的 `DEMO_UI` 构建，就可以在没有真实 API Key 的情况下查看流式交互。这个文件不会被生产镜像复制。

## 测试

```bash
npm test
```

测试使用 Node 内置的 `node:test` 和本地 mock 上游，覆盖鉴权、Key 替换、流式转发与取消、压缩响应、CORS、路径白名单、请求体上限和 multipart 上传。
