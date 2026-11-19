import 'dart:async';
import 'dart:typed_data';

import 'package:deepseek_chat/api/api_client.dart';
import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/api/api_types.dart';
import 'package:deepseek_chat/api/chat_gateway.dart';
import 'package:deepseek_chat/chat/chat_request.dart';
import 'package:deepseek_chat/models/chat_models.dart';
import 'package:deepseek_chat/models/chat_participant.dart';
import 'package:deepseek_chat/models/chat_preferences.dart';
import 'package:deepseek_chat/models/model_configuration.dart';
import 'package:deepseek_chat/models/persona.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/storage/session_store.dart';
import 'package:deepseek_chat/storage/settings_store.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/chat/chat_view.dart';
import 'package:deepseek_chat/ui/chat/generation_monitor.dart';
import 'package:deepseek_chat/ui/chat/group_message.dart';
import 'package:deepseek_chat/ui/chat/local_image.dart';
import 'package:deepseek_chat/ui/chat/markdown_view.dart';
import 'package:deepseek_chat/ui/participants/participant_avatar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'work monitor follows independent roles and background sessions',
    (tester) async {
      final fixture = _Fixture();
      final chat = fixture.chat;
      await tester.binding.setSurfaceSize(const Size(390, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await fixture.selectTeam();
      await chat.saveParticipant(
        ChatParticipant(
          id: _second.id,
          name: _second.name,
          configuration: _first.configuration,
        ),
      );
      chat.restoreSession(_workSession('background', 'Other conversation'));
      expect(await chat.sendMessage('Background question', []), isTrue);
      final [analyst, tutor] = fixture.gateway.calls;
      expect(analyst.configuration.model, tutor.configuration.model);
      chat.restoreSession(_workSession('editor', 'Editor conversation'));
      await _mountChat(tester, chat, isMobile: true);
      final editor = find.byType(TextField);
      await tester.enterText(editor, 'Keep this draft');
      final editingController = tester.widget<TextField>(editor).controller;
      await tester.tap(find.byKey(const Key('generation-monitor-toggle')));
      await tester.pump();
      expect(
        find.text(
          'No replies in this conversation yet. Send a message to see generation here.',
        ),
        findsOneWidget,
      );

      await _choose(tester, 'monitor-session', 'Other conversation');
      expect(find.text(const S(false).waiting), findsOneWidget);
      analyst.text('Analyst partial');
      tutor.text('Tutor partial');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      Iterable<String> monitoredText() => tester
          .widgetList<MarkdownView>(
            find.descendant(
              of: find.byType(GenerationMonitor),
              matching: find.byType(MarkdownView),
            ),
          )
          .map((m) => m.data);
      expect(monitoredText(), ['Analyst partial']);
      await _choose(tester, 'monitor-role', 'Tutor');
      expect(monitoredText(), ['Tutor partial']);
      expect(chat.activeId, 'editor');
      expect(chat.draftText, 'Keep this draft');

      await _choose(tester, 'monitor-session', 'Follow active conversation');
      expect(monitoredText(), isEmpty);
      await tester.tap(find.byTooltip('Close generation monitor').last);
      await tester.pump();
      expect(find.byType(GenerationMonitor), findsNothing);
      expect(
        tester.widget<TextField>(editor).controller,
        same(editingController),
      );
      expect(analyst.cancelToken.isCancelled, isFalse);
      expect(tutor.cancelToken.isCancelled, isFalse);
      expect(chat.isStreaming('background'), isTrue);

      await analyst.complete('Analyst final');
      await tutor.complete('Tutor final');
      await tester.pump();
      await tester.tap(find.byKey(const Key('generation-monitor-toggle')));
      await tester.pump();
      await _choose(tester, 'monitor-session', 'Other conversation');
      await _choose(tester, 'monitor-role', 'Tutor');
      expect(monitoredText(), ['Tutor partialTutor final']);
      expect(find.text('Generation complete'), findsOneWidget);
      await tester.tap(find.byKey(const Key('request-debug')));
      await tester.pump();
      expect(find.byKey(const Key('request-debug-panel')), findsOneWidget);
      expect(find.byType(GenerationMonitor), findsOneWidget);
      expect(
        tester.widget<TextField>(editor).controller,
        same(editingController),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byType(GenerationMonitor)).dx,
        greaterThan(800),
      );
      expect(
        tester.widget<TextField>(editor).controller,
        same(editingController),
      );
    },
  );

  testWidgets('chat bubbles enclose attachments and retain reply snapshots', (
    tester,
  ) async {
    final fixture = _Fixture();
    final chat = fixture.chat;
    await tester.binding.setSurfaceSize(const Size(390, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await fixture.selectTeam();
    chat.restoreSession(
      ChatSession(
        id: 'group',
        createdAt: 1,
        updatedAt: 1,
        messages: [
          UserMessage(
            id: 'user',
            createdAt: 1,
            content: 'See attached',
            files: [
              FileAttachment(
                id: 'image',
                name: 'example.png',
                size: 64,
                mimeType: 'image/png',
                isImage: true,
              ),
            ],
          ),
          AssistantMessage(
            id: 'reply',
            createdAt: 2,
            participantId: _first.id,
            participantName: 'Historical name',
            participantAvatarBase64: 'AA==',
            status: ReplyStatus.done,
            blocks: [TextBlock(text: 'Historical answer')],
          ),
        ],
      ),
    );
    await _mountChat(tester, chat, isMobile: true);
    final outgoing = find.ancestor(
      of: find.text('See attached'),
      matching: find.byType(GroupBubble),
    );
    expect(outgoing, findsOneWidget);
    expect(
      find.descendant(
        of: outgoing,
        matching: find.byType(LocalAttachmentImage),
      ),
      findsOneWidget,
    );
    expect(find.text('You'), findsOneWidget);
    final history = find.ancestor(
      of: find.text('Historical name'),
      matching: find.byType(GroupMessage),
    );
    final avatar = find.descendant(
      of: history,
      matching: find.byType(ParticipantAvatar),
    );
    expect(tester.widget<ParticipantAvatar>(avatar).avatarBase64, 'AA==');
    expect(
      tester.getCenter(avatar).dx,
      lessThan(tester.getCenter(find.text('Historical name')).dx),
    );
    expect(find.byKey(const Key('generation-monitor-toggle')), findsNothing);
    await chat.setChatMode(ChatMode.work);
    await tester.pump();
    expect(find.byType(GroupBubble), findsNothing);
    expect(find.text('Historical name'), findsOneWidget);
    expect(find.byKey(const Key('generation-monitor-toggle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final sameModel in [false, true]) {
    test('linked personas collaborate (same model: $sameModel)', () async {
      final fixture = _Fixture();
      final chat = fixture.chat;
      final analyst = await chat.importPersona(
        '{"version":1,"name":"Evidence","system_prompt":"Find evidence",'
        '"workflow":["Check sources","Report gaps"]}',
      );
      final tutor = await chat.savePersona(
        name: 'Examples',
        systemPrompt: 'Give examples',
      );
      await chat.saveParticipant(
        ChatParticipant(
          id: 'first',
          name: 'Analyst',
          personaId: analyst.id,
          configuration: _first.configuration,
        ),
      );
      await chat.saveParticipant(
        ChatParticipant(
          id: 'second',
          name: 'Tutor',
          personaId: tutor.id,
          systemPrompt: '  Give examples  ',
          configuration: sameModel
              ? _first.configuration
              : _second.configuration,
        ),
      );
      await chat.setSelectedParticipantIds(['first', 'second']);
      chat.setDebugRecording(true);
      expect(await chat.sendMessage('First task', []), isTrue);
      final [first, second] = fixture.gateway.calls;
      expect(
        first.configuration.model == second.configuration.model,
        sameModel,
      );
      expect(first.request.systemPrompt, contains('Find evidence'));
      expect(
        first.request.systemPrompt,
        contains('1. Check sources\n2. Report gaps'),
      );
      expect(first.request.systemPrompt, isNot(contains('Give examples')));
      expect(
        'Give examples'.allMatches(second.request.systemPrompt),
        hasLength(1),
      );
      expect(first.request.systemPrompt, contains('你在本对话中的名字是 Analyst。'));
      expect(second.request.systemPrompt, isNot(contains('Find evidence')));
      expect(first.request.history, isEmpty);
      expect(second.request.history, isEmpty);
      expect(chat.activeRequestDebug.map((r) => r.systemPrompt), [
        second.request.systemPrompt,
        first.request.systemPrompt,
      ]);
      expect(
        chat.activeRequestDebug.first.systemChars,
        second.request.systemPrompt.length,
      );
      expect(chat.activeRequestDebug.map((r) => r.status), [
        ReplyStatus.streaming,
        ReplyStatus.streaming,
      ]);
      var finished = fixture.finished();
      await Future.wait([
        second.complete('Tutorial'),
        first.complete('Evidence'),
      ]);
      await finished;
      expect(
        chat.activeRequestDebug.every((r) => r.status == ReplyStatus.done),
        isTrue,
      );
      expect(
        await chat.sendMessage('Build on the earlier replies', []),
        isTrue,
      );
      for (final call in fixture.gateway.calls.skip(2)) {
        expect(
          call.request.history.whereType<AssistantMessage>().single.text,
          allOf(contains('[Analyst]\nEvidence'), contains('[Tutor]\nTutorial')),
        );
      }
      final third = fixture.gateway.calls[2];
      final fourth = fixture.gateway.calls[3];
      expect(third.request.systemPrompt, first.request.systemPrompt);
      expect(fourth.request.systemPrompt, second.request.systemPrompt);
      finished = fixture.finished();
      third.frames.addError(ApiException('http', 'private body', status: 429));
      await third.frames.close();
      expect(chat.activeRequestDebug[1].errorKind, 'http');
      expect(chat.activeRequestDebug[1].httpStatus, 429);
      expect(chat.activeRequestDebug[1].errorMessage, 'private body');
      expect(chat.activeRequestDebug.first.status, ReplyStatus.streaming);
      fourth.cancelToken.cancel();
      await finished;
      expect(chat.activeRequestDebug.first.status, ReplyStatus.stopped);
      chat.setDebugRecording(false);
      expect(chat.activeRequestDebug, isEmpty);
    });
  }

  test(
    'one send starts separate requests and one failure does not end the batch',
    () async {
      final fixture = _Fixture();
      final chat = fixture.chat;
      await fixture.selectTeam();
      expect(chat.hasChatConnection, isTrue);
      expect(await chat.sendMessage('Question', []), isTrue);
      final first = fixture.gateway.calls[0];
      final second = fixture.gateway.calls[1];
      expect(first.configuration.apiKey, 'first-key');
      expect(second.configuration.apiKey, 'second-key');
      expect(first.request.systemPrompt, contains('Be concise'));
      expect(second.request.systemPrompt, contains('Give examples'));
      expect(first.request.systemPrompt, isNot(contains('Give examples')));
      expect(first.request.history, isEmpty);
      expect(second.request.history, isEmpty);
      expect(identical(first.cancelToken, second.cancelToken), isFalse);
      expect(fixture.replies.map((reply) => reply.participantName), [
        'Analyst',
        'Tutor',
      ]);
      expect(fixture.replies.first.participantAvatarBase64, 'AA==');

      await chat.saveParticipant(_first.copyWithName('New Analyst', 'new-key'));
      second.frames.addError(ApiException('http', 'Provider rejected request'));
      await second.frames.close();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.replies.last.status, ReplyStatus.error);
      expect(first.configuration.apiKey, 'first-key');
      expect(chat.activeStreaming, isTrue);
      expect(await chat.sendMessage('Wait', []), isFalse);

      final finished = fixture.finished();
      await first.complete('First answer');
      await finished;
      expect(fixture.replies.first.text, 'First answer');
      expect(fixture.replies.first.status, ReplyStatus.done);
      expect(fixture.replies.first.participantName, 'Analyst');
      final persisted = fixture.store.lastSession!;
      expect(persisted.selectedParticipantIds, ['first', 'second']);
      expect(persisted.toJson().toString(), isNot(contains('first-key')));
      expect(
        persisted.visibleMessages
            .whereType<AssistantMessage>()
            .first
            .participantAvatarBase64,
        'AA==',
      );
    },
  );

  test('each successful assistant stream gets one delivery cue', () async {
    final fixture = _Fixture();
    final chat = fixture.chat;
    var deliveries = 0;
    chat.onReplyDelivered = () async {
      deliveries++;
    };
    await fixture.selectTeam();
    await chat.sendMessage('Question', []);
    final finished = fixture.finished();
    final first = fixture.gateway.calls[0];
    final second = fixture.gateway.calls[1];
    first.text('First answer');
    second.text('Second answer');
    await Future<void>.delayed(Duration.zero);
    expect(deliveries, 0);
    await first.complete('');
    await Future<void>.delayed(Duration.zero);
    expect(chat.activeStreaming, isTrue);
    expect(deliveries, 1);
    await second.complete('');
    await finished;
    expect(deliveries, 2);
  });

  test('later turns share all labeled public replies, including with the main model', () async {
    final fixture = _Fixture();
    final chat = fixture.chat;
    await fixture.selectTeam();
    await chat.sendMessage('First question', []);
    final initial = fixture.finished();
    final first = fixture.gateway.calls.first;
    first.frames.add(
      const ContentBlockStartEvent(
        index: 1,
        block: {
          'type': 'thinking',
          'thinking': 'PRIVATE',
          'signature': 'SIGNED',
        },
      ),
    );
    await Future.wait([
      first.complete('Alpha'),
      fixture.gateway.calls[1].complete('Beta'),
    ]);
    await initial;

    await chat.setSelectedParticipantIds([]);
    chat.settings.apiKey = 'legacy-key';
    expect(await chat.sendMessage('Second question', []), isTrue);
    final legacy = fixture.gateway.calls[2];
    expect(legacy.configuration.apiKey, 'legacy-key');
    expect(legacy.request.history, hasLength(2));
    final shared = legacy.request.history.last as AssistantMessage;
    expect(shared.text, '[Analyst]\nAlpha\n\n[Tutor]\nBeta');
    expect(shared.blocks.every((block) => block is TextBlock), isTrue);
    expect(shared.latestReminder, isNull);
    final finished = fixture.finished();
    await legacy.complete('Legacy response');
    await finished;
  });

  test(
    'stop cancels all streams; continuing and retrying use the reply identity',
    () async {
      final fixture = _Fixture();
      final chat = fixture.chat;
      await fixture.selectTeam();
      await chat.sendMessage('Question', []);
      final first = fixture.gateway.calls[0];
      final second = fixture.gateway.calls[1];
      first.text('First partial');
      second.text('Second partial');
      await Future<void>.delayed(Duration.zero);
      var finished = fixture.finished();
      chat.stopReply();
      await finished;
      expect(first.cancelToken.isCancelled, isTrue);
      expect(second.cancelToken.isCancelled, isTrue);
      expect(fixture.replies.map((reply) => reply.status), [
        ReplyStatus.stopped,
        ReplyStatus.stopped,
      ]);

      final firstId = fixture.replies[0].id;
      final secondId = fixture.replies[1].id;
      await chat.setSelectedParticipantIds(['second']);
      expect(await chat.continueReply(firstId), isTrue);
      final continuation = fixture.gateway.calls[2];
      expect(continuation.configuration.apiKey, 'first-key');
      expect(continuation.request.prefix?.text, 'First partial');
      finished = fixture.finished();
      await continuation.complete(' and more');
      await finished;
      expect(fixture.replies.first.text, 'First partial and more');

      expect(await chat.regenerate(firstId), isTrue);
      final retry = fixture.gateway.calls[3];
      expect(retry.configuration.apiKey, 'first-key');
      expect(retry.request.history, isEmpty);
      finished = fixture.finished();
      await retry.complete('Revised');
      await finished;
      expect(fixture.replies.map((reply) => reply.text), [
        'Revised',
        'Second partial',
      ]);
      expect(fixture.replies.map((reply) => reply.participantId), [
        'first',
        'second',
      ]);
      expect(fixture.replies.last.id, isNot(secondId));
      await chat.switchVersion(firstId);
      expect(fixture.replies.first.text, 'First partial and more');
      expect(fixture.replies.last.id, secondId);
    },
  );

  test(
    'an incompatible attachment names the recipient and is never sent',
    () async {
      final fixture = _Fixture();
      final chat = fixture.chat;
      await fixture.selectTeam();
      final files = [
        FileAttachment(
          id: 'image',
          name: 'photo.png',
          size: 5,
          isImage: true,
          mimeType: 'image/png',
        ),
      ];
      expect(chat.draftAttachmentError(files), contains('Tutor'));
      expect(await chat.sendMessage('Question', files), isFalse);
      expect(fixture.gateway.calls, isEmpty);
    },
  );

  test(
    'a newly selected model can read prior answers without unsupported files',
    () async {
      final fixture = _Fixture();
      final chat = fixture.chat;
      await fixture.selectTeam();
      await chat.setSelectedParticipantIds(['first']);
      final image = FileAttachment(
        id: 'image',
        name: 'photo.png',
        size: 5,
        isImage: true,
        mimeType: 'image/png',
      );
      expect(await chat.sendMessage('', [image]), isTrue);
      var finished = fixture.finished();
      await fixture.gateway.calls.first.complete('There is a sunrise.');
      await finished;

      await chat.setSelectedParticipantIds(['first', 'second']);
      expect(await chat.sendMessage('Explain the last answer', []), isTrue);
      final first = fixture.gateway.calls[1];
      final second = fixture.gateway.calls[2];
      expect(
        (first.request.history.first as UserMessage).files.single.id,
        image.id,
      );
      final projected = second.request.history.first as UserMessage;
      expect(projected.files, isEmpty);
      expect(projected.content, contains('photo.png'));
      expect(
        (second.request.history.last as AssistantMessage).text,
        contains('There is a sunrise.'),
      );
      expect(
        (chat.activeSession!.visibleMessages.first as UserMessage)
            .files
            .single
            .id,
        image.id,
      );
      finished = fixture.finished();
      await Future.wait([first.complete('One'), second.complete('Two')]);
      await finished;
      final deletedReply = fixture.replies.last;
      await chat.deleteParticipant('second');
      expect(chat.canReplyAs(deletedReply), isFalse);
      expect(fixture.replies.last.participantName, 'Tutor');
    },
  );
}

const _first = ChatParticipant(
  id: 'first',
  name: 'Analyst',
  avatarBase64: 'AA==',
  configuration: ModelConfiguration(apiKey: 'first-key'),
  systemPrompt: 'Be concise',
);

const _second = ChatParticipant(
  id: 'second',
  name: 'Tutor',
  configuration: ModelConfiguration(
    protocol: ApiProtocol.openaiCompatible,
    apiOrigin: 'https://other.example/v1',
    apiKey: 'second-key',
    model: 'test-model',
  ),
  systemPrompt: 'Give examples',
);

extension on ChatParticipant {
  ChatParticipant copyWithName(String name, String apiKey) => ChatParticipant(
    id: id,
    name: name,
    configuration: configuration.copyWith(apiKey: apiKey),
    systemPrompt: systemPrompt,
    avatarBase64: avatarBase64,
  );
}

ChatSession _workSession(String id, String title) => ChatSession(
  id: id,
  title: title,
  createdAt: 1,
  updatedAt: 1,
  mode: ChatMode.work,
  selectedParticipantIds: ['first', 'second'],
);

Future<void> _mountChat(
  WidgetTester tester,
  ChatController chat, {
  required bool isMobile,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(lightPalette),
      builder: (context, child) => ListenableBuilder(
        listenable: chat,
        builder: (context, _) => AppScope(
          controller: chat,
          palette: lightPalette,
          strings: const S(false),
          child: child!,
        ),
      ),
      home: Scaffold(body: ChatView(isMobile: isMobile)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key, String label) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(label).last);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

class _Fixture {
  _Fixture() {
    chat = ChatController(
      chatGateway: gateway,
      settingsStore: _Profiles(),
      sessionStore: store,
    );
    addTearDown(chat.dispose);
  }

  final gateway = _Gateway();
  final store = _Store();
  late final ChatController chat;

  List<AssistantMessage> get replies => chat.activeSession!.visibleMessages
      .whereType<AssistantMessage>()
      .toList();

  Future<void> selectTeam() async {
    await chat.saveParticipant(_first);
    await chat.saveParticipant(_second);
    await chat.setSelectedParticipantIds(['first', 'second']);
  }

  Future<void> finished() async {
    final done = Completer<void>();
    void listener() {
      if (!chat.activeStreaming && !done.isCompleted) done.complete();
    }

    chat.addListener(listener);
    try {
      await done.future.timeout(const Duration(seconds: 2));
    } finally {
      chat.removeListener(listener);
    }
  }
}

class _Profiles extends SettingsStore {
  @override
  Future<void> savePersonas(List<Persona> values) async {}

  @override
  Future<void> saveParticipants(List<ChatParticipant> participants) async {}
}

class _Store extends SessionStore {
  ChatSession? lastSession;

  @override
  Future<void> saveDrafts(Map<String, dynamic> data) async {}

  @override
  Future<void> saveIndex(List<SessionSummary> sessions) async {}

  @override
  Future<void> saveSession(ChatSession session) async {
    lastSession = session.copy();
  }
}

class _Gateway extends ChatGateway {
  _Gateway()
    : super(
        legacyClient: ApiClient(),
        readAttachment: (_) async => Uint8List(0),
      );

  final calls = <_Call>[];

  @override
  Stream<ApiEvent> stream({
    required ModelConfiguration configuration,
    required ChatRequest request,
    required CancelToken cancelToken,
    void Function()? onAttachmentChanged,
    bool followRedirects = true,
  }) {
    final call = _Call(configuration, request, cancelToken);
    calls.add(call);
    unawaited(
      cancelToken.whenCancel.then((_) async {
        if (!call.frames.isClosed) await call.frames.close();
      }),
    );
    return call.frames.stream;
  }
}

class _Call {
  _Call(this.configuration, this.request, this.cancelToken);

  final ModelConfiguration configuration;
  final ChatRequest request;
  final CancelToken cancelToken;
  final frames = StreamController<ApiEvent>();

  void text(String content) => frames.add(
    ContentBlockStartEvent(index: 0, block: {'type': 'text', 'text': content}),
  );

  Future<void> complete(String content) async {
    text(content);
    frames.add(const MessageDeltaEvent(stopReason: StopReason.endTurn));
    await frames.close();
  }
}
