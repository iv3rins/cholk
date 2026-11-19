import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/api/account_client.dart';
import 'package:deepseek_chat/api/api_client.dart';
import 'package:deepseek_chat/api/api_types.dart';
import 'package:deepseek_chat/api/chat_gateway.dart';
import 'package:deepseek_chat/chat/chat_request.dart';
import 'package:deepseek_chat/models/chat_member.dart';
import 'package:deepseek_chat/models/chat_models.dart';
import 'package:deepseek_chat/models/chat_preferences.dart';
import 'package:deepseek_chat/models/model_configuration.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/storage/session_store.dart';
import 'package:deepseek_chat/storage/settings_store.dart';

const _address = 'https://server.example';

class _MemoryStore extends SessionStore {
  ChatSession? lastSession;

  @override
  Future<List<SessionSummary>> loadIndex() async => [];

  @override
  Future<List<SessionSummary>> scanSessions() async => [];

  @override
  Future<Map<String, dynamic>> loadDrafts() async => {};

  @override
  Future<void> saveDrafts(Map<String, dynamic> data) async {}

  @override
  Future<void> saveSession(ChatSession session) async {
    lastSession = session.copy();
  }

  @override
  Future<void> saveIndex(List<SessionSummary> sessions) async {}
}

/// Records saved connections so a test can assert a conversation's snapshot is
/// what actually reaches the network layer.
class _NotebookSettings extends _MemorySettings {
  final List<ModelConfiguration> saved = [];

  @override
  Future<void> saveModelConfiguration(ModelConfiguration value) async {
    saved.add(value);
  }
}

class _MemorySettings extends SettingsStore {
  String? address;
  ChatModelRef? chatModel;
  @override
  Future<void> setServerAddress(String value) async {
    address = value;
  }

  @override
  Future<void> setChatModel(ChatModelRef? value) async {
    chatModel = value;
  }

  @override
  Future<void> savePersonas(List<dynamic> values) async {}

  @override
  Future<void> saveParticipants(List<dynamic> participants) async {}

  @override
  Future<void> saveModelConfiguration(ModelConfiguration value) async {}
}

class _Call {
  _Call(this.configuration, this.request, this.redirects);

  final ModelConfiguration configuration;
  final ChatRequest request;
  final bool redirects;
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
    final call = _Call(configuration, request, followRedirects);
    calls.add(call);
    unawaited(
      cancelToken.whenCancel.then((_) async {
        if (!call.frames.isClosed) await call.frames.close();
      }),
    );
    return call.frames.stream;
  }
}

AccountClient _signedInAccount({
  String token = 'memory-token',
  List<String> models = const ['account-model', 'second-model'],
}) => AccountClient(
  httpClient: MockClient((request) async {
    switch (request.url.path) {
      case '/auth/login':
        return http.Response(
          jsonEncode({'username': 'alice', 'token': token}),
          200,
          headers: {'content-type': 'application/json'},
        );
      case '/v1/models':
        return http.Response(
          jsonEncode({
            'data': [
              for (final model in models) {'id': model},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      default:
        return http.Response('', 404);
    }
  }),
);

Future<ChatController> _signedIn({
  SettingsStore? settingsStore,
  _MemoryStore? store,
  _Gateway? gateway,
  List<String> models = const ['account-model', 'second-model'],
}) async {
  final controller = ChatController(
    chatGateway: gateway ?? _Gateway(),
    settingsStore: settingsStore ?? _MemorySettings(),
    sessionStore: store ?? _MemoryStore(),
    accountClient: _signedInAccount(models: models),
  );
  addTearDown(controller.dispose);
  await controller.init();
  expect(controller.initError, isFalse);
  await controller.account.authenticate(
    _address,
    username: 'alice',
    password: 'secret',
    register: false,
  );
  await controller.setServerAddress(_address);
  return controller;
}

/// Pumps the event loop until [condition] holds. The streams are completed
/// explicitly, so this waits on state instead of on a timeout.
Future<void> _until(ChatController chat, bool Function() condition) async {
  if (condition()) return;
  final observed = Completer<void>();
  void listener() {
    if (!observed.isCompleted && condition()) observed.complete();
  }

  chat.addListener(listener);
  try {
    await observed.future.timeout(const Duration(seconds: 5));
  } finally {
    chat.removeListener(listener);
  }
}

/// Waits for one turn to finish. The controller throttles its notifications
/// with a timer, and a plain `test` runs on fake time, so the timer has to be
/// advanced explicitly before the batch can be observed as finished.
///
/// [whileRunning] closes a stream while the clock keeps moving. A batch whose
/// streams closed sends the final persist into a microtask that only runs once
/// time advances, so the advancing has to happen here rather than in the test.
Future<void> _settle(
  ChatController chat, {
  Future<void> Function()? whileRunning,
}) async {
  if (whileRunning != null) {
    var closed = false;
    // `then` keeps the chain's own value; the error handler must return one too.
    final work = whileRunning().then<void>((_) {
      closed = true;
    }, onError: (Object _) {});
    unawaited(work);
    for (var round = 0; round < 400; round++) {
      await _advance(const Duration(milliseconds: 20));
      if (closed && !chat.hasRunningWork) return;
    }
    await work;
  }
  for (var round = 0; round < 400; round++) {
    if (!chat.hasRunningWork) return;
    await _advance(const Duration(milliseconds: 20));
  }
  await _until(chat, () => !chat.hasRunningWork);
}

/// Moves the fake clock and lets the callbacks it queues run.
Future<void> _advance(Duration duration) async {
  final ticked = Completer<void>();
  Timer(duration, () {
    if (!ticked.isCompleted) ticked.complete();
  });
  await ticked.future;
  await Future<void>.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Keeps SettingsStore's plugin lookups quiet; every test overrides the store.
  SharedPreferences.setMockInitialValues({});

  test('a signed-in server answers through its token at /v1 without redirects', () async {
    final gateway = _Gateway();
    final chat = await _signedIn(gateway: gateway);
    expect(
      chat.availableChatModels.map(
        (ref) => '${ref.model}@${ref.serverAddress}',
      ),
      contains('account-model@$_address'),
      reason: 'the signed-in server offers its own models first',
    );
    final model = chat.availableChatModels.firstWhere(
      (ref) => ref.serverAddress == _address && ref.model == 'account-model',
    );
    await chat.setChatModel(model);
    // The composer reports the applied model; setChatModel prints it right
    // here, so the visible selection is the evidence that it took effect.
    expect(chat.selectedChatModel?.model, 'account-model');

    expect(await chat.sendMessage('Hello', []), isTrue);
    final call = gateway.calls.single;
    expect(call.configuration.protocol, ApiProtocol.openaiCompatible);
    expect(call.configuration.apiOrigin, '$_address/v1');
    expect(call.configuration.apiKey, 'memory-token');
    // The account model selected through the composer answers, not the default.
    expect(call.configuration.model, 'account-model');
    expect(
      call.redirects,
      isFalse,
      reason: 'an account token must not follow a redirect',
    );

    await _settle(chat, whileRunning: () => call.complete('Answer'));
    final reply = chat.activeSession!.visibleMessages.last as AssistantMessage;
    expect(reply.modelReference?.serverAddress, _address);
    expect(reply.toJson().toString(), isNot(contains('memory-token')));
  });

  test(
    'a normal server setup never silently uses the hand-filled key',
    () async {
      final gateway = _Gateway();
      final chat = await _signedIn(gateway: gateway);
      // A saved connection exists, but the account model is what answers. The
      // manual key never travels unless it was the advanced path in use.
      chat.settings.modelConfiguration = const ModelConfiguration(
        apiKey: 'manual-key',
        model: 'manual-model',
      );
      chat.settings.serverAddress = _address;
      final accountModel = chat.availableChatModels.firstWhere(
        (ref) => ref.serverAddress == _address && ref.model == 'account-model',
      );
      await chat.setChatModel(accountModel);

      expect(await chat.sendMessage('Hello', []), isTrue);
      final call = gateway.calls.single;
      expect(call.configuration.apiKey, 'memory-token');
      expect(call.configuration.model, 'account-model');
      await _settle(chat, whileRunning: () => call.complete('Answer'));
    },
  );

  test(
    'a saved server address does not require sign-in for a manual key',
    () async {
      final gateway = _Gateway();
      final chat = ChatController(
        chatGateway: gateway,
        settingsStore: _MemorySettings(),
        sessionStore: _MemoryStore(),
        accountClient: _signedInAccount(),
      );
      addTearDown(chat.dispose);
      await chat.init();
      await chat.setServerAddress(_address);
      expect(chat.account.token, isNull);
      chat.settings.modelConfiguration = const ModelConfiguration(
        apiKey: 'manual-key',
      );
      await chat.setChatModel(
        const ChatModelRef(
          'deepseek-flash',
          manualSource: 'deepseek:https://api.deepseek.com',
        ),
      );

      expect(await chat.sendMessage('Hello', []), isTrue);
      final call = gateway.calls.single;
      expect(call.configuration.apiKey, 'manual-key');
      await _settle(chat, whileRunning: () => call.complete('Answer'));
      // The manual path keeps the transport it had: redirects stay enabled.
      expect(
        call.redirects,
        isTrue,
        reason: 'hand-filled endpoints keep redirect support',
      );
    },
  );

  test(
    'switching the saved server revokes the account and its models',
    () async {
      final chat = await _signedIn();
      expect(chat.account.token, 'memory-token');
      await chat.setServerAddress('https://other.example');
      expect(chat.account.token, isNull);
      expect(chat.account.address, isNull);
      expect(chat.settings.serverAddress, 'https://other.example');
      expect(
        chat.availableChatModels.any((ref) => ref.serverAddress == _address),
        isFalse,
      );
    },
  );

  test(
    'an old room cannot rebind its model to another signed-in server',
    () async {
      final gateway = _Gateway();
      final chat = await _signedIn(gateway: gateway);
      const oldModel = ChatModelRef('account-model', serverAddress: _address);
      await chat.setChatModel(oldModel);
      expect(await chat.sendMessage('Original', []), isTrue);
      await _settle(
        chat,
        whileRunning: () => gateway.calls.single.complete('Reply'),
      );
      final session = chat.activeSession!;
      final user = session.visibleMessages.first as UserMessage;
      final reply = session.visibleMessages.last as AssistantMessage;
      const other = 'https://other.example';
      await chat.setServerAddress(other);
      await chat.account.authenticate(
        other,
        username: 'alice',
        password: 'secret',
        register: false,
      );

      expect(chat.hasConnectionFor('Next'), isFalse);
      expect(await chat.sendMessage('Next', []), isFalse);
      expect(await chat.editPrompt(user.id, 'Edited', []), isFalse);
      expect(await chat.regenerate(reply.id), isFalse);
      expect(chat.selectedChatModel, oldModel);
      expect(session.visibleMessages.map((message) => message.id), [
        user.id,
        reply.id,
      ]);
      expect(gateway.calls, hasLength(1));
    },
  );

  test(
    'a server address alone does not connect a chat',
    () async {
      final gateway = _Gateway();
      final chat = await _signedIn(gateway: gateway);
      chat.account.clearSession();
      expect(chat.hasChatConnection, isFalse);
      expect(await chat.sendMessage('Do not send', []), isFalse);
      expect(gateway.calls, isEmpty);
    },
  );

  test('setServerAddress stores the address only', () async {
    final settings = _MemorySettings();
    final chat = await _signedIn(settingsStore: settings);
    await chat.setServerAddress('  https://server.example/  ');
    expect(settings.address, 'https://server.example/');
  });

  test('a retry reuses the server and model of the reply', () async {
    final gateway = _Gateway();
    final chat = await _signedIn(gateway: gateway);
    final model = chat.availableChatModels.firstWhere(
      (ref) => ref.model == 'account-model' && ref.serverAddress != null,
    );
    await chat.setChatModel(model);
    await chat.sendMessage('Hello', []);
    await _settle(
      chat,
      whileRunning: () => gateway.calls.first.complete('First'),
    );

    // The user selects another model afterwards; the retry must not follow it.
    await chat.setChatModel(
      ChatModelRef('second-model', serverAddress: _address),
    );
    final reply = chat.activeSession!.visibleMessages.last as AssistantMessage;
    expect(await chat.regenerate(reply.id), isTrue);
    final retry = gateway.calls.last;
    expect(retry.configuration.model, 'account-model');
    expect(retry.configuration.apiKey, 'memory-token');
    await _settle(chat, whileRunning: () => retry.complete('Second'));

    // After logging out the server reply cannot fall back to another server.
    chat.account.clearSession();
    final retried =
        chat.activeSession!.visibleMessages.last as AssistantMessage;
    expect(await chat.regenerate(retried.id), isFalse);
  });

  test('draft and saved chat remember a separate persona per mode', () async {
    final gateway = _Gateway();
    final chat = await _signedIn(gateway: gateway);
    await chat.setChatPersona('companion');
    await chat.setChatMode(ChatMode.work);
    expect(chat.chatPersonaOverride, isNull);
    await chat.setChatPersona('engineer');
    await chat.setChatMode(ChatMode.chat);
    expect(chat.chatPersonaOverride, 'companion');

    expect(await chat.sendMessage('Hello', []), isTrue);
    await _settle(
      chat,
      whileRunning: () => gateway.calls.single.complete('Hi'),
    );
    expect(chat.activeSession!.chatPersonaId, 'companion');
    await chat.setChatMode(ChatMode.work);
    expect(chat.chatPersonaOverride, 'engineer');
    final saved = ChatSession.fromJson(chat.activeSession!.toJson())!;
    expect(saved.chatPersonaId, 'companion');
    expect(saved.workPersonaId, 'engineer');

    chat.newChat();
    expect(chat.chatPersonaOverride, isNull);
    await chat.setChatMode(ChatMode.work);
    expect(chat.chatPersonaOverride, isNull);
  });

  test('legacy history without a reference keeps the manual behaviour', () async {
    final gateway = _Gateway();
    final chat = await _signedIn(gateway: gateway);
    chat.settings.modelConfiguration = const ModelConfiguration(
      apiKey: 'manual-key',
    );
    final reply = AssistantMessage(
      id: 'old',
      createdAt: 2,
      status: ReplyStatus.done,
      stopReason: StopReason.maxTokens,
      blocks: [TextBlock(text: 'Older answer')],
    );
    final session = ChatSession(id: 'legacy', createdAt: 1, updatedAt: 2);
    appendBranch(session, null, [
      UserMessage(id: 'u', createdAt: 1, content: 'Question'),
      reply,
    ]);
    chat.restoreSession(session);
    expect(await chat.continueReply('old'), isTrue);
    expect(gateway.calls, hasLength(1));
    // The continuation reports that it is working before the first token, even
    // though it keeps the text that is already visible.
    final pending =
        chat.activeSession!.visibleMessages.last as AssistantMessage;
    expect(pending.isStreaming, isTrue);
    expect(pending.text, 'Older answer');
    await _settle(
      chat,
      whileRunning: () => gateway.calls.last.complete(' more'),
    );
    expect(
      (chat.activeSession!.visibleMessages.last as AssistantMessage)
          .modelReference
          ?.manualSource,
      isNotNull,
    );
  });

  test(
    'local members and global profiles share mentions and one batch',
    () async {
      final gateway = _Gateway();
      final chat = await _signedIn(gateway: gateway);
      final address = chat.account.address;
      await chat.setRoomMembers(
        const [
          ChatMember(
            'room-a',
            '小满',
            ChatModelRef('account-model', serverAddress: _address),
          ),
          ChatMember(
            'room-b',
            '阿澈',
            ChatModelRef('second-model', serverAddress: _address),
          ),
        ],
        const ['room-a', 'room-b'],
      );
      expect(chat.chatMembers.length, 2);
      expect(chat.selectedChatMemberIds, ['room-a', 'room-b']);
      expect(address, isNotNull);

      // No mention: both members answer in the same turn.
      expect(await chat.sendMessage('所有人都在吗', []), isTrue);
      expect(gateway.calls.length, 2);
      expect(chat.activeStreaming, isTrue);

      // Mentions pick only the named member, by @name and by @{id}.
      final first = gateway.calls[0];
      final second = gateway.calls[1];
      await Future.wait([first.complete('我在'), second.complete('在的')]);
      await _settle(chat);

      final mentionSent = await chat.sendMessage('@小满 你怎么看', []);
      expect(mentionSent, isTrue);
      expect(gateway.calls.length, 3);
      expect(gateway.calls.last.configuration.model, 'account-model');
      await _settle(
        chat,
        whileRunning: () => gateway.calls.last.complete('看法'),
      );

      expect(await chat.sendMessage('@{room-b} 补充一下', []), isTrue);
      expect(gateway.calls.length, 4);
      expect(gateway.calls.last.configuration.model, 'second-model');
      await _settle(
        chat,
        whileRunning: () => gateway.calls.last.complete('补充'),
      );

      final shared = gateway.calls[3].request.history
          .whereType<AssistantMessage>();
      expect(shared.map((reply) => reply.text).join(), contains('我在'));
      expect(chat.activeSession!.members.map((member) => member.name), [
        '小满',
        '阿澈',
      ]);
    },
  );

  test(
    'the first draft keeps its room, and the next draft starts clean',
    () async {
      final gateway = _Gateway();
      final chat = await _signedIn(gateway: gateway);
      await chat.setRoomMembers(
        const [
          ChatMember(
            'room-a',
            '小满',
            ChatModelRef('account-model', serverAddress: _address),
          ),
        ],
        const ['room-a'],
      );
      expect(await chat.sendMessage('你好', []), isTrue);
      // The room travels into the session with the first message.
      final session = chat.activeSession!;
      expect(session.members.single.name, '小满');
      expect(session.selectedMemberIds, ['room-a']);
      await _settle(
        chat,
        whileRunning: () => gateway.calls.single.complete('在'),
      );
      expect(chat.activeSession!.members.single.name, '小满');
      expect(chat.activeSession!.selectedMemberIds, ['room-a']);

      chat.newChat();
      expect(chat.chatMembers, isEmpty);
      expect(chat.selectedChatMemberIds, isEmpty);
      expect(chat.draftKey, '__new__');
      // The global default assistant still answers on its own.
      expect(await chat.sendMessage('新的问题', []), isTrue);
      expect(gateway.calls.length, 2);
      await _settle(
        chat,
        whileRunning: () => gateway.calls.last.complete('回答'),
      );
    },
  );

  test('onMessageAccepted fires after the user message without waiting for replies', () async {
    final gateway = _Gateway();
    final chat = await _signedIn(gateway: gateway);
    var accepted = 0;
    chat.onMessageAccepted = () async {
      accepted++;
    };
    // Feedback runs after the message is appended and never waits for the
    // stream; the reply is still pending when the counter has moved.
    expect(await chat.sendMessage('开始', []), isTrue);
    await _advance(Duration.zero);
    expect(accepted, 1);
    // The reply is still streaming: the cue did not wait for it.
    expect(chat.activeStreaming, isTrue);
    expect(
      (chat.activeSession!.visibleMessages.whereType<UserMessage>().single)
          .content,
      '开始',
    );
    await _settle(
      chat,
      whileRunning: () => gateway.calls.single.complete('完成'),
    );
    expect(accepted, 1);

    // A rejected message never reports acceptance.
    chat.onMessageAccepted = () async {
      accepted++;
    };
    expect(await chat.sendMessage('   ', []), isFalse);
    expect(accepted, 1);
  });

  test('a running conversation keeps its saved connection', () async {
    final notebook = _NotebookSettings();
    final gateway = _Gateway();
    final chat = ChatController(
      chatGateway: gateway,
      settingsStore: notebook,
      sessionStore: _MemoryStore(),
      accountClient: _signedInAccount(),
    );
    addTearDown(chat.dispose);
    await chat.init();
    await chat.saveModelConfiguration(
      const ModelConfiguration(
        protocol: ApiProtocol.openaiCompatible,
        apiOrigin: 'https://first.example/v1',
        apiKey: 'first-key',
        model: 'first-model',
      ),
    );
    expect(await chat.sendMessage('Hello', []), isTrue);
    final call = gateway.calls.single;
    expect(call.configuration.apiKey, 'first-key');
    expect(call.configuration.model, 'first-model');
    await _settle(chat, whileRunning: () => call.complete('Ready'));
    expect(notebook.saved, hasLength(1));
  });

  test('the default assistant is not borrowed as a room member', () async {
    final gateway = _Gateway();
    final chat = await _signedIn(gateway: gateway);
    const ref = ChatModelRef('account-model', serverAddress: _address);
    await chat.setChatModel(ref);
    // No member and no profile is selected, so the default assistant answers.
    expect(await chat.sendMessage('Hello', []), isTrue);
    final reply = chat.activeSession!.visibleMessages.last as AssistantMessage;
    expect(reply.participantId, isNull);
    expect(reply.participantName, isNull);
    await _settle(
      chat,
      whileRunning: () => gateway.calls.single.complete('Hi'),
    );

    // Selecting a member with the same model routes to that member instead.
    await chat.setRoomMembers(
      const [ChatMember('room-a', '小满', ref)],
      const ['room-a'],
    );
    expect(await chat.sendMessage('Hi again', []), isTrue);
    final routed = chat.activeSession!.visibleMessages.last as AssistantMessage;
    expect(routed.participantId, 'room-a');
    expect(routed.participantName, '小满');
    await _settle(
      chat,
      whileRunning: () => gateway.calls.last.complete('Hello'),
    );
  });

  test(
    'the assistant menu model is applied immediately and remembered',
    () async {
      final settings = _MemorySettings();
      final chat = await _signedIn(settingsStore: settings);
      final ref = ChatModelRef('second-model', serverAddress: _address);
      await chat.setChatModel(ref);
      expect(chat.selectedChatModel, ref);
      expect(settings.chatModel, ref);
      expect(settings.chatModel?.manualSource, isNull);

      // A new draft starts from the same account models the menu offered.
      chat.newChat();
      expect(
        chat.availableChatModels.map((entry) => entry.model),
        containsAll(['account-model', 'second-model']),
      );
      expect(chat.selectedChatModel?.serverAddress, _address);
    },
  );
}
