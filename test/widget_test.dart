import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/api/api_types.dart';
import 'package:deepseek_chat/api/sse.dart';
import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/chat/context_builder.dart';
import 'package:deepseek_chat/chat/reply_merge.dart';
import 'package:deepseek_chat/models/chat_models.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/ui/chat/assistant_message.dart';

void main() {
  test('plain reply errors explain recovery in both languages', () {
    for (final (kind, status, message, zh, en) in [
      ('auth', null, '', '登录已失效', 'Your sign-in expired'),
      ('http', 401, 'private', '登录已失效', 'Your sign-in expired'),
      ('http', 403, 'private', '登录已失效', 'Your sign-in expired'),
      ('network', null, '', '网络没连上', "Can't reach the network"),
      ('interrupted', null, '', '回复被中断', 'The reply was interrupted'),
      ('http', 429, '', '请求太频繁', 'Too many requests'),
      (
        'http',
        503,
        '',
        '模型服务暂时不可用',
        'The model service is temporarily unavailable',
      ),
      (
        'stream',
        null,
        'upstream_unavailable',
        '模型服务暂时不可用',
        'The model service is temporarily unavailable',
      ),
      ('protocol', null, 'private', '出了点问题', 'Something went wrong'),
    ]) {
      final error = ReplyError(kind: kind, status: status, message: message);
      expect(plainReplyError(error, true), startsWith(zh));
      expect(plainReplyError(error, false), startsWith(en));
    }
  });

  group('SSE parser', () {
    test('a heartbeat comment does not emit an event', () async {
      final bytes = utf8.encode(': ping\n\n');
      expect(await parseSse(Stream.value(bytes)).toList(), isEmpty);
    });

    test('parses events, multi-line data and comments', () async {
      final input = utf8.encode(
        ': keep-alive\r\n\r\n'
        'event: message_start\r\n'
        'data: {"type":"message_start"}\r\n\r\n'
        'event: content_block_delta\r\n'
        'data: {"type":"content_block_delta",\r\n'
        'data:  "index":0}\r\n\r\n',
      );
      final events = await parseSse(Stream.value(input)).toList();
      expect(events, hasLength(2));
      expect(events.first.event, 'message_start');
      expect(events.first.data, '{"type":"message_start"}');
      expect(events.last.data, contains('"index":0'));
    });
  });

  group('context builder', () {
    final user = UserMessage(id: 'u1', createdAt: 1, content: 'hello');
    final reply = AssistantMessage(
      id: 'a1',
      createdAt: 2,
      parentId: 'u1',
      status: ReplyStatus.done,
      stopReason: StopReason.endTurn,
      latestReminder: '2026-11-16,Monday,,Web,English',
      blocks: [
        TextBlock(
          text: 'hi there',
          citations: [
            Citation(
              url: 'https://example.com',
              title: 'Example',
              citedText: 'hi',
            ),
          ],
        ),
        ThinkingBlock(thinking: 'secret', signature: 'sig'),
        ServerToolUseBlock(
          id: 'tool1',
          name: 'deepseek_read_url',
          kind: 'read_link',
          input: {'action': 'read_link', 'url': 'https://example.com'},
          raw: const {},
        ),
        WebFetchResultBlock(
          toolUseId: 'tool1',
          kind: 'read_link',
          content: {
            'type': 'web_fetch_result',
            'url': 'https://example.com',
            'content': {'type': 'document', 'title': 'Example'},
          },
          signature: 'page-signature',
          raw: const {},
        ),
      ],
    );

    test('builds a pair and strips citations and historical thinking', () {
      final messages = toRequestMessages(
        history: [user, reply],
        question: UserMessage(id: 'u2', createdAt: 3, content: 'again'),
        latestReminder: '2026-11-16,Monday,,Web,English',
      );
      expect(messages.first['role'], 'latest_reminder');
      final assistant = messages[2];
      expect(assistant['role'], 'assistant');
      final blocks = assistant['content'] as List;
      expect(blocks.first, {'type': 'text', 'text': 'hi there'});
      expect(blocks.any((b) => b['type'] == 'thinking'), isFalse);
      expect(blocks.any((b) => b['type'] == 'server_tool_use'), isTrue);
      expect(blocks.any((b) => b['type'] == 'web_fetch_tool_result'), isTrue);
    });

    test('keeps the newest complete rounds in order within budget', () {
      final question = UserMessage(id: 'now', createdAt: 200, content: '继续');
      final history = <ChatMessage>[
        for (var i = 0; i < 100; i++) ...[
          UserMessage(id: 'u$i', createdAt: 2 * i, content: '你好' * 7 + '$i'),
          AssistantMessage(
            id: 'a$i',
            createdAt: 2 * i + 1,
            status: ReplyStatus.done,
            blocks: [TextBlock(text: 'yes$i')],
          ),
        ],
      ];
      final messages = toRequestMessages(
        history: history,
        question: question,
        budgetTokens: 34,
      );
      expect(messages.map((m) => m['role']), [
        'user',
        'assistant',
        'user',
        'assistant',
        'user',
      ]);
      expect(messages[0]['content'], '你好' * 7 + '98');
      expect(messages[2]['content'], '你好' * 7 + '99');
      expect(messages[3]['content'], [
        {'type': 'text', 'text': 'yes99'},
      ]);
      expect(messages.last, userParam(question));
      expect(estimateTokens('汉字かな한글abcdefgh'), 8);
    });

    test('a round with an attachment can exceed the budget on its own', () {
      final file = FileAttachment(
        id: 'file',
        name: 'photo.png',
        size: 300,
        isImage: true,
        mimeType: 'image/png',
        serverId: 'uploaded',
      );
      final question = UserMessage(id: 'now', createdAt: 4, content: 'next');
      final prefix = AssistantMessage(
        id: 'prefix',
        createdAt: 5,
        prefix: true,
        blocks: [TextBlock(text: 'keep writing')],
      );
      final messages = toRequestMessages(
        history: [
          UserMessage(
            id: 'file-turn',
            createdAt: 1,
            content: '',
            files: [file],
          ),
          reply,
        ],
        question: question,
        prefix: prefix,
        budgetTokens: 999,
      );
      expect(messages, [userParam(question), assistantParam(prefix)]);
    });

    test('leaves the wire messages unchanged for a short history', () {
      final question = UserMessage(id: 'now', createdAt: 3, content: 'again');
      expect(toRequestMessages(history: [user, reply], question: question), [
        {'role': 'latest_reminder', 'content': reply.latestReminder},
        userParam(user),
        assistantParam(reply),
        userParam(question),
      ]);
    });

    test('skips error replies in context', () {
      final failed = AssistantMessage(
        id: 'a2',
        createdAt: 2,
        status: ReplyStatus.error,
        blocks: [TextBlock(text: 'oops')],
      );
      final messages = toRequestMessages(
        history: [user, failed],
        question: UserMessage(id: 'u2', createdAt: 3, content: 'again'),
      );
      expect(messages, hasLength(1));
      expect(messages.single['role'], 'user');
    });
  });

  group('stream merge', () {
    test('accumulates text, thinking and citations', () {
      final reply = AssistantMessage(
        id: 'a1',
        createdAt: 1,
        status: ReplyStatus.streaming,
      );
      final indexes = <int, int>{};
      applyApiEvent(
        reply,
        ContentBlockStartEvent(
          index: 0,
          block: {'type': 'thinking', 'thinking': ''},
        ),
        1000,
        indexes,
      );
      applyApiEvent(
        reply,
        ContentBlockStartEvent(index: 1, block: {'type': 'text', 'text': ''}),
        1000,
        indexes,
      );
      applyApiEvent(
        reply,
        const ContentBlockDeltaEvent(
          index: 0,
          delta: ApiDelta.thinking('plan'),
        ),
        1000,
        indexes,
      );
      applyApiEvent(
        reply,
        const ContentBlockDeltaEvent(
          index: 0,
          delta: ApiDelta.signature('sig'),
        ),
        1000,
        indexes,
      );
      applyApiEvent(
        reply,
        const ContentBlockDeltaEvent(index: 1, delta: ApiDelta.text('answer')),
        1000,
        indexes,
      );
      applyApiEvent(
        reply,
        ContentBlockDeltaEvent(
          index: 1,
          delta: ApiDelta.citation(
            const Citation(url: 'https://a.b', title: 'A', citedText: 'answer'),
          ),
        ),
        1000,
        indexes,
      );
      applyApiEvent(
        reply,
        const ContentBlockStopEvent(index: 0),
        2000,
        indexes,
      );
      applyApiEvent(
        reply,
        const ContentBlockStopEvent(index: 1),
        2000,
        indexes,
      );
      applyApiEvent(
        reply,
        const MessageDeltaEvent(stopReason: StopReason.endTurn),
        2000,
        indexes,
      );
      settleReply(reply, ReplyStatus.done, 2000);

      expect(reply.status, ReplyStatus.done);
      expect(reply.stopReason, StopReason.endTurn);
      final thinking = reply.blocks[0] as ThinkingBlock;
      expect(thinking.thinking, 'plan');
      expect(thinking.signature, 'sig');
      expect(thinking.endedAt, 2000);
      final text = reply.blocks[1] as TextBlock;
      expect(text.text, 'answer');
      expect(text.citations.single.url, 'https://a.b');
    });

    test('refusal drops thinking and body blocks', () {
      final reply = AssistantMessage(
        id: 'a1',
        createdAt: 1,
        status: ReplyStatus.streaming,
        blocks: [
          ThinkingBlock(thinking: 'x'),
          TextBlock(text: 'y'),
        ],
      );
      final indexes = <int, int>{};
      applyApiEvent(
        reply,
        const MessageDeltaEvent(stopReason: StopReason.refusal),
        1,
        indexes,
      );
      settleReply(
        reply,
        ReplyStatus.error,
        1,
        error: const ReplyError(kind: 'stream', message: 'refused'),
      );
      expect(reply.blocks, isEmpty);
    });
  });

  group('branches', () {
    test('appends and switches sibling replies', () {
      final session = ChatSession(id: 's', createdAt: 1, updatedAt: 1);
      final user = UserMessage(id: 'u', createdAt: 1, content: 'q');
      final replyA = AssistantMessage(
        id: 'a',
        createdAt: 2,
        status: ReplyStatus.done,
        blocks: [TextBlock(text: 'A')],
      );
      appendBranch(session, null, [user, replyA]);
      expect(session.visibleMessages.map((m) => m.id), ['u', 'a']);
      expect(session.rootMessageId, 'u');

      final replyB = AssistantMessage(
        id: 'b',
        createdAt: 3,
        status: ReplyStatus.done,
        blocks: [TextBlock(text: 'B')],
      );
      appendBranch(session, 'u', [replyB]);
      expect(session.visibleMessages.map((m) => m.id), ['u', 'b']);
      expect(session.messageById('u')!.selectedChildId, 'b');

      selectVersion(session, 'a');
      expect(session.visibleMessages.map((m) => m.id), ['u', 'a']);
    });

    test('continuation eligibility', () {
      final stopped = AssistantMessage(
        id: 'a',
        createdAt: 1,
        status: ReplyStatus.stopped,
        blocks: [TextBlock(text: 'partial')],
      );
      expect(stopped.canContinue, isTrue);

      final withTool = AssistantMessage(
        id: 'b',
        createdAt: 1,
        status: ReplyStatus.stopped,
        blocks: [
          TextBlock(text: 'partial'),
          ServerToolUseBlock(
            id: 't',
            name: 'deepseek_web_search',
            kind: 'search',
            input: {
              'action': 'search',
              'queries': ['x'],
            },
            raw: const {},
          ),
        ],
      );
      expect(withTool.canContinue, isFalse);
    });
  });

  widgetTests();
  messageWidgetTests();
}

// ---------------------------------------------------------------------------
// Widget smoke test

void widgetTests() {
  testWidgets('renders the main menu and opens chat', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ChatController();
    controller.settings.apiKey = 'test-key';
    await tester.pumpWidget(DeepSeekChatApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('开始对话'), findsOneWidget);
    expect(find.text('人格'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    await tester.ensureVisible(find.text('开始对话'));
    await tester.tap(find.text('开始对话'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('今天有什么可以帮到你？'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);

    await tester.tap(find.byTooltip('返回主界面'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('开始对话'), findsOneWidget);

    await tester.ensureVisible(find.text('人格'));
    await tester.tap(find.text('人格'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('默认助手'), findsOneWidget);

    await tester.ensureVisible(find.text('严谨工程师'));
    await tester.tap(find.text('严谨工程师'));
    await tester.pump();
    expect(controller.settings.personaId, 'engineer');
  });
}

void messageWidgetTests() {
  testWidgets('renders thinking, search and markdown answer', (tester) async {
    final controller = ChatController();
    controller.settings.apiKey = 'test';
    final reply = AssistantMessage(
      id: 'a1',
      createdAt: 1,
      status: ReplyStatus.done,
      stopReason: StopReason.endTurn,
      blocks: [
        ThinkingBlock(
          thinking: 'plan the answer',
          startedAt: 1000,
          endedAt: 3000,
        ),
        ServerToolUseBlock(
          id: 't1',
          name: 'deepseek_web_search',
          kind: 'search',
          input: {
            'action': 'search',
            'queries': ['flutter widgets'],
          },
          raw: const {},
        ),
        WebSearchResultBlock(
          toolUseId: 't1',
          kind: 'search',
          content: [
            {
              'type': 'web_search_result',
              'url': 'https://flutter.dev',
              'title': 'Flutter',
              'snippet': 'Build apps for any screen.',
              'site_name': 'flutter.dev',
              'page_age': null,
              'site_icon': null,
            },
          ],
          raw: const {},
        ),
        TextBlock(
          text: '## Heading\n\nHello **world**.',
          citations: [
            Citation(
              url: 'https://flutter.dev',
              title: 'Flutter',
              citedText: 'Hello',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(lightPalette),
        home: AppScope(
          controller: controller,
          strings: const S(true),
          palette: lightPalette,
          child: Scaffold(
            body: SingleChildScrollView(
              child: AssistantMessageTile(
                message: reply,
                streaming: false,
                versions: null,
                onRegenerate: () {},
                onContinue: () {},
                onSwitchVersion: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('flutter widgets'), findsWidgets);
    expect(find.textContaining('已思考'), findsWidgets);
    expect(find.textContaining('Heading'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
