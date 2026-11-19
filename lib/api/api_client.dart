import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_types.dart';
import 'sse.dart';

class ApiClient {
  ApiClient({this._origin = defaultApiOrigin, Dio? dio})
    : _useFetch = kIsWeb && dio == null,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 10),
              sendTimeout: const Duration(minutes: 10),
              // Every response is inspected manually so error bodies can surface.
              validateStatus: (_) => true,
              headers: {'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'},
            ),
          );

  ApiClient._(this._origin, this._dio, this._useFetch);

  final Dio _dio;
  final bool _useFetch;
  String _origin;

  String get origin => _origin;

  /// Each request keeps its own endpoint while sharing the HTTP connection
  /// pool. Changing settings during a stream cannot redirect its attachments.
  ApiClient forOrigin(String origin) => ApiClient._(origin, _dio, _useFetch);

  set origin(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return;
    }
    _origin = trimmed;
  }

  Uri _uri(String path) => Uri.parse('$_origin$path');

  Map<String, String> _anthropicHeaders(String apiKey, {bool files = false}) =>
      {'x-api-key': apiKey, if (files) 'anthropic-beta': filesBeta};

  /// Validates the key with GET /models, which does not consume tokens.
  Future<void> verifyApiKey(String apiKey, {CancelToken? cancelToken}) async {
    final response = await _guard(
      () => _dio.getUri<dynamic>(
        _uri('/models'),
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      ),
    );
    if (response.statusCode != 200) {
      throw _httpError(
        response.statusCode,
        response.statusMessage,
        response.data,
      );
    }
    if (response.data is! Map || (response.data as Map)['data'] is! List) {
      throw ApiException('protocol', 'Expected a model list response');
    }
  }

  Future<UploadedFile> uploadFile({
    required String apiKey,
    String? filePath,
    Uint8List? bytes,
    required String name,
    required String mimeType,
    String? purpose,
    CancelToken? cancelToken,
  }) async {
    if (bytes == null && (filePath == null || filePath.isEmpty)) {
      throw ApiException('attachment', 'Attachment bytes or path are required');
    }
    final form = FormData();
    if (purpose != null && purpose.isNotEmpty) {
      form.fields.add(MapEntry('purpose', purpose));
    }
    form.files.add(
      MapEntry(
        'file',
        bytes != null
            ? MultipartFile.fromBytes(
                bytes,
                filename: name,
                contentType: MediaType.parse(
                  mimeType.isEmpty ? 'application/octet-stream' : mimeType,
                ),
              )
            : await MultipartFile.fromFile(
                filePath!,
                filename: name,
                contentType: MediaType.parse(
                  mimeType.isEmpty ? 'application/octet-stream' : mimeType,
                ),
              ),
      ),
    );

    final response = await _guard(
      () => _dio.postUri<dynamic>(
        _uri('/anthropic/v1/files'),
        data: form,
        options: Options(
          headers: _anthropicHeaders(apiKey, files: true),
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      ),
    );
    if (response.statusCode != 200) {
      throw _httpError(
        response.statusCode,
        response.statusMessage,
        response.data,
      );
    }
    final uploaded = UploadedFile.fromJson(response.data);
    if (uploaded == null) {
      throw ApiException(
        'protocol',
        response.data is String
            ? response.data as String
            : 'Invalid file response',
      );
    }
    return uploaded;
  }

  Future<void> deleteFile({
    required String apiKey,
    required String fileId,
    CancelToken? cancelToken,
  }) async {
    final response = await _guard(
      () => _dio.deleteUri<dynamic>(
        _uri('/anthropic/v1/files/${Uri.encodeComponent(fileId)}'),
        options: Options(
          headers: _anthropicHeaders(apiKey, files: true),
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      ),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw _httpError(
        response.statusCode,
        response.statusMessage,
        response.data,
      );
    }
  }

  /// Sends a message and yields parsed SSE events until `message_stop`.
  Stream<ApiEvent> streamMessage({
    required String apiKey,
    required Map<String, dynamic> body,
    required CancelToken cancelToken,
  }) async* {
    await for (final sse in streamEvents(
      path: '/anthropic/v1/messages',
      body: {...body, 'stream': true},
      headers: _anthropicHeaders(apiKey, files: _hasFile(body)),
      cancelToken: cancelToken,
    )) {
      Object? payload;
      try {
        payload = jsonDecode(sse.data);
      } catch (_) {
        if (sse.event != 'error') continue;
      }
      final errorMessage = apiErrorMessage(payload);
      if (errorMessage != null) {
        throw ApiException('stream', errorMessage);
      }
      if (sse.event == 'error') {
        throw ApiException('stream', sse.data);
      }
      final event = parseApiEvent(payload);
      if (event == null) continue;
      yield event;
      if (event is MessageStopEvent) return;
    }
    throw ApiException('interrupted', '');
  }

  /// HTTP and SSE transport shared by the protocol adapters. It deliberately
  /// leaves payload parsing and completion markers to each provider.
  ///
  /// [followRedirects] is off for requests that carry an account credential: a
  /// redirect could route a bearer token to another host. Callers that rely on
  /// a user-configured base URL keep Dio's default redirect handling.
  Stream<SseEvent> streamEvents({
    required String path,
    required Map<String, dynamic> body,
    required Map<String, String> headers,
    required CancelToken cancelToken,
    bool followRedirects = true,
  }) async* {
    final requestHeaders = {...headers, 'Accept': 'text/event-stream'};
    final payload = jsonEncode(body);
    final webClient = _useFetch ? http.Client() : null;
    try {
      final response = webClient == null
          ? (await _dio.postUri<ResponseBody>(
              _uri(path),
              data: payload,
              options: Options(
                responseType: ResponseType.stream,
                contentType: 'application/json',
                headers: requestHeaders,
                validateStatus: (_) => true,
                followRedirects: followRedirects,
              ),
              cancelToken: cancelToken,
            )).data
          : await _fetchEventStream(
              webClient,
              _uri(path),
              payload,
              requestHeaders,
              cancelToken,
              followRedirects: followRedirects,
            );
      if (response == null) {
        throw ApiException('protocol', 'Empty response body');
      }
      yield* _eventStream(response, cancelToken);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw ApiException('network', _networkMessage(error));
    } on http.ClientException catch (error) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      throw ApiException('network', error.message);
    } on TimeoutException {
      throw ApiException('network', 'Event stream timed out');
    } finally {
      webClient?.close();
    }
  }

  /// Applies the status, content-type and SSE checks to one response. It stays
  /// a separate generator so [streamEvents] keeps translating transport errors
  /// through the same catch blocks as before.
  Stream<SseEvent> _eventStream(
    ResponseBody response,
    CancelToken cancelToken,
  ) async* {
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      final text = await _readStream(response.stream);
      throw _httpError(status, response.statusMessage, text);
    }
    final contentType =
        response.headers[Headers.contentTypeHeader]?.join(',') ?? '';
    if (!contentType.contains('text/event-stream')) {
      final text = await _readStream(response.stream);
      throw ApiException(
        'protocol',
        text.isNotEmpty ? text : 'Expected an event stream',
        status: status,
      );
    }
    yield* parseSse(response.stream);
  }

  // Dio's browser XHR adapter buffers through onLoad, even for a stream.
  // Fetch exposes incoming bytes as they arrive; keep other requests on Dio.
  Future<ResponseBody> _fetchEventStream(
    http.Client client,
    Uri uri,
    String body,
    Map<String, String> headers,
    CancelToken cancelToken, {
    bool followRedirects = true,
  }) async {
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    final request =
        http.AbortableRequest('POST', uri, abortTrigger: cancelToken.whenCancel)
          // `followRedirects` is a settable field on BaseRequest, not a
          // constructor argument, so it is assigned before the request is sent.
          ..followRedirects = followRedirects
          ..headers.addAll({
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Content-Type': 'application/json',
            ...headers,
          })
          ..body = body;
    final timeout = _dio.options.receiveTimeout!;
    final response = await client.send(request).timeout(timeout);
    return ResponseBody(
      response.stream
          .map(
            (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
          )
          .timeout(
            timeout,
            onTimeout: (sink) {
              sink.addError(TimeoutException('Event stream timed out'));
              sink.close();
            },
          ),
      response.statusCode,
      statusMessage: response.reasonPhrase,
      headers: response.headers.map((key, value) => MapEntry(key, [value])),
    );
  }

  Future<String> transcribe({
    required String apiKey,
    required String filePath,
    required String fileName,
    required String mimeType,
    CancelToken? cancelToken,
  }) async {
    final form = FormData();
    form.files.add(
      MapEntry(
        'file',
        await MultipartFile.fromFile(
          filePath,
          filename: fileName,
          contentType: MediaType.parse(
            mimeType.isEmpty ? 'audio/wav' : mimeType,
          ),
        ),
      ),
    );
    final response = await _guard(
      () => _dio.postUri<dynamic>(
        _uri('/v1/tools/asr'),
        data: form,
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      ),
    );
    if (response.statusCode != 200) {
      throw _httpError(
        response.statusCode,
        response.statusMessage,
        response.data,
      );
    }
    final data = response.data;
    if (data is Map && data['text'] is String) {
      return data['text'] as String;
    }
    throw ApiException(
      'protocol',
      data is String ? data : 'Invalid transcription response',
    );
  }

  /// Returns raw PCM: 24 kHz, mono, 16-bit little-endian.
  Future<Uint8List> synthesize({
    required String apiKey,
    required String text,
    required String voice,
    CancelToken? cancelToken,
  }) async {
    final response = await _guard(
      () => _dio.postUri<ResponseBody>(
        _uri('/v1/tools/tts'),
        data: jsonEncode({
          'text': text,
          'voice_id': voice,
          'format': 'pcm',
          'filter_markdown': true,
        }),
        options: Options(
          responseType: ResponseType.stream,
          contentType: 'application/json',
          headers: {'Authorization': 'Bearer $apiKey'},
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      ),
    );
    if (response.statusCode != 200) {
      final text = response.data == null
          ? ''
          : await _readStream(response.data!.stream);
      throw _httpError(response.statusCode, response.statusMessage, text);
    }
    final stream = response.data?.stream;
    if (stream == null) {
      throw ApiException('protocol', 'Empty audio stream');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  bool _hasFile(Map<String, dynamic> body) {
    final messages = body['messages'];
    if (messages is! List) return false;
    for (final message in messages) {
      if (message is! Map) continue;
      final content = message['content'];
      if (content is! List) continue;
      for (final block in content) {
        if (block is Map &&
            (block['type'] == 'image' || block['type'] == 'document')) {
          return true;
        }
      }
    }
    return false;
  }

  Future<Response<T>> _guard<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw ApiException('network', _networkMessage(error));
    }
  }

  String _networkMessage(DioException error) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out';
      case DioExceptionType.receiveTimeout:
        return 'Response timed out';
      case DioExceptionType.sendTimeout:
        return 'Upload timed out';
      case DioExceptionType.connectionError:
        return 'Network connection failed';
      default:
        return error.error?.toString() ?? 'Network request failed';
    }
  }

  ApiException _httpError(int? status, String? statusMessage, Object? data) {
    String text = '';
    if (data is String) {
      text = data;
    } else if (data != null) {
      try {
        text = jsonEncode(data);
      } catch (_) {
        text = data.toString();
      }
    }
    final message =
        apiErrorMessage(data) ??
        (text.isNotEmpty ? text : (statusMessage ?? 'HTTP ${status ?? 0}'));
    return ApiException('http', message, status: status);
  }

  Future<String> _readStream(Stream<List<int>> stream) async {
    try {
      return await utf8.decodeStream(stream.map<List<int>>((chunk) => chunk));
    } catch (_) {
      return '';
    }
  }
}
