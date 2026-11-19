import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;

import 'package:deepseek_chat/api/api_client.dart';
import 'package:deepseek_chat/api/api_types.dart';
import 'package:deepseek_chat/api/chat_gateway.dart';
import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/chat/chat_request.dart';
import 'package:deepseek_chat/models/chat_models.dart';
import 'package:deepseek_chat/models/model_configuration.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/storage/session_store.dart';
import 'package:deepseek_chat/ui/chat/chat_input.dart';
import 'package:deepseek_chat/ui/chat/markdown_view.dart';
import 'package:deepseek_chat/ui/chat/sider.dart';

class _MemoryStore extends SessionStore {
  @override
  Future<void> saveDrafts(Map<String, dynamic> data) async {}
  @override
  Future<void> saveSession(ChatSession session) async {}
  @override
  Future<void> saveIndex(List<SessionSummary> sessions) async {}
}

class _ManualGateway extends ChatGateway {
  _ManualGateway()
    : super(
        legacyClient: ApiClient(),
        readAttachment: (_) async => Uint8List(0),
      );

  final events = StreamController<ApiEvent>();

  @override
  Stream<ApiEvent> stream({
    required ModelConfiguration configuration,
    required ChatRequest request,
    required CancelToken cancelToken,
    void Function()? onAttachmentChanged,
    bool followRedirects = true,
  }) => events.stream;
}

ContentBlockStartEvent _text(String text) =>
    ContentBlockStartEvent(index: 0, block: {'type': 'text', 'text': text});

const _reasoning = ContentBlockStartEvent(
  index: 0,
  block: {'type': 'thinking', 'thinking': 'Reasoning without an answer'},
);

const _tool = ContentBlockStartEvent(
  index: 1,
  block: {'type': 'server_tool_use', 'id': 'search', 'name': 'web_search'},
);

Future<void> _when(ChatController chat, bool Function() condition) async {
  if (condition()) return;
  final observed = Completer<void>();
  void listener() {
    if (!observed.isCompleted && condition()) observed.complete();
  }

  chat.addListener(listener);
  try {
    await observed.future.timeout(const Duration(seconds: 3));
  } finally {
    chat.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('streaming updates the reply without rebuilding the workspace', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final gateway = _ManualGateway();
    final chat = ChatController(
      chatGateway: gateway,
      sessionStore: _MemoryStore(),
    );
    addTearDown(chat.dispose);
    chat.settings.apiKey = 'fake-key';
    await tester.pumpWidget(DeepSeekChatApp(controller: chat));
    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();
    expect(await chat.sendMessage('Hello', []), isTrue);
    await tester.pump();

    final sidebar = tester.widget<Sider>(find.byType(Sider));
    final composer = tester.widget<ChatInput>(find.byType(ChatInput));
    gateway.events.add(_text('Streamed answer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is MarkdownView && widget.data == 'Streamed answer',
      ),
      findsOneWidget,
    );
    expect(tester.widget<Sider>(find.byType(Sider)), same(sidebar));
    expect(tester.widget<ChatInput>(find.byType(ChatInput)), same(composer));

    gateway.events.add(const MessageStopEvent());
    await gateway.events.close();
    await tester.pumpAndSettle();
    expect(chat.activeStreaming, isFalse);
  });

  for (final outcome in [
    'normal',
    'cancelled',
    'failed',
    'interrupted after finish reason',
    'refused',
    'thinking and tool only',
    'switched away',
    'playback failure',
  ]) {
    test('delivery cue: $outcome', () async {
      final gateway = _ManualGateway();
      var deliveries = 0;
      final chat = ChatController(
        chatGateway: gateway,
        sessionStore: _MemoryStore(),
        onReplyDelivered: () async {
          deliveries++;
          if (outcome == 'playback failure') throw StateError('Unavailable');
        },
      );
      addTearDown(chat.dispose);
      chat.settings.apiKey = 'fake-key';
      expect(await chat.sendMessage('Hello', []), isTrue);
      final session = chat.activeSession!;
      final reply = session.visibleMessages.last as AssistantMessage;
      expect(deliveries, 0);

      if (outcome == 'thinking and tool only') {
        gateway.events.add(_reasoning);
        gateway.events.add(_tool);
      } else {
        gateway.events.add(_text('New answer'));
        await _when(chat, () => reply.text == 'New answer');
        expect(deliveries, 0, reason: 'Partial text must be silent');
      }

      if (outcome == 'cancelled') chat.stopReply();
      if (outcome == 'switched away') chat.newChat();
      if (outcome == 'failed') {
        gateway.events.addError(ApiException('stream', 'Disconnected'));
      } else {
        gateway.events.add(
          MessageDeltaEvent(
            stopReason: outcome == 'refused'
                ? StopReason.refusal
                : StopReason.endTurn,
          ),
        );
        if (outcome == 'interrupted after finish reason') {
          gateway.events.addError(ApiException('interrupted', ''));
        } else {
          gateway.events.add(const MessageStopEvent());
        }
      }
      await gateway.events.close();
      await _when(chat, () => !chat.isStreaming(session.id));

      expect(
        deliveries,
        outcome == 'normal' || outcome == 'playback failure' ? 1 : 0,
      );
      expect(reply.status, switch (outcome) {
        'cancelled' => ReplyStatus.stopped,
        'failed' => ReplyStatus.error,
        _ => ReplyStatus.done,
      });
      if (outcome == 'switched away') {
        chat.restoreSession(session);
        expect(deliveries, 0, reason: 'Returning to history must be silent');
      }
    });
  }

  for (final addition in ['', ' \n ', ' More text.']) {
    test(
      'delivery cue on continuation with ${addition.trim().isEmpty ? 'no' : 'some'} new text (${addition.length} chars)',
      () async {
        final gateway = _ManualGateway();
        var deliveries = 0;
        final chat = ChatController(
          chatGateway: gateway,
          sessionStore: _MemoryStore(),
          onReplyDelivered: () async {
            deliveries++;
          },
        );
        addTearDown(chat.dispose);
        chat.settings.apiKey = 'fake-key';
        final reply = AssistantMessage(
          id: 'a',
          createdAt: 2,
          status: ReplyStatus.done,
          stopReason: StopReason.maxTokens,
          blocks: [TextBlock(text: 'Existing answer.')],
        );
        final session = ChatSession(id: 'test', createdAt: 1, updatedAt: 2);
        appendBranch(session, null, [
          UserMessage(id: 'u', createdAt: 1, content: 'Hello'),
          reply,
        ]);
        chat.restoreSession(session);
        expect(deliveries, 0);
        expect(await chat.continueReply(), isTrue);
        if (addition.isNotEmpty) gateway.events.add(_text(addition));
        gateway.events.add(
          const MessageDeltaEvent(stopReason: StopReason.endTurn),
        );
        gateway.events.add(const MessageStopEvent());
        await gateway.events.close();
        await _when(chat, () => !chat.isStreaming(session.id));
        expect(reply.text, 'Existing answer.$addition');
        expect(deliveries, addition.trim().isEmpty ? 0 : 1);
      },
    );
  }
}
