# 使用 GPT-6.2（Using GPT-6.2）

> 原文：[Using GPT-6.2 | OpenAI API](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6.2-astra)
>
> 翻译日期：2026-11-19（Asia/Shanghai）
>
> 提示词示例已译为简体中文。API 字段、参数值和模型标识符沿用原文。

完整文档索引见 [llms.txt](https://developers.openai.com/llms.txt)。在文档页面的网址末尾加上 `.md`，即可获取 Markdown 版本。

<a id="gpt-6.2-astra-gpt-62-astra-and-gpt-62-sol"></a>

对于要求最高的任务，请选用 GPT-6.2 Astra。如果需要以较低成本完成复杂工作，请选用 GPT-6.2 Sol。[GPT-6.2 Astra](https://developers.openai.com/api/docs/models/gpt-6.2-astra) · [GPT-6.2 Sol](https://developers.openai.com/api/docs/models/gpt-6.2-sol)

<a id="whats-new"></a>

## 新变化

- **编辑对话前缀。** 从 GPT-6.2 开始，如果你在对话过程中编辑已有的对话历史（即编辑前缀）、做出某些模型变更（包括降级），或更换最终用户或组织，Responses API 会丢弃推理项。模型失去对这些推理项的访问后，回答质量可能下降，也可能消耗更多 token 来重复先前的工作。请检查你的集成，找出修改旧的 `developer` 消息或工具调用之类的操作。若要保留推理项，让先前的输入继续符合提示词缓存条件，请在两次响应之间调整设置时保持前缀不变。[提示词缓存](https://developers.openai.com/api/docs/guides/prompt-caching) · [保持前缀不变](https://developers.openai.com/api/docs/guides/keep-prefix-unchanged)
- **Responses API 的 `instructions` 字段变更。** 从 GPT-6.2 开始，模型会把 Responses API 的顶层 `instructions` 追加到 `input` 之后。若要让可复用的指令符合提示词缓存条件，请将其写入一条 `developer` 消息，作为 `input` 的第一项。仅适用于当前请求的开发者指令可放在顶层 `instructions` 中。[前缀匹配机制](https://developers.openai.com/api/docs/guides/prompt-caching#how-prefix-matching-works)
- **后台模式（公开测试版）。** 对于长时间运行的 Responses API 请求，可以用后台模式的折扣完成窗口替代 Flex 处理。后台模式支持通过 Standard 处理在 2 小时或 8 小时的窗口内完成请求。GPT-6.2 Astra 和 Sol 均不支持 Flex 处理（`service_tier: flex`）。[使用折扣完成窗口](https://developers.openai.com/api/docs/guides/background#use-discounted-completion-windows)

<a id="prompting-best-practices"></a>

## 提示词最佳实践

下面的提示词可作为使用 GPT-6.2 系列模型的起点。示例针对 OpenAI 在使用 GPT-6.2 Astra 和 Sol 时观察到的行为。如果你在自己的应用中遇到了其中一种行为，可以试试对应小节的提示词。

<a id="gpt-62-astra-behavior"></a>

### GPT-6.2 Astra 的行为特点

- **[写作风格](#writing-style)**。模型默认倾向于写得更简洁、直接。迁移时，可以重新审视系统提示词中「请简洁」之类的指令。
- **[完成任务](#task-completion)**。用户意图不明确时，模型可能会提出下一步建议并等待确认。对于耗时较长的任务，可以允许模型作出合理假设并继续推进。
- **[编码风格](#coding-style)**。相比早期模型，它通常能写出效率更高、质量更好的代码。请说明编写或修改代码时应遵循哪些项目约定。
- **[前端设计](#frontend-design)**。如果界面需要特定的视觉风格，请指定应使用的图像和排版。

<a id="gpt-6.2-astra-prompt-patterns-for-api-applications"></a>
<a id="gpt-6.2-astra-personality-and-writing-style"></a>
<a id="writing-style"></a>

### 写作风格

相比早期模型，GPT-6.2 Astra 默认写得更简洁、直接。你可以根据应用调整语气，比如让它像专业的同事，或让它用更接近日常对话的口吻交流。

如果你希望模型与用户协作、一起思考日常工作中的问题，可以使用以下提示词。

```text
采用用户和参考资料使用的术语。保留技术细节，并在领域术语能让解释更准确时使用它们。使用主动语态，把紧密相关的细节放在一起。先交代要点，避免提及读者读到后文才能理解的内容。提供足够的背景，让用户能跟上你的推理。
```

让模型根据目标读者调整表达，适用于起草文档、电子邮件、消息和对外发布的内容。

```text
代表用户起草将发给外部受众的消息或其他材料时，先想清楚谁会阅读，再根据目标受众调整内容。目标受众可能掌握的背景与用户不同。请补充他们理解内容所需的背景信息或推理过程。

审阅或编辑已有内容时，保留作者的内容和措辞，并严格按照用户的要求修改。
```

在较长的任务中，模型有时会把推理过程或其他智能体使用的简写带进最终答复。可以提醒模型写一份独立、清楚的答复，让没看过进度更新的人也能读懂。

```text
把最终答复当作用户第一次看到你的工作成果。最终答复必须可以独立阅读。界面显示最终答复时，先前的进度更新会折叠，因此用户应当无需翻看这些更新就能理解答复。

面向目标读者重新撰写最终答复及其他供人阅读的材料。避免照抄或近似改写推理内容，也避免沿用推理过程中的写作风格。推理、工具调用以及给子智能体或自动化任务的指令中所用的临时简称、行话和缩写，都应改用读者能理解的说法。
```

<a id="gpt-6.2-astra-initiative-and-follow-through"></a>
<a id="gpt-6.2-astra-subagent-delegation"></a>
<a id="task-completion"></a>

### 完成任务

对于可以无人监督地开展的工作，请明确模型要交付什么结果，以及哪些决定需要用户参与。

```text
只要任务尚未完成或还有已获授权的下一步，就继续推进。请在任务范围内采取下一步行动，落实用户的请求。如果你准备在最终答复中建议下一步、给出计划、请用户作常规决定、给用户布置操作步骤，或以类似方式把后续工作交还给用户，就在获得授权的前提下自己执行这些步骤，并告知用户你作出的假设或决定。

只在任务范围发生重大变化、遇到确实无法继续的阻碍、需要用户作决定，或即将执行不可逆或破坏性操作时，才停下来向用户确认。
```

<a id="gpt-6.2-astra-testing-and-verification"></a>
<a id="gpt-6.2-astra-ask-for-an-exhaustive-pass"></a>

要求模型核实所请求的工作已经完成。对于复杂或长时间运行的任务，提高推理强度有助于模型坚持完成最后的检查。在 Responses API 中，通过 `reasoning.effort` 设置推理强度。[推理强度](https://developers.openai.com/api/docs/guides/reasoning#reasoning-effort)

```text
主动采取行动，并坚持到完成用户要求的任务为止。只要任务尚未完成或还有已获授权的下一步，就在任务范围内继续推进。逐项落实用户的请求，直到交付充分满足用户目标的结果。

如果任务需要持续投入，就做完所有必要的工作，直到完全达成预期结果。

自主推进用户的目标，例如在需要时建立隔离的工作树或检出副本、解决合并冲突、创建草稿拉取请求（PR）。遇到明显会造成破坏或无法撤销的操作时应暂停。结束当前回合或宣布完成之前，检查成果是否充分满足用户的要求。如有步骤尚未执行或结果尚未验证，请完成这些工作后再结束。
```

<a id="gpt-6.2-astra-instruction-following"></a>
<a id="gpt-6.2-astra-intent-understanding"></a>
<a id="gpt-6.2-astra-interpreting-ambiguous-requests"></a>

当某个细节不明确时，可以允许模型说明自己的假设并继续执行任务。

```text
只要有助于在任务范围内推进，就作出合理、可撤销的假设，并告诉用户你的假设。避免反复怀疑自己的判断。在仍可推进的情况下，直接继续执行，避免只描述自己可以做什么、询问是否需要代做，或只给出部分答案。
```

如果在应用中提供 `request_user_input_async` 之类的异步工具，GPT-6.2 就可以一边请用户澄清，一边继续处理无需等待答复的工作。[添加异步提问工具](https://developers.openai.com/api/docs/guides/async-tool-calling#add-a-tool-to-ask-the-user-for-input)

<a id="gpt-6.2-astra-code-changes"></a>
<a id="coding-style"></a>

### 编码风格

说明代码库的约定，以及现有调用方依赖的行为。例如，可以规定何时复用现有逻辑、如何限制改动范围，以及何时需要为现有测试未覆盖的行为补充测试。

```text
首要目标是认真写出高质量、正确的代码，完整落实用户的任务。保持代码易读，并验证功能是否按用户预期运行。编写代码时遵循以下要求。

(a) 在保证正确性的前提下，尽量复用用户仓库已有的逻辑，包括类、方法、数据表示和 API。合并或删除代码之前，先确保现有调用方依赖的行为得以保留，除非任务明确要求改变这些行为。
(b) 在用户要求、仓库规定，或需要捕捉现有测试会漏掉的特定回归时，才新增测试。
(c) 保持代码便于人阅读。简明的代码需要清晰的结构，避免为了压缩代码而缩减行数、缩短变量名、使用压缩格式或把多个操作塞进一行。确保注释和变量名容易看懂。为了缩短代码而写的表达式，如果把许多分支、条件或隐含假设挤在一起，就过于复杂。
(d) 避免不必要的间接层和抽象。即使没有增加分支，辅助函数、工具函数和类抽象也可能增加理解代码的成本。
```

<a id="gpt-6.2-astra-visual-review"></a>
<a id="gpt-6.2-astra-visual-work-and-frontend-design"></a>
<a id="frontend-design"></a>

### 前端设计

如果应用依赖特定的视觉风格，请在提示词中加以描述。指定应使用的图像类型和排版方式，必要时指定字体。界面文案应聚焦于用户需要知道的信息或需要采取的行动。

```text
生成网页或带前端界面的应用时，遵循以下要求。

- 选择视觉素材时，通常优先采用 ImageGen 生成或通过图片搜索找到的写实图像，并确保它们符合项目的风格和用途。用户明确要求时，使用 SVG。
- 只有当某段文字提供用户需要的信息、帮助用户导航或操作，或满足明确的内容要求时，才将它放进界面。删除装饰性编号、占位徽章、重复标题，以及只是在复述界面已传达信息的说明文字。保留必要的标签、操作说明和状态反馈。
```

处理视觉任务时，可以分享设计软件中的参考稿，也可以让 GPT-6.2 使用图像生成工具，调用 GPT Image 创建参考图。参考图能补足难以用文字说明的细节。等参考图呈现出想要的效果后，请模型制作素材、渲染结果，并对照参考图继续调整。[图像生成工具](https://developers.openai.com/api/docs/guides/tools-image-generation)

<a id="migration-quickstart"></a>

## 迁移快速入门

<a id="gpt-6.2-astra-migrate-with-codex"></a>

如果你要用编码智能体将 API 应用迁移到 GPT-6.2 Astra，可以使用 OpenAI Docs 技能。[OpenAI Docs 技能](https://github.com/openai/codex/tree/main/codex-rs/skills/src/assets/samples/openai-docs)

<a id="gpt-6.2-astra-choose-a-reasoning-effort"></a>
<a id="gpt-6.2-astra-zdr-data-residency-and-service-tiers"></a>
<a id="gpt-6.2-astra-limitations"></a>
<a id="gpt-6.2-astra-data-residency-and-service-tiers"></a>
<a id="update-api-and-model-parameters"></a>

### 更新 API 和模型参数

将 `model` 设为 `gpt-6.2-astra` 或 `gpt-6.2-sol`，然后检查以下各项。

- **推理强度。** 新集成可从 `medium` 开始。如果当前使用 `none` 或 `minimal`，请改用 `low`。在 Responses API 中使用 `reasoning.effort`，在 Chat Completions 中使用 `reasoning_effort`。
- **工具调用。** GPT-6.2 Astra 和 GPT-6.2 Sol 都支持 Chat Completions。工具调用需要使用 Responses API。[从 Chat Completions 迁移至 Responses API](https://developers.openai.com/api/docs/guides/migrate-to-responses#migrating-from-chat-completions)
- **不受支持的参数。** 迁移 Chat Completions 请求时，移除 `temperature`、`top_p`、`logprobs` 和 `top_logprobs`。迁移 Responses API 请求时，移除 `temperature`、`top_p` 和 `top_logprobs`，并从 `include` 中移除 `message.output_text.logprobs`。
- **提示词缓存。** 把稳定的指令从顶层 `instructions` 参数移到 `input` 开头的 `developer` 消息中，使其符合缓存条件。从 GPT-5.5 或更早的版本迁移时，用 `prompt_cache_options.ttl` 替换 `prompt_cache_retention`，并将其设为 `"30m"`。请查阅提示词缓存的变更，包括缓存边界和写入缓存的计费方式。[前缀匹配机制](https://developers.openai.com/api/docs/guides/prompt-caching#how-prefix-matching-works) · [各模型的提示词缓存差异](https://developers.openai.com/api/docs/guides/prompt-caching#summary-of-model-differences)
- **零数据保留。** 对于获批组织，GPT-6.2 Astra 和 Sol 在符合条件的端点和功能上支持零数据保留（Zero Data Retention，ZDR）。启用 ZDR 后，Responses API 会将 `store` 视为 `false`。在多轮请求中，请按原顺序传回先前的输出项，包括加密的推理项。[零数据保留的适用条件与端点行为](https://developers.openai.com/api/docs/guides/your-data#zero-data-retention)
- **服务等级与区域。** 两款模型均通过 Standard、Fast 和 Batch 处理支持美国和欧盟的数据驻留。Ultrafast 仅支持美国数据驻留。[数据驻留](https://developers.openai.com/api/docs/guides/data-residency#which-models-and-features-are-eligible-for-data-residency) · [定价](https://developers.openai.com/api/docs/pricing#text-tokens)
- **提示词。** 参见[提示词最佳实践](#prompting-best-practices)。
