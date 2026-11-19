import 'dart:convert';

import 'package:dio/dio.dart';

import '../../chat/attachments.dart';
import '../../chat/chat_request.dart';
import '../../chat/context_builder.dart';
import '../../models/chat_models.dart';
import '../../models/model_configuration.dart';
import '../api_client.dart';
import '../api_types.dart';

/// OpenAI Chat Completions wire adapter. Generic text files are read locally;
/// media is sent inline, so DeepSeek file IDs never cross provider boundaries.
class OpenAiProvider {
  OpenAiProvider(this._client, this._readAttachment);

  final ApiClient _client;
  final AttachmentReader _readAttachment;

  Stream<ApiEvent> stream({
    required ModelConfiguration configuration,
    required ChatRequest request,
    required CancelToken cancelToken,
    void Function()? onAttachmentChanged,
    bool followRedirects = true,
  }) async* {
    final messages = <Map<String, dynamic>>[
      if (request.systemPrompt.isNotEmpty)
        {'role': 'system', 'content': request.systemPrompt},
    ];
    var hasAudio = false;
    final prepared = <String, Map<String, dynamic>>{};

    Future<Map<String, dynamic>> userMessage(UserMessage user) async {
      final content = <Map<String, dynamic>>[];
      for (final file in user.files) {
        final extension = fileExtension(file.name);
        if (compatibleAudioExtensions.contains(extension)) hasAudio = true;
        content.add(
          prepared[file.id] ??= await _attachmentPart(
            file,
            configuration,
            cancelToken,
            onAttachmentChanged,
          ),
        );
      }
      if (user.content.isNotEmpty) {
        content.add({'type': 'text', 'text': user.content});
      }
      return {
        'role': 'user',
        'content': user.files.isEmpty ? user.content : content,
      };
    }

    for (final (user, assistant) in contextRounds(request.history)) {
      final text = _assistantText(assistant);
      if ((user.content.isNotEmpty || user.files.isNotEmpty) &&
          text.isNotEmpty) {
        messages
          ..add(await userMessage(user))
          ..add({'role': 'assistant', 'content': text});
      }
    }
    messages.add(await userMessage(request.question));
    final prefix = request.prefix;
    if (prefix != null && _assistantText(prefix).isNotEmpty) {
      messages
        ..add({'role': 'assistant', 'content': _assistantText(prefix)})
        ..add({'role': 'user', 'content': 'Continue the previous answer.'});
    }
    final reminder = request.latestReminder;
    if (reminder != null && reminder.isNotEmpty) {
      messages.insert(messages.length - 1, {
        'role': 'system',
        'content': 'Context: $reminder',
      });
    }
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;

    var started = false;
    var nextIndex = 0;
    int? textIndex;
    int? thinkingIndex;
    StopReason? stopReason;
    MessageUsage? usage;
    var producedContent = false;
    await for (final frame in _client.streamEvents(
      path: '/chat/completions',
      body: {
        'model': configuration.model.trim(),
        'messages': messages,
        'stream': true,
        'stream_options': {'include_usage': true},
        if (hasAudio) 'modalities': ['text'],
      },
      headers: {'Authorization': 'Bearer ${configuration.apiKey.trim()}'},
      cancelToken: cancelToken,
      followRedirects: followRedirects,
    )) {
      if (frame.data.trim().isEmpty) continue;
      if (frame.data.trim() == '[DONE]') {
        if (!started || (!producedContent && stopReason == null)) {
          throw ApiException('protocol', 'The model returned an empty stream');
        }
        if (thinkingIndex != null) {
          yield ContentBlockStopEvent(index: thinkingIndex);
        }
        if (textIndex != null) yield ContentBlockStopEvent(index: textIndex);
        yield MessageDeltaEvent(
          stopReason: stopReason ?? StopReason.endTurn,
          usage: usage,
        );
        yield const MessageStopEvent();
        return;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(frame.data);
      } on FormatException {
        throw ApiException('protocol', 'Invalid Chat Completions stream data');
      }
      final error = apiErrorMessage(decoded);
      if (error != null) throw ApiException('stream', error);
      if (frame.event == 'error') throw ApiException('stream', frame.data);
      if (decoded is! Map || decoded['choices'] is! List) {
        throw ApiException('protocol', 'Expected a Chat Completions chunk');
      }
      if (!started) {
        started = true;
        yield MessageStartEvent(
          id: decoded['id'] is String ? decoded['id'] as String : newId(),
          model: decoded['model'] is String
              ? decoded['model'] as String
              : configuration.model,
        );
      }
      usage = _usage(decoded['usage']) ?? usage;
      final choices = decoded['choices'] as List;
      for (final choice in choices) {
        if (choice is! Map || (choice['index'] ?? 0) != 0) continue;
        final delta = choice['delta'];
        if (delta is Map) {
          if (delta['tool_calls'] is List &&
              (delta['tool_calls'] as List).isNotEmpty) {
            throw ApiException(
              'unsupported',
              'Client tool calls are not configured',
            );
          }
          final thinking = delta['reasoning_content'] ?? delta['reasoning'];
          if (thinking is String && thinking.isNotEmpty) {
            producedContent = true;
            if (thinkingIndex == null) {
              thinkingIndex = nextIndex++;
              yield ContentBlockStartEvent(
                index: thinkingIndex,
                block: {'type': 'thinking', 'thinking': ''},
              );
            }
            yield ContentBlockDeltaEvent(
              index: thinkingIndex,
              delta: ApiDelta.thinking(thinking),
            );
          }
          final text = delta['content'] ?? delta['refusal'];
          if (text is String && text.isNotEmpty) {
            producedContent = true;
            if (textIndex == null) {
              textIndex = nextIndex++;
              yield ContentBlockStartEvent(
                index: textIndex,
                block: {'type': 'text', 'text': ''},
              );
            }
            yield ContentBlockDeltaEvent(
              index: textIndex,
              delta: ApiDelta.text(text),
            );
          }
        }
        final finish = choice['finish_reason'];
        if (finish != null) {
          if (finish == 'tool_calls' || finish == 'function_call') {
            throw ApiException(
              'unsupported',
              'Client tool calls are not configured',
            );
          }
          stopReason = finish == 'length'
              ? StopReason.maxTokens
              : finish == 'content_filter'
              ? StopReason.refusal
              : StopReason.endTurn;
          yield MessageDeltaEvent(stopReason: stopReason, usage: usage);
        }
      }
    }
    throw ApiException('interrupted', '');
  }

  Future<Map<String, dynamic>> _attachmentPart(
    FileAttachment file,
    ModelConfiguration configuration,
    CancelToken cancelToken,
    void Function()? onAttachmentChanged,
  ) async {
    final extension = fileExtension(file.name);
    final isText = textFileExtensions.contains(extension);
    final isImage = compatibleImageExtensions.contains(extension);
    final isPdf = extension == 'pdf';
    final isAudio = compatibleAudioExtensions.contains(extension);
    if ((!isText && !isImage && !isPdf && !isAudio) ||
        (isImage && !configuration.supportsImages) ||
        (isPdf && !configuration.supportsPdf) ||
        (isAudio && !configuration.supportsAudio)) {
      throw ApiException('unsupported', '当前模型不支持附件：${file.name}');
    }
    file
      ..status = AttachmentStatus.uploading
      ..error = null;
    onAttachmentChanged?.call();
    try {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final bytes = await _readAttachment(file);
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final Map<String, dynamic> part;
      if (isText) {
        final text = utf8.decode(bytes);
        part = {'type': 'text', 'text': 'File: ${file.name}\n\n$text'};
      } else if (isImage) {
        final mime = extension == 'jpg' || extension == 'jpeg'
            ? 'image/jpeg'
            : 'image/$extension';
        part = {
          'type': 'image_url',
          'image_url': {'url': 'data:$mime;base64,${base64Encode(bytes)}'},
        };
      } else if (isPdf) {
        part = {
          'type': 'file',
          'file': {
            'filename': file.name,
            'file_data': 'data:application/pdf;base64,${base64Encode(bytes)}',
          },
        };
      } else {
        part = {
          'type': 'input_audio',
          'input_audio': {'data': base64Encode(bytes), 'format': extension},
        };
      }
      file.status = AttachmentStatus.ready;
      return part;
    } catch (error) {
      if (error is DioException && CancelToken.isCancel(error)) {
        file.status = AttachmentStatus.ready;
        rethrow;
      }
      file
        ..status = AttachmentStatus.failed
        ..error = error.toString();
      if (error is FormatException) {
        throw ApiException('unsupported', '${file.name} 不是有效 UTF-8 文本文件');
      }
      if (error is ApiException) rethrow;
      throw ApiException('attachment', '读取附件失败 ${file.name}: $error');
    } finally {
      onAttachmentChanged?.call();
    }
  }
}

String _assistantText(AssistantMessage message) => message.blocks
    .whereType<TextBlock>()
    .map((block) => block.text)
    .join('\n\n');

MessageUsage? _usage(Object? value) {
  if (value is! Map) return null;
  int read(String key) => value[key] is num ? (value[key] as num).toInt() : 0;
  final details = value['prompt_tokens_details'];
  final cached = details is Map && details['cached_tokens'] is num
      ? (details['cached_tokens'] as num).toInt()
      : 0;
  final prompt = read('prompt_tokens');
  return MessageUsage(
    inputTokens: (prompt - cached).clamp(0, prompt).toInt(),
    cacheReadInputTokens: cached,
    outputTokens: read('completion_tokens'),
  );
}
