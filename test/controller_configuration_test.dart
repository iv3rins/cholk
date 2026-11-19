import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/api/api_client.dart';
import 'package:deepseek_chat/api/api_types.dart';
import 'package:deepseek_chat/api/chat_gateway.dart';
import 'package:deepseek_chat/chat/chat_request.dart';
import 'package:deepseek_chat/models/chat_models.dart';
import 'package:deepseek_chat/models/chat_preferences.dart';
import 'package:deepseek_chat/models/model_configuration.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/storage/session_store.dart';
import 'package:deepseek_chat/storage/settings_store.dart';
import 'package:deepseek_chat/storage/session_store_web.dart' as web;

class _MemoryStore extends SessionStore {
  @override
  Future<void> saveDrafts(Map<String, dynamic> data) async {}
  @override
  Future<void> saveSession(ChatSession session) async {}
  @override
  Future<void> saveIndex(List<SessionSummary> sessions) async {}
}

class _RecordingGateway extends ChatGateway {
  _RecordingGateway()
    : super(
        legacyClient: ApiClient(),
        readAttachment: (_) async => Uint8List(0),
      );

  final started = Completer<void>();
  final finish = Completer<void>();
  late ModelConfiguration captured;
  late ChatRequest capturedRequest;
  StopReason finishReason = StopReason.endTurn;
  ApiException? failure;

  @override
  Stream<ApiEvent> stream({
    required ModelConfiguration configuration,
    required ChatRequest request,
    required CancelToken cancelToken,
    void Function()? onAttachmentChanged,
    bool followRedirects = true,
  }) async* {
    captured = configuration;
    capturedRequest = request;
    started.complete();
    await finish.future;
    yield const ContentBlockStartEvent(
      index: 0,
      block: {'type': 'text', 'text': 'Ready'},
    );
    if (failure != null) throw failure!;
    yield MessageDeltaEvent(stopReason: finishReason);
    yield const MessageStopEvent();
  }
}

class _FailingSettingsStore extends SettingsStore {
  @override
  Future<void> saveModelConfiguration(ModelConfiguration value) async {
    throw StateError('Storage unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Chinese work mode leads with the conclusion', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _RecordingGateway()..finish.complete();
    final chat = ChatController(chatGateway: gateway, sessionStore: _MemoryStore());
    addTearDown(chat.dispose);
    chat.settings.modelConfiguration = const ModelConfiguration(apiKey: 'key');
    await chat.setChatMode(ChatMode.work);
    expect(await chat.sendMessage('整理计划', []), isTrue);
    await gateway.started.future;
    expect(gateway.capturedRequest.systemPrompt, contains('先给结论'));
    expect(gateway.capturedRequest.systemPrompt, isNot(contains('本地自动执行')));
  });

  test(
    'a running chat keeps its connection snapshot when settings change',
    () async {
      SharedPreferences.setMockInitialValues({});
      final gateway = _RecordingGateway();
      final controller = ChatController(
        chatGateway: gateway,
        sessionStore: _MemoryStore(),
      );
      addTearDown(controller.dispose);
      await controller.saveModelConfiguration(
        const ModelConfiguration(
          protocol: ApiProtocol.openaiCompatible,
          apiOrigin: 'https://first.example/v1',
          apiKey: 'first-key',
          model: 'first-model',
        ),
      );
      expect(await controller.sendMessage('Hello', []), isTrue);
      await gateway.started.future;

      await controller.saveModelConfiguration(
        const ModelConfiguration(
          apiOrigin: 'https://second.example',
          apiKey: 'second-key',
          model: 'second-model',
        ),
      );
      expect(gateway.captured.apiOrigin, 'https://first.example/v1');
      expect(gateway.captured.apiKey, 'first-key');
      expect(gateway.captured.model, 'first-model');
      expect(gateway.capturedRequest.systemPrompt, isNot(contains('DeepSeek')));

      final completed = Completer<void>();
      controller.addListener(() {
        if (!controller.activeStreaming && !completed.isCompleted) {
          completed.complete();
        }
      });
      gateway.finish.complete();
      await completed.future.timeout(const Duration(seconds: 2));
      final reply =
          controller.activeSession!.visibleMessages.last as AssistantMessage;
      expect(reply.text, 'Ready');
      expect(reply.model, 'first-model');
      expect(reply.status, ReplyStatus.done);
    },
  );

  test(
    'failed persistence does not change the active model configuration',
    () async {
      final controller = ChatController(
        settingsStore: _FailingSettingsStore(),
        sessionStore: _MemoryStore(),
      );
      addTearDown(controller.dispose);
      await expectLater(
        controller.saveModelConfiguration(
          const ModelConfiguration(apiKey: 'new-key', model: 'new-model'),
        ),
        throwsStateError,
      );
      expect(controller.settings.apiKey, isEmpty);
      expect(controller.settings.model, defaultModel);
    },
  );

  for (final refusal in [false, true]) {
    test(refusal ? 'a refused continuation preserves the previous answer' : 'an interrupted continuation cannot reuse the previous finish reason', () async {
      final gateway = _RecordingGateway();
      if (refusal) {
        gateway.finishReason = StopReason.refusal;
      } else {
        gateway.failure = ApiException('interrupted', '');
      }
      final controller = ChatController(
        chatGateway: gateway,
        sessionStore: _MemoryStore(),
      );
      addTearDown(controller.dispose);
      controller.settings.apiKey = 'key';
      final reply = AssistantMessage(
        id: 'assistant',
        createdAt: 1,
        status: ReplyStatus.done,
        stopReason: StopReason.maxTokens,
        blocks: [TextBlock(text: 'Previous answer')],
      );
      final session = ChatSession(id: 'session', createdAt: 1, updatedAt: 1);
      appendBranch(session, null, [
        UserMessage(id: 'user', createdAt: 1, content: 'Hello'),
        reply,
      ]);
      controller.restoreSession(session);
      expect(await controller.continueReply(), isTrue);
      await gateway.started.future;
      final completed = Completer<void>();
      controller.addListener(() {
        if (!controller.activeStreaming && !completed.isCompleted) {
          completed.complete();
        }
      });
      gateway.finish.complete();
      await completed.future.timeout(const Duration(seconds: 2));
      if (refusal) {
        expect(reply.text, 'Previous answer');
        expect(reply.stopReason, StopReason.refusal);
      } else {
        expect(reply.status, ReplyStatus.error);
        expect(reply.error?.kind, 'interrupted');
        expect(reply.text, contains('Previous answer'));
      }
    });
  }

  test(
    'web attachment reader restores bytes from the store after JSON roundtrip',
    () async {
      final store = web.SessionStore();
      final file = await store.importAttachmentBytes(
        bytes: Uint8List.fromList([1, 2, 3]),
        name: 'voice.wav',
        size: 3,
        isImage: false,
        mimeType: 'audio/wav',
      );
      file.serverOrigin = 'https://provider.example';
      final restored = FileAttachment.fromJson(file.toJson())!;
      expect(restored.bytes, isNull);
      expect(restored.serverOrigin, 'https://provider.example');
      expect(await store.readAttachment(restored), [1, 2, 3]);
      await store.deleteAttachmentFile(restored);
      await expectLater(store.readAttachment(restored), throwsStateError);
    },
  );
}
