# 后端健康化方案（交付给后端工程师）

> 目标：**System prompt 更省 token、流式链路更稳、新手第一次就能聊起来。**
> 范围：只动下面列出的文件和行为。前端视觉已由前端负责，不在本方案内。
> 前置阅读：`docs/ENGINEERING_HANDOFF.md`（请求生命周期：ChatController → ChatGateway → providers → SSE → reply_merge）。

---

## 0. 写给执行者的工作守则（请先读完再动手）

你的工程能力没有问题。本项目最需要的是**少而准的代码**。以下规则优先于个人习惯：

1. **只在边界校验。** 边界是：服务端收到的 HTTP 请求体、客户端从磁盘/网络读到的 JSON、上游 SSE 字节流。
   项目内部的 Dart 类型、已经构造好的 `ChatSession` / `ChatRequest`，**直接信任**，不要再判空、再 `trim()`、再 `try/catch`。
2. **不吞异常。** 不允许 `catch (_) {}` 或 `catch { return null }`。需要捕获时，必须转换成现有的 `ApiException` / `ReplyError`（已有 `kind` 字段：`http | stream | network | interrupted | protocol | auth`），让 UI 能显示。
3. **不加只有一个实现的抽象。** 不新建 `XxxService` / `XxxManager` / `IXxx` 接口。函数够用就写函数。
4. **重试只有一个地方。** 本方案不新增任何自动重试。用户界面已有“重新生成”，那就是重试。
5. **每个任务有 diff 预算**（见各任务）。超出预算先停下来，在 PR 描述里写原因，而不是继续加。
6. **想加防御代码时，先写一个会失败的测试。** 写不出失败用例，就说明这个分支不需要。
7. 每个任务一个 PR。PR 描述只需三段：改了什么 / 怎么验证 / 刻意没做什么。

验证命令（每个 PR 都要跑）：

```bash
flutter analyze
flutter test
npm --prefix server test
npm --prefix proxy test
```

---

## 任务 1：修正工作模式中文提示词（Bug，最先做）

**位置**：`lib/state/chat_controller.dart` `_systemFor()`（约 1213 行），`session.mode == ChatMode.work` 分支。

**问题**：中文文本是 `'后续消息会沿用该人格流程；本步骤只作为提示发送，不在本地自动执行。'`，与英文的“围绕任务组织答案”完全不是一个意思。中文用户在工作模式下拿到的是一句与回答无关的话。

**改为**（与英文语义一致，且更短）：

```
围绕任务作答：先给结论或交付物，再列必要步骤、约束和待确认问题。简单问题简短回答，不虚构进度。
```

**验收**：新增 1 个单测，断言中文工作模式的 system prompt 包含 `先给结论`，不包含 `本地自动执行`。
**diff 预算**：≤ 15 行。
**不要做**：顺手重写其他提示词（那是任务 2）。

---

## 任务 2：System prompt 瘦身并做成“缓存友好”的固定顺序

### 背景

DeepSeek / OpenAI 兼容服务都有**前缀缓存**：请求开头逐字相同的部分会按缓存价计费，速度也更快。
所以原则只有一条：**越稳定的内容越靠前，越常变的内容越靠后；稳定部分逐字不变。**

当前 `_systemFor()` 的拼接顺序是：
`基础提示 → 参与者名字(仅英文) → 成员 profilePrompt → 人格 prompt + workflow → 聊天/工作模式句`

另外 `lib/api/providers/openai_provider.dart` 第 28–32 行会把日期提醒拼进 system 消息末尾：`Context: <日期 星期>`。

### 要做的事

1. **固定顺序**（写成注释放在 `_systemFor()` 顶部，就这一段注释）：
   ```
   1 基础提示（全局，几乎不变）
   2 人格 prompt + workflow（按会话不变）
   3 成员 profilePrompt + 名字句（群聊时，按成员不变）
   4 模式句（chat/work，切换时才变）
   ```
   日期提醒**不进 system**：OpenAI 路径改为把 `Context: …` 作为最后一条 user 消息之前的一条 `system` 消息，或直接拼到最后一条用户消息的开头（二选一，选改动更少的；DeepSeek 路径已用 `latest_reminder` 角色，保持不变）。
2. **名字句本地化**：现在中文会话也发英文的 `Your name in this conversation is …`。按 `zh` 输出中文：`你在本对话中的名字是 X。之前的公开回复会标注作者名。`
3. **去重**：如果 `profilePrompt` 与某个人格 `prompt(zh)` trim 后完全相同，只保留一份。只做“完全相同”判断，不做模糊匹配。
4. **长度护栏（只记录不截断）**：在调试记录 `ChatRequestDebug` 中增加 `systemChars` 字段（`prompt.length`），请求调试面板已经会展示调试记录，前端负责展示位置。**不要**自动截断用户写的 prompt。

### 验收

- 单测：同一会话连续两次 `_systemFor()` 结果**逐字相同**（防止有人往里塞时间戳、随机数）。
- 单测：跨天时（注入时间）system 内容不变，只有提醒消息变化。
- 单测：profile 与人格相同 → prompt 中只出现一次。
- 用请求调试面板对比前后：默认人格、单聊时 system 字符数应 ≤ 改前。

**diff 预算**：≤ 120 行（含测试）。
**不要做**：引入模板引擎、YAML 提示词文件、提示词版本管理。提示词就是常量字符串。

---

## 任务 3：历史上下文 token 预算（最大的省钱点）

**位置**：`lib/chat/context_builder.dart` `toRequestMessages()`。当前把所有可用历史轮次全部发出，没有任何上限。长对话每轮的输入 token 线性增长。

### 方案：滑动窗口，按“轮”裁剪，不做摘要

1. 新增一个纯函数（同文件内）：
   ```dart
   /// 粗估：CJK 字符按 1 token，其余按 4 字符 1 token。只用于裁剪，不用于计费。
   int estimateTokens(String text)
   ```
2. `toRequestMessages` 增加参数 `int budgetTokens = 24000`。
   从**最新一轮往回**累加，超出预算就停；**最早被保留的那一轮之前全部丢弃**。当前问题、`prefix`（续写）永远保留，不计入裁剪判断。
3. 附件：文件块按其 token 估算（若无文本则按固定 1000 计），不读取文件内容来估算。
4. 预算值放在 `ModelConfiguration` 旁边作为常量即可，**先不做设置项**（新手不需要理解这个旋钮）。

### 为什么不做摘要

摘要需要额外一次模型调用（花钱、增加延迟、引入新的失败点），而且摘要质量问题会变成“AI 忘了我说过什么”的投诉。窗口裁剪行为可预期，先上窗口；有数据证明需要再谈摘要。

### 验收

- 单测：100 轮长对话 → 输出消息估算 token ≤ 预算；最后一轮完整保留；顺序不变。
- 单测：一轮就超预算 → 仍然发送当前问题（不能发空请求）。
- 单测：未超预算的短对话 → 输出与改前**完全一致**（回归保护）。

**diff 预算**：≤ 150 行（含测试）。
**不要做**：引入 tokenizer 依赖包；为估算误差加“安全系数”层层叠加（一个预算值就够了）。

---

## 任务 4：会话标题——已达标，只补一个测试

**现状（已核实）**：DeepSeek 协议在同一请求里带 `title: {enabled: true}`（`deepseek_provider.dart:133`）；服务端没给标题时，`ChatController._fallbackTitle()`（约 1471 行）用首条用户消息的前 30 字作标题。**没有额外的标题请求，这已经是最省的方案。**

**要做**：确认 `_fallbackTitle` 有单测覆盖“多行首条消息 → 单行、≤ 30 字 + `…`”；没有就补一个。
**diff 预算**：≤ 30 行（只有测试）。
**不要做**：为标题新增模型请求；改动 30 这个长度。

---

## 任务 5：流式链路加固（服务端 `server/src/app.js`）

现状已经做对的：`X-Accel-Buffering: no`、`Cache-Control: no-transform`、`flushHeaders()`、客户端断开时 `controller.abort()` 传给上游、收到响应头后清除超时。**这些保持不动。**

### 5.1 SSE 心跳（必须做）

推理模型可能长时间不吐字（思考阶段），中间的反向代理/移动网络会把“无数据”的连接当死连接断掉。

在 `proxyUpstream` 的 streaming 分支：pipe 期间若 **15 秒**没有向 `res` 写过任何字节，就写一行 SSE 注释 `: ping\n\n`。

- 实现方式：用一个 `Transform` 包在 pipeline 中间，记录最后写入时间和**最后两个字节**，再加一个 `setInterval`；`finally` 中 `clearInterval`。
- **唯一需要的正确性条件**：只在事件边界插入，即上次写出的内容以 `\n\n` 结尾（或尚未写过任何字节）时才写 ping。上游若停在半行中间，插入会把那一行切坏。这是本任务中唯一值得写的判断，不需要其他防护。
- **客户端已兼容（已核实）**：`lib/api/sse.dart` 第 36 行已忽略以 `:` 开头的注释行。只补一个 Dart 单测，喂入 `": ping\n\n"` 并断言不产生事件。**不要改 sse.dart。**

### 5.2 首字节超时与总时长分离

当前 `upstreamTimeoutMs`（默认 30s）只覆盖“拿到响应头之前”。保持这个语义，**改名注释**说明它是“首字节超时”。不要新增“总时长超时”——长回答本来就可能超过几分钟，用户有停止按钮。

### 5.3 不要压缩 SSE

确认没有任何压缩中间件作用于 `text/event-stream`（目前没有）。在 PR 里写一句确认即可，不需要加代码。

### 验收

- `server/test/app.test.js` 新增：上游 20 秒不出数据（用假上游 + 假时钟，或把间隔做成可注入参数）→ 客户端收到至少一次 `: ping`。
- 新增：上游写出半行 `data: {"a"` 后停顿超过间隔 → **不得**插入 ping。
- 新增：客户端中途断开 → 上游请求被 abort（已有类似测试就扩展它）。

**diff 预算**：服务端 ≤ 60 行，测试 ≤ 80 行。
**不要做**：服务端重试上游、服务端缓存回复、服务端解析 SSE 内容。服务端只是一根管子。

### 客户端侧（只确认，不改）

- `ChatController` 的通知节流 60ms、草稿保存 400ms 防抖：**保持**。这是流畅度与 CPU 的平衡点，前端动画依赖它。
- 取消：`CancelToken` 已贯穿到 provider，确认“停止”按钮 → 服务端日志能看到连接关闭即可。

---

## 任务 6：对“一窍不通的新手”友好

新手的三个卡点：**不知道去哪连接、不知道为什么失败、失败后不知道该点什么。**

### 6.1 错误文案表（纯文案，不改流程）

`ReplyError.kind` 已经分类得很好。新增一个函数 `String plainReplyError(ReplyError e, bool zh)`，放在 `lib/i18n/strings.dart` 附近，按下表返回：

| kind / status | 中文 | 英文 |
|---|---|---|
| `auth` 或 401/403 | 登录已失效或密钥不对。去「设置 → 账号」重新登录即可。 | Your sign-in expired or the key is wrong. Sign in again in Settings → Account. |
| `network` | 网络没连上。检查网络后点「重新生成」。 | Can't reach the network. Check your connection, then tap Regenerate. |
| `interrupted` | 回复被中断了，已保留写好的部分。点「继续」或「重新生成」。 | The reply was interrupted; what was written is kept. Tap Continue or Regenerate. |
| 429 | 请求太频繁，稍等几秒再试。 | Too many requests. Wait a few seconds and try again. |
| 5xx / `upstream_unavailable` | 模型服务暂时不可用，不是你的问题。稍后再试。 | The model service is temporarily unavailable — not your fault. Try again shortly. |
| 其他 | 出了点问题。点「重新生成」再试一次。 | Something went wrong. Tap Regenerate to try again. |

原始错误 `message` 继续保留在请求调试面板里，**不要**展示给普通模式用户。前端会把这个函数接到 `assistant_message.dart` 的错误行上（你只需提供函数 + 单测）。

### 6.2 普通模式“零配置”

- 普通模式下，若构建时提供了默认账号服务地址（`--dart-define=ACCOUNT_ORIGIN=…`），设置页的服务地址输入框直接预填并折叠到“高级”，用户只看到“登录/注册”。
- 没提供时保持现状。

**diff 预算**：6.1 ≤ 80 行（含测试）；6.2 ≤ 60 行。
**不要做**：游客账号、匿名额度、引导教程弹窗——这些是产品决策，需要单独评审。

---

## 交付顺序与预估

| 顺序 | 任务 | 风险 | 预计 |
|---|---|---|---|
| 1 | 任务 1 中文工作模式 Bug | 极低 | 0.5h |
| 2 | 任务 3 上下文预算 | 中（影响回答质量） | 0.5d |
| 3 | 任务 2 Prompt 顺序/瘦身 | 低 | 0.5d |
| 4 | 任务 5 SSE 心跳 | 低 | 0.5d |
| 5 | 任务 6.1 错误文案 | 极低 | 2h |
| 6 | 任务 4 标题（仅补测试） | 极低 | 0.5h |
| 7 | 任务 6.2 零配置 | 低 | 2h |

## 明确不在本方案内（看到也不要顺手做）

- 切换 SSE 为 WebSocket。
- 引入状态管理框架（Riverpod/Bloc 等）重构 `ChatController`。
- 给每个 provider 加统一基类。
- 服务端引入 ORM、迁移框架或队列。
- 对已有通过的测试“加强断言”而不对应任何行为变化。

有疑问时的判断标准：**这行代码删掉后，有没有一个真实用户会遇到问题？** 没有，就不写。
