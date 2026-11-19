import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:deepseek_chat/api/api_client.dart';
import 'package:deepseek_chat/api/api_types.dart';
import 'package:deepseek_chat/api/chat_gateway.dart';
import 'package:deepseek_chat/api/sse.dart';
import 'package:deepseek_chat/chat/chat_request.dart';
import 'package:deepseek_chat/chat/reply_merge.dart';
import 'package:deepseek_chat/models/chat_models.dart';
import 'package:deepseek_chat/models/model_configuration.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configuration validates and round-trips capabilities', () {
    const compatible = ModelConfiguration(
      protocol: ApiProtocol.openaiCompatible,
    );
    expect(compatible.supportsImages, isFalse);
    expect(compatible.supportsPdf, isFalse);
    expect(compatible.supportsAudio, isFalse);
    expect(const ModelConfiguration().supportsImages, isTrue);
    const original = ModelConfiguration(
      protocol: ApiProtocol.openaiCompatible,
      apiOrigin: ' https://example.com/v1/ ',
      apiKey: ' key ',
      model: ' vision-audio ',
      supportsAudio: true,
    );
    final normalized = original.validated();
    expect(normalized.apiOrigin, 'https://example.com/v1');
    expect(normalized.apiKey, 'key');
    final restored = ModelConfiguration.fromJson(normalized.toJson());
    expect(restored.protocol, ApiProtocol.openaiCompatible);
    expect(restored.supportsAudio, isTrue);
    expect(restored.model, 'vision-audio');
    expect(
      () =>
          original.copyWith(apiOrigin: 'https://example.com/?x=1').validated(),
      throwsFormatException,
    );
  });

  test(
    'OpenAI serializes media and merges text, reasoning and final usage',
    () async {
      final captured = <Map<String, dynamic>>[];
      final server = await _serve((request) async {
        expect(request.uri.path, '/v1/chat/completions');
        expect(request.headers.value('authorization'), 'Bearer compatible-key');
        captured.add(
          jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>,
        );
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        for (final payload in [
          {
            'id': 'cmpl-1',
            'model': 'other-model',
            'choices': [
              {
                'index': 0,
                'delta': {'reasoning_content': 'plan'},
              },
            ],
          },
          {
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'answer'},
              },
            ],
          },
          {
            'choices': [
              {'index': 0, 'delta': {}, 'finish_reason': 'stop'},
            ],
          },
          {
            'choices': [],
            'usage': {
              'prompt_tokens': 12,
              'completion_tokens': 4,
              'prompt_tokens_details': {'cached_tokens': 5},
            },
          },
        ]) {
          request.response.write('data: ${jsonEncode(payload)}\n\n');
        }
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      final config = ModelConfiguration(
        protocol: ApiProtocol.openaiCompatible,
        apiOrigin: '${_origin(server)}/v1',
        apiKey: 'compatible-key',
        model: 'other-model',
        supportsImages: true,
        supportsPdf: true,
        supportsAudio: true,
      );
      final files = [
        _file('note.txt'),
        _file('picture.png', isImage: true),
        _file('report.pdf'),
        _file('voice.wav'),
      ];
      final gateway = ChatGateway(
        legacyClient: ApiClient(),
        readAttachment: (file) async =>
            Uint8List.fromList(utf8.encode('payload')),
      );
      final events = await gateway
          .stream(
            configuration: config,
            request: _request(
              files: files,
              latestReminder: DateTime.utc(2026, 11, 19).toIso8601String(),
            ),
            cancelToken: CancelToken(),
          )
          .toList();
      await gateway
          .stream(
            configuration: config,
            request: _request(
              files: files,
              latestReminder: DateTime.utc(2026, 11, 20).toIso8601String(),
            ),
            cancelToken: CancelToken(),
          )
          .drain<void>();
      final body = captured.first;
      expect(body['model'], 'other-model');
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('title'), isFalse);
      final messages = body['messages'] as List;
      expect(messages.map((message) => message['role']), [
        'system',
        'system',
        'user',
      ]);
      expect(messages.first['content'], _request().systemPrompt);
      final tomorrow = captured.last['messages'] as List;
      expect(tomorrow.first, messages.first);
      expect(tomorrow.last, messages.last);
      expect(messages[1]['content'], startsWith('Context: 2026-11-19'));
      expect(tomorrow[1]['content'], startsWith('Context: 2026-11-20'));
      final content = messages.last['content'] as List;
      expect(content[0], {'type': 'text', 'text': 'File: note.txt\n\npayload'});
      expect(
        content[1]['image_url']['url'],
        startsWith('data:image/png;base64,'),
      );
      expect(
        content[2]['file']['file_data'],
        startsWith('data:application/pdf;base64,'),
      );
      expect(content[3]['input_audio']['format'], 'wav');
      expect(jsonEncode(body), isNot(contains('old-deepseek-id')));
      final reply = AssistantMessage(
        id: 'a',
        createdAt: 1,
        status: ReplyStatus.streaming,
      );
      final indexes = <int, int>{};
      for (final event in events) {
        applyApiEvent(reply, event, 2, indexes);
      }
      expect(reply.blocks.whereType<TextBlock>().single.text, 'answer');
      expect(reply.blocks.whereType<ThinkingBlock>().single.thinking, 'plan');
      expect(reply.usage!.totalInputTokens, 12);
      expect(reply.usage!.outputTokens, 4);
      expect(reply.stopReason, StopReason.endTurn);
      expect(events.last, isA<MessageStopEvent>());
    },
  );

  test(
    'DeepSeek reuses IDs only for the same gateway, account and API origin',
    () async {
      var uploads = 0;
      Map<String, dynamic>? captured;
      final server = await _serve((request) async {
        if (request.uri.path.endsWith('/files')) {
          uploads++;
          final multipart = await utf8.decodeStream(request);
          expect(multipart, contains('filename="note.txt"'));
          expect(multipart, contains('hello file'));
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': 'file-$uploads',
              'filename': 'note.txt',
              'mime_type': 'text/plain',
              'size_bytes': 10,
            }),
          );
        } else {
          captured = jsonDecode(
            await utf8.decodeStream(request),
          ) as Map<String, dynamic>;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'data: {"type":"message_start","message":{"id":"m","model":"deepseek-flash"}}\n\n',
          );
          request.response.write(
            'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n',
          );
          request.response.write('data: {"type":"message_stop"}\n\n');
        }
        await request.response.close();
      });
      final file = _file('note.txt');
      final client = ApiClient(origin: 'https://unchanged.example');
      final gateway = ChatGateway(
        legacyClient: client,
        readAttachment: (_) async =>
            Uint8List.fromList(utf8.encode('hello file')),
      );
      var config = ModelConfiguration(
        apiOrigin: _origin(server),
        apiKey: 'deepseek-key',
      );
      Future<void> run() => gateway
          .stream(
            configuration: config,
            request: _request(files: [file]),
            cancelToken: CancelToken(),
          )
          .drain();
      await run();
      await run();
      expect(uploads, 1);
      expect(captured!['tools'], hasLength(2));
      expect(captured!['title'], {'enabled': true});
      expect((captured!['messages'] as List).first['role'], 'latest_reminder');
      config = config.copyWith(apiKey: 'another-account');
      await run();
      expect(uploads, 2);
      config = config.copyWith(apiOrigin: '${_origin(server)}/other');
      await run();
      expect(uploads, 3);
      expect(file.serverOrigin, config.apiOrigin);
      expect(client.origin, 'https://unchanged.example');
      final restartedGateway = ChatGateway(
        legacyClient: client,
        readAttachment: (_) async =>
            Uint8List.fromList(utf8.encode('hello file')),
      );
      await restartedGateway
          .stream(
            configuration: config,
            request: _request(files: [file]),
            cancelToken: CancelToken(),
          )
          .drain<void>();
      expect(uploads, 4);
    },
  );

  test(
    'unsupported media and invalid UTF-8 fail before an HTTP request',
    () async {
      var reads = 0;
      final gateway = ChatGateway(
        legacyClient: ApiClient(),
        readAttachment: (_) async {
          reads++;
          return Uint8List.fromList([255]);
        },
      );
      const config = ModelConfiguration(
        protocol: ApiProtocol.openaiCompatible,
        apiKey: 'key',
        supportsAudio: false,
      );
      await expectLater(
        gateway
            .stream(
              configuration: config,
              request: _request(files: [_file('voice.wav')]),
              cancelToken: CancelToken(),
            )
            .toList(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            'unsupported',
          ),
        ),
      );
      expect(reads, 0);
      final text = _file('bad.txt');
      await expectLater(
        gateway
            .stream(
              configuration: config,
              request: _request(files: [text]),
              cancelToken: CancelToken(),
            )
            .toList(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            'unsupported',
          ),
        ),
      );
      expect(text.status, AttachmentStatus.failed);
    },
  );

  test('cancelling preparation restores attachment status', () async {
    final token = CancelToken();
    final file = _file('note.txt');
    final gateway = ChatGateway(
      legacyClient: ApiClient(),
      readAttachment: (_) async {
        token.cancel('stop');
        return Uint8List(0);
      },
    );
    await expectLater(
      gateway
          .stream(
            configuration: const ModelConfiguration(apiKey: 'key'),
            request: _request(files: [file]),
            cancelToken: token,
          )
          .toList(),
      throwsA(
        isA<DioException>().having(CancelToken.isCancel, 'cancelled', isTrue),
      ),
    );
    expect(file.status, AttachmentStatus.ready);
  });

  test('verification rejects HTML with HTTP 200', () async {
    final server = await _serve((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html>wrong endpoint</html>');
      await request.response.close();
    });
    final gateway = ChatGateway(
      legacyClient: ApiClient(),
      readAttachment: (_) async => Uint8List(0),
    );
    await expectLater(
      gateway.verify(
        ModelConfiguration(apiOrigin: _origin(server), apiKey: 'key'),
      ),
      throwsA(
        isA<ApiException>().having((error) => error.kind, 'kind', 'protocol'),
      ),
    );
  });

  test('SSE event name resets even for an empty event', () async {
    final frames = await parseSse(
      Stream.value(utf8.encode('event: error\n\ndata: {}\n\n')),
    ).toList();
    expect(frames.single.event, isNull);
  });
}

Future<HttpServer> _serve(FutureOr<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen(handler);
  return server;
}

String _origin(HttpServer server) => 'http://127.0.0.1:${server.port}';

FileAttachment _file(String name, {bool isImage = false}) => FileAttachment(
  id: name,
  name: name,
  size: 10,
  isImage: isImage,
  mimeType: isImage ? 'image/png' : 'application/octet-stream',
  serverId: 'old-deepseek-id',
);

ChatRequest _request({
  List<FileAttachment> files = const [],
  AssistantMessage? prefix,
  String latestReminder = 'test-reminder',
}) => ChatRequest(
  history: const [],
  question: UserMessage(
    id: 'q',
    createdAt: 1,
    content: 'question',
    files: files,
  ),
  prefix: prefix,
  systemPrompt: 'You are a helpful assistant.',
  latestReminder: latestReminder,
  thinking: true,
  search: true,
  titleRequest: true,
);
