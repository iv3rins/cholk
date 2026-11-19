import '../models/chat_models.dart';
import '../models/model_configuration.dart';

export '../models/model_configuration.dart' show defaultApiOrigin, defaultModel;

const String systemPrompt =
    '你是 Cholk 对话中的 AI 助手。以用户的目标为先，清晰、准确地回答；'
    '区分已知事实、推断和不确定之处，不声称执行过没有执行的操作。';
const String systemPromptEn =
    'You are an AI assistant in Cholk. Answer clearly and accurately, focusing '
    'on the user’s goal. Distinguish facts, inferences, and uncertainty. '
    'Do not claim to have taken actions you did not take.';
const String filesBeta = 'files-api-2025-04-14';

class ApiException implements Exception {
  ApiException(this.kind, this.message, {this.status});

  /// http | stream | network | interrupted | protocol
  final String kind;
  final String message;
  final int? status;

  @override
  String toString() => message.isEmpty ? kind : message;
}

class UploadedFile {
  const UploadedFile({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String id;
  final String filename;
  final String mimeType;
  final int sizeBytes;

  static UploadedFile? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    if (id is! String) return null;
    return UploadedFile(
      id: id,
      filename: value['filename'] is String ? value['filename'] as String : '',
      mimeType: value['mime_type'] is String
          ? value['mime_type'] as String
          : '',
      sizeBytes: value['size_bytes'] is num
          ? (value['size_bytes'] as num).toInt()
          : 0,
    );
  }
}

enum ApiDeltaKind { text, thinking, signature, citation }

class ApiDelta {
  const ApiDelta.text(this.text) : kind = ApiDeltaKind.text, citation = null;
  const ApiDelta.thinking(this.text)
    : kind = ApiDeltaKind.thinking,
      citation = null;
  const ApiDelta.signature(this.text)
    : kind = ApiDeltaKind.signature,
      citation = null;
  const ApiDelta.citation(this.citation)
    : kind = ApiDeltaKind.citation,
      text = '';

  final ApiDeltaKind kind;
  final String text;
  final Citation? citation;
}

sealed class ApiEvent {
  const ApiEvent();
}

class MessageStartEvent extends ApiEvent {
  const MessageStartEvent({required this.id, required this.model, this.usage});
  final String id;
  final String model;
  final MessageUsage? usage;
}

class ContentBlockStartEvent extends ApiEvent {
  const ContentBlockStartEvent({required this.index, required this.block});
  final int index;
  final Map<String, dynamic> block;
}

class ContentBlockDeltaEvent extends ApiEvent {
  const ContentBlockDeltaEvent({required this.index, required this.delta});
  final int index;
  final ApiDelta delta;
}

class ContentBlockStopEvent extends ApiEvent {
  const ContentBlockStopEvent({required this.index});
  final int index;
}

class MessageDeltaEvent extends ApiEvent {
  const MessageDeltaEvent({
    required this.stopReason,
    this.stopDetails,
    this.title,
    this.usage,
  });
  final StopReason stopReason;
  final Map<String, dynamic>? stopDetails;
  final String? title;
  final MessageUsage? usage;
}

class MessageStopEvent extends ApiEvent {
  const MessageStopEvent();
}

ApiEvent? parseApiEvent(Object? value) {
  if (value is! Map) return null;
  final json = Map<String, dynamic>.from(value);
  switch (json['type']) {
    case 'message_start':
      final message = json['message'];
      if (message is! Map) return null;
      final id = message['id'];
      if (id is! String) return null;
      return MessageStartEvent(
        id: id,
        model: message['model'] is String
            ? message['model'] as String
            : defaultModel,
        usage: MessageUsage.fromJson(message['usage']),
      );
    case 'content_block_start':
      final index = json['index'];
      final block = json['content_block'];
      if (index is! int || block is! Map) return null;
      return ContentBlockStartEvent(
        index: index,
        block: Map<String, dynamic>.from(block),
      );
    case 'content_block_delta':
      final index = json['index'];
      final delta = json['delta'];
      if (index is! int || delta is! Map) return null;
      final typed = _parseDelta(delta);
      if (typed == null) return null;
      return ContentBlockDeltaEvent(index: index, delta: typed);
    case 'content_block_stop':
      final index = json['index'];
      if (index is! int) return null;
      return ContentBlockStopEvent(index: index);
    case 'message_delta':
      final delta = json['delta'];
      if (delta is! Map) return null;
      final rawReason = delta['stop_reason'];
      final reason = rawReason is String ? stopReasonFromWire(rawReason) : null;
      if (reason == null) return null;
      return MessageDeltaEvent(
        stopReason: reason,
        stopDetails: delta['stop_details'] is Map
            ? Map<String, dynamic>.from(delta['stop_details'] as Map)
            : null,
        title: delta['title'] is String ? delta['title'] as String : null,
        usage: MessageUsage.fromJson(json['usage']),
      );
    case 'message_stop':
      return const MessageStopEvent();
    default:
      return null;
  }
}

ApiDelta? _parseDelta(Map<dynamic, dynamic> delta) {
  switch (delta['type']) {
    case 'text_delta':
      final text = delta['text'];
      return text is String ? ApiDelta.text(text) : null;
    case 'thinking_delta':
      final text = delta['thinking'];
      return text is String ? ApiDelta.thinking(text) : null;
    case 'signature_delta':
      final text = delta['signature'];
      return text is String ? ApiDelta.signature(text) : null;
    case 'citations_delta':
      final citation = Citation.fromJson(delta['citation']);
      return citation == null ? null : ApiDelta.citation(citation);
    default:
      return null;
  }
}

/// Server-side error body. Also used for an unnamed `data` frame carrying an
/// error while streaming.
String? apiErrorMessage(Object? value) {
  if (value is! Map) return null;
  final error = value['error'];
  if (error is! Map) return null;
  final message = error['message'];
  return message is String ? message : null;
}
