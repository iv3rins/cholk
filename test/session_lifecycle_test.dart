import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/api/api_client.dart';
import 'package:deepseek_chat/api/api_types.dart';
import 'package:deepseek_chat/api/chat_gateway.dart';
import 'package:deepseek_chat/chat/chat_request.dart';
import 'package:deepseek_chat/models/chat_models.dart';
import 'package:deepseek_chat/models/chat_participant.dart';
import 'package:deepseek_chat/models/model_configuration.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/storage/session_store.dart';

class _DelayedStore extends SessionStore {
  final started = Completer<void>();
  final release = Completer<void>();
  int reads = 0;

  @override
  Future<ChatSession?> loadSession(String id) async {
    reads++;
    final result = await super.loadSession(id);
    if (!started.isCompleted) started.complete();
    await release.future;
    return result;
  }
}

class _RecordingGateway extends ChatGateway {
  _RecordingGateway()
    : super(
        legacyClient: ApiClient(),
        readAttachment: (_) async => Uint8List(0),
      );

  final requestedModels = <String>[];
  ApiException? failure;

  @override
  Stream<ApiEvent> stream({
    required ModelConfiguration configuration,
    required ChatRequest request,
    required CancelToken cancelToken,
    void Function()? onAttachmentChanged,
    bool followRedirects = true,
  }) async* {
    requestedModels.add(configuration.model);
    final error = failure;
    if (error != null) throw error;
    yield const ContentBlockStartEvent(
      index: 0,
      block: {'type': 'text', 'text': 'A reply'},
    );
    yield const MessageDeltaEvent(stopReason: StopReason.endTurn);
    yield const MessageStopEvent();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'cholk-session-',
    );
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => temporaryDirectory.path,
    );
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> finishSaving(ChatController controller) async {
    while (controller.hasRunningWork) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<ChatController> openController(
    SessionStore store, {
    _RecordingGateway? gateway,
    List<String> participantIds = const [],
  }) async {
    final session = ChatSession(
      id: 'existing',
      title: 'Old title',
      createdAt: 1,
      updatedAt: 1,
      selectedParticipantIds: participantIds,
    );
    await store.saveSession(session);
    await store.saveIndex([session.toSummary()]);
    final controller = ChatController(
      sessionStore: store,
      chatGateway: gateway,
    );
    addTearDown(() async {
      await finishSaving(controller);
      controller.dispose();
      await store.saveDrafts({});
    });
    await controller.init();
    expect(controller.initError, isFalse);
    return controller;
  }

  test('renaming an unopened chat persists in the conversation file', () async {
    final store = SessionStore();
    final controller = await openController(store);
    await controller.renameSession('existing', '  New title  ');

    expect(controller.activeId, isNull);
    expect((await SessionStore().loadSession('existing'))?.title, 'New title');
    expect((await SessionStore().loadIndex()).single.title, 'New title');
    await controller.selectSession('existing');
    expect(controller.activeSession?.title, 'New title');
  });

  test('loading a chat cannot put it back after deletion', () async {
    final store = _DelayedStore();
    final controller = await openController(store);
    final opening = controller.selectSession('existing');
    await store.started.future;
    await controller.deleteSession('existing');
    store.release.complete();
    await opening;

    expect(controller.activeId, isNull);
    expect(controller.cachedSession('existing'), isNull);
    expect(controller.summaries, isEmpty);
  });

  test('sending while a saved room opens uses that room recipients', () async {
    final store = _DelayedStore();
    final gateway = _RecordingGateway();
    final controller = await openController(
      store,
      gateway: gateway,
      participantIds: ['room-model'],
    );
    const configuration = ModelConfiguration(
      apiOrigin: 'https://models.example/v1',
      apiKey: 'test-key',
      model: 'manual-default',
      protocol: ApiProtocol.openaiCompatible,
    );
    await controller.saveModelConfiguration(configuration);
    await controller.saveParticipant(
      ChatParticipant(
        id: 'room-model',
        name: 'Room model',
        configuration: configuration.copyWith(model: 'configured-for-room'),
      ),
    );

    final opening = controller.selectSession('existing');
    await store.started.future;
    final sending = controller.sendMessage('Hello', []);
    store.release.complete();
    await opening;

    expect(await sending, isTrue);
    expect(gateway.requestedModels, ['configured-for-room']);
    expect(store.reads, 1);
  });

  test('a queued save cannot recreate a session after deletion', () async {
    final store = SessionStore();
    final session = ChatSession(id: 'existing', createdAt: 1, updatedAt: 1);
    await store.saveSession(session);

    final saving = store.saveSession(session..title = 'Updated title');
    final deleting = store.deleteSession(session.id);
    await Future.wait([saving, deleting]);

    expect(await store.loadSession(session.id), isNull);
  });

  test('fallback title flattens and limits the first question', () async {
    final gateway = _RecordingGateway();
    final controller = await openController(SessionStore(), gateway: gateway);
    await controller.setApiKey('test-key');
    controller.newChat();
    expect(
      await controller.sendMessage(
        '0123456789\nabcdefghij klmnopqrst UVWXYZ',
        [],
      ),
      isTrue,
    );
    await finishSaving(controller);
    expect(controller.activeSession!.title, '0123456789 abcdefghij klmnopqr…');
    expect(gateway.requestedModels, hasLength(1));
  });

  test(
    'Chinese reply errors explain connection, protocol, and request limits',
    () async {
      final gateway = _RecordingGateway();
      final controller = await openController(SessionStore(), gateway: gateway);
      await controller.setLocale('zh-CN');
      await controller.setApiKey('test-key');

      for (final (error, message) in [
        (ApiException('network', ''), '网络连接失败，请检查网络后重试'),
        (ApiException('protocol', ''), '模型服务返回了异常响应，请重试。'),
        (
          ApiException('http', '', status: 413),
          '请求超过服务端大小限制。请缩短消息、减少附件，或开启新对话后重试。',
        ),
      ]) {
        controller.newChat();
        gateway.failure = error;
        expect(await controller.sendMessage('Hello', []), isTrue);
        await finishSaving(controller);

        final reply =
            controller.activeSession!.visibleMessages.last as AssistantMessage;
        expect(reply.error?.localMessage, message);
      }
    },
  );
}
