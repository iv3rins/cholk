import '../models/chat_models.dart';

/// Sample conversations for the browser-based UI preview. They are only used
/// when the app runs with `--dart-define=DEMO_UI=true` on Flutter Web.
List<ChatSession> createDemoSessions() {
  final now = DateTime.now();
  final richTime = now.millisecondsSinceEpoch;

  final rich = ChatSession(
    id: 'demo-flutter',
    title: 'Flutter 问候页面',
    createdAt: richTime - 120000,
    updatedAt: richTime,
  );

  final firstUser = UserMessage(
    id: 'demo-u1',
    createdAt: richTime - 120000,
    content: '帮我写一个 Flutter 的问候页面，并解释一下关键代码。',
  );
  final firstReply = AssistantMessage(
    id: 'demo-a1',
    createdAt: richTime - 110000,
    status: ReplyStatus.done,
    stopReason: StopReason.endTurn,
    model: 'deepseek-flash',
    thinking: true,
    search: true,
    latestReminder: '2026-11-16,星期日,,Web,中文',
    blocks: [
      ThinkingBlock(
        thinking:
            '用户需要一个可以直接运行的 Flutter 页面示例，最好包含状态更新和按钮交互。'
            '我会先给出一个最小实现，再说明 StatefulWidget 和 setState 的作用。',
        startedAt: richTime - 114000,
        endedAt: richTime - 111000,
      ),
      ServerToolUseBlock(
        id: 'demo-tool-1',
        name: 'deepseek_web_search',
        kind: 'search',
        input: {
          'action': 'search',
          'queries': ['Flutter StatefulWidget 示例', 'Flutter setState 用法'],
        },
        raw: const {},
      ),
      WebSearchResultBlock(
        toolUseId: 'demo-tool-1',
        kind: 'search',
        content: [
          {
            'type': 'web_search_result',
            'url': 'https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html',
            'title': 'StatefulWidget class',
            'snippet': 'A widget that has mutable state.',
            'site_name': 'api.flutter.dev',
            'page_age': null,
            'site_icon': null,
          },
          {
            'type': 'web_search_result',
            'url': 'https://docs.flutter.dev/ui/interactivity',
            'title': 'Adding interactivity to your Flutter app',
            'snippet': 'Learn how to add a stateful widget and call setState.',
            'site_name': 'docs.flutter.dev',
            'page_age': null,
            'site_icon': null,
          },
        ],
        raw: const {},
      ),
      TextBlock(
        text:
            '## 一个简单的问候页面\n\n'
            '下面是一个使用 `StatefulWidget` 的示例，点击按钮会更新问候语。\n\n',
        citations: [
          Citation(
            url: 'https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html',
            title: 'StatefulWidget class',
            citedText: '下面是一个使用 StatefulWidget 的示例',
          ),
        ],
      ),
      TextBlock(
        text: r'''```dart
class GreetingPage extends StatefulWidget {
  const GreetingPage({super.key});

  @override
  State<GreetingPage> createState() => _GreetingPageState();
}

class _GreetingPageState extends State<GreetingPage> {
  String _name = '世界';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('问候')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('你好，$_name！'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => setState(() => _name = 'Flutter'),
              child: const Text('换个问候'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- `StatefulWidget` 负责保存可变状态
- 调用 `setState` 后界面会重新构建
- `const` 构造函数可以减少不必要的重建

如果需要，我也可以继续加上输入框、主题切换和数据持久化。''',
      ),
    ],
    usage: MessageUsage(inputTokens: 1280, outputTokens: 640),
  );

  final secondUser = UserMessage(
    id: 'demo-u2',
    createdAt: richTime - 60000,
    content: '再帮我总结一下这个页面的关键点。',
  );
  final secondReply = AssistantMessage(
    id: 'demo-a2',
    createdAt: richTime - 50000,
    status: ReplyStatus.done,
    stopReason: StopReason.endTurn,
    model: 'deepseek-flash',
    blocks: [
      TextBlock(
        text:
            '## 关键点\n\n'
            '- 用 `StatefulWidget` 保存页面状态\n'
            '- 把可变字段放在 `State` 子类里\n'
            '- 通过 `setState` 触发界面重建\n'
            '- 用 `const` 构造不可变的小组件',
      ),
    ],
  );

  appendBranch(rich, null, [firstUser, firstReply]);
  appendBranch(rich, firstReply.id, [secondUser, secondReply]);
  rich.updatedAt = richTime;

  final sseTime = now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
  final sse = ChatSession(
    id: 'demo-sse',
    title: 'SSE 流式协议',
    createdAt: sseTime,
    updatedAt: sseTime,
  );
  final sseUser = UserMessage(
    id: 'demo-sse-u',
    createdAt: sse.createdAt,
    content: 'SSE 和 WebSocket 的主要区别是什么？',
  );
  final sseReply = AssistantMessage(
    id: 'demo-sse-a',
    createdAt: sse.createdAt + 1000,
    status: ReplyStatus.done,
    stopReason: StopReason.endTurn,
    blocks: [
      TextBlock(
        text:
            'SSE 是单向的服务器推送，基于普通 HTTP，适合聊天和通知；'
            'WebSocket 是全双工连接，适合需要频繁双向交互的场景。',
      ),
    ],
  );
  appendBranch(sse, null, [sseUser, sseReply]);
  sse.updatedAt = sseTime;

  final errorTime = now
      .subtract(const Duration(days: 3))
      .millisecondsSinceEpoch;
  final error = ChatSession(
    id: 'demo-error',
    title: '接口调试记录',
    createdAt: errorTime,
    updatedAt: errorTime,
  );
  final errorUser = UserMessage(
    id: 'demo-error-u',
    createdAt: error.createdAt,
    content: '用这个 Key 请求一直返回 401。',
  );
  final errorReply = AssistantMessage(
    id: 'demo-error-a',
    createdAt: error.createdAt + 1000,
    status: ReplyStatus.error,
    stopReason: StopReason.endTurn,
    error: const ReplyError(
      kind: 'http',
      message: '401 Unauthorized: invalid api key',
      status: 401,
    ),
  );
  appendBranch(error, null, [errorUser, errorReply]);
  error.updatedAt = errorTime;

  final travelTime = now
      .subtract(const Duration(days: 10))
      .millisecondsSinceEpoch;
  final travel = ChatSession(
    id: 'demo-travel',
    title: '周末旅行计划',
    createdAt: travelTime,
    updatedAt: travelTime,
  );
  final travelUser = UserMessage(
    id: 'demo-travel-u',
    createdAt: travel.createdAt,
    content: '帮我安排一个两天一夜的周末行程。',
  );
  final travelReply = AssistantMessage(
    id: 'demo-travel-a',
    createdAt: travel.createdAt + 1000,
    status: ReplyStatus.stopped,
    stopReason: StopReason.maxTokens,
    blocks: [
      TextBlock(
        text:
            '第一天的安排是上午到达、下午逛老街，晚上住在河边。第二天可以早起看日出，'
            '中午返程。',
      ),
    ],
  );
  appendBranch(travel, null, [travelUser, travelReply]);
  travel.updatedAt = travelTime;

  return [travel, error, sse, rich];
}
