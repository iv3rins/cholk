import 'dart:math';
import 'dart:typed_data';

import 'chat_member.dart';
import 'chat_preferences.dart';

/// Generates locally unique, roughly sortable ids without an extra dependency.
String newId() {
  final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  // A shift by 32 wraps on JavaScript targets. Use an exact numeric bound.
  final rand = Random.secure().nextInt(0x100000000).toRadixString(36);
  return '$micros-$rand';
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

final RegExp _storageIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Session ids become file names under the app data directory.
bool isSafeStorageId(String value) => _storageIdPattern.hasMatch(value);

enum ReplyStatus { pending, streaming, done, stopped, error }

ReplyStatus replyStatusFromWire(String? value) => switch (value) {
  'pending' => ReplyStatus.pending,
  'streaming' => ReplyStatus.streaming,
  'done' => ReplyStatus.done,
  'stopped' => ReplyStatus.stopped,
  'error' => ReplyStatus.error,
  _ => ReplyStatus.done,
};

enum StopReason { endTurn, maxTokens, toolUse, refusal }

String stopReasonToWire(StopReason reason) => switch (reason) {
  StopReason.endTurn => 'end_turn',
  StopReason.maxTokens => 'max_tokens',
  StopReason.toolUse => 'tool_use',
  StopReason.refusal => 'refusal',
};

StopReason? stopReasonFromWire(String? value) => switch (value) {
  'end_turn' => StopReason.endTurn,
  'max_tokens' => StopReason.maxTokens,
  'tool_use' => StopReason.toolUse,
  'refusal' => StopReason.refusal,
  _ => null,
};

class Citation {
  const Citation({
    required this.url,
    this.title,
    required this.citedText,
    this.encryptedIndex = '',
  });

  final String url;
  final String? title;
  final String citedText;
  final String encryptedIndex;

  Map<String, dynamic> toJson() => {
    'type': 'web_search_result_location',
    'url': url,
    'title': title,
    'cited_text': citedText,
    'encrypted_index': encryptedIndex,
  };

  static Citation? fromJson(Object? value) {
    if (value is! Map) return null;
    final url = value['url'];
    if (url is! String) return null;
    return Citation(
      url: url,
      title: value['title'] is String ? value['title'] as String : null,
      citedText: value['cited_text'] is String
          ? value['cited_text'] as String
          : '',
      encryptedIndex: value['encrypted_index'] is String
          ? value['encrypted_index'] as String
          : '',
    );
  }
}

class MessageUsage {
  MessageUsage({
    this.inputTokens = 0,
    this.cacheCreationInputTokens = 0,
    this.cacheReadInputTokens = 0,
    this.outputTokens = 0,
    this.webSearchRequests,
    this.toolSearch,
  });

  int inputTokens;
  int cacheCreationInputTokens;
  int cacheReadInputTokens;
  int outputTokens;
  int? webSearchRequests;
  int? toolSearch;

  Map<String, dynamic> toJson() => {
    'input_tokens': inputTokens,
    'cache_creation_input_tokens': cacheCreationInputTokens,
    'cache_read_input_tokens': cacheReadInputTokens,
    'output_tokens': outputTokens,
    if (webSearchRequests != null || toolSearch != null)
      'server_tool_use': {
        'web_search_requests': webSearchRequests ?? 0,
        'tool_search': toolSearch ?? 0,
      },
  };

  static MessageUsage? fromJson(Object? value) {
    if (value is! Map) return null;
    int read(String key) => value[key] is num ? (value[key] as num).toInt() : 0;
    final tool = value['server_tool_use'];
    return MessageUsage(
      inputTokens: read('input_tokens'),
      cacheCreationInputTokens: read('cache_creation_input_tokens'),
      cacheReadInputTokens: read('cache_read_input_tokens'),
      outputTokens: read('output_tokens'),
      webSearchRequests: tool is Map && tool['web_search_requests'] is num
          ? (tool['web_search_requests'] as num).toInt()
          : null,
      toolSearch: tool is Map && tool['tool_search'] is num
          ? (tool['tool_search'] as num).toInt()
          : null,
    );
  }

  int get totalInputTokens =>
      inputTokens + cacheCreationInputTokens + cacheReadInputTokens;
}

/// A content block of an assistant reply. Unknown block types are dropped,
/// except for server tool blocks which keep their original JSON so they can be
/// echoed back for read-link context.
abstract class ReplyBlock {
  const ReplyBlock();

  String get type;

  Map<String, dynamic> toJson();

  static ReplyBlock? fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'text':
        final text = json['text'];
        if (text is! String) return null;
        final citations = <Citation>[];
        final rawCitations = json['citations'];
        if (rawCitations is List) {
          for (final item in rawCitations) {
            final citation = Citation.fromJson(item);
            if (citation != null) citations.add(citation);
          }
        }
        return TextBlock(
          text: text,
          citations: citations,
          isTemplate: json['is_template'] == true,
        );
      case 'thinking':
        final thinking = json['thinking'];
        if (thinking is! String) return null;
        return ThinkingBlock(
          thinking: thinking,
          signature: json['signature'] is String
              ? json['signature'] as String
              : null,
          startedAt: json['started_at'] is num
              ? (json['started_at'] as num).toInt()
              : null,
          endedAt: json['ended_at'] is num
              ? (json['ended_at'] as num).toInt()
              : null,
          elapsedSeconds: json['elapsed_seconds'] is num
              ? (json['elapsed_seconds'] as num).toInt()
              : null,
        );
      case 'server_tool_use':
        final id = json['id'];
        final name = json['name'];
        final kind = json['kind'];
        final input = json['input'];
        if (id is! String ||
            name is! String ||
            kind is! String ||
            input is! Map) {
          return null;
        }
        return ServerToolUseBlock(
          id: id,
          name: name,
          kind: kind,
          input: Map<String, dynamic>.from(input),
          raw: Map<String, dynamic>.from(json),
        );
      case 'web_search_tool_result':
        final toolUseId = json['tool_use_id'];
        final content = json['content'];
        final kind = json['kind'];
        if (toolUseId is! String || content is! List || kind is! String) {
          return null;
        }
        return WebSearchResultBlock(
          toolUseId: toolUseId,
          kind: kind,
          content: List<dynamic>.from(content),
          raw: Map<String, dynamic>.from(json),
        );
      case 'web_fetch_tool_result':
        final toolUseId = json['tool_use_id'];
        final content = json['content'];
        final kind = json['kind'];
        if (toolUseId is! String || content is! Map || kind is! String) {
          return null;
        }
        return WebFetchResultBlock(
          toolUseId: toolUseId,
          kind: kind,
          content: Map<String, dynamic>.from(content),
          signature: json['signature'] is String
              ? json['signature'] as String
              : null,
          raw: Map<String, dynamic>.from(json),
        );
      default:
        return null;
    }
  }
}

class ThinkingBlock extends ReplyBlock {
  ThinkingBlock({
    required this.thinking,
    this.signature,
    this.startedAt,
    this.endedAt,
    this.elapsedSeconds,
  });

  String thinking;
  String? signature;
  int? startedAt;
  int? endedAt;
  int? elapsedSeconds;

  @override
  String get type => 'thinking';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'thinking',
    'thinking': thinking,
    if (signature != null) 'signature': signature,
    if (startedAt != null) 'started_at': startedAt,
    if (endedAt != null) 'ended_at': endedAt,
    if (elapsedSeconds != null) 'elapsed_seconds': elapsedSeconds,
  };
}

class TextBlock extends ReplyBlock {
  TextBlock({
    required this.text,
    List<Citation>? citations,
    this.isTemplate = false,
  }) : citations = citations ?? [];

  String text;
  List<Citation> citations;
  bool isTemplate;

  @override
  String get type => 'text';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'text',
    'text': text,
    if (citations.isNotEmpty)
      'citations': citations.map((item) => item.toJson()).toList(),
    if (isTemplate) 'is_template': true,
  };
}

class ServerToolUseBlock extends ReplyBlock {
  ServerToolUseBlock({
    required this.id,
    required this.name,
    required this.kind,
    required this.input,
    required this.raw,
  });

  String id;
  String name;
  String kind;
  Map<String, dynamic> input;
  final Map<String, dynamic> raw;

  String get action =>
      input['action'] is String ? input['action'] as String : '';

  List<String> get queries {
    final value = input['queries'];
    if (value is! List) return const [];
    return value.whereType<String>().toList();
  }

  String get url => input['url'] is String ? input['url'] as String : '';

  String get pattern =>
      input['pattern'] is String ? input['pattern'] as String : '';

  @override
  String get type => 'server_tool_use';

  @override
  Map<String, dynamic> toJson() => {
    ...raw,
    'type': 'server_tool_use',
    'id': id,
    'name': name,
    'input': input,
    'kind': kind,
  };
}

class WebSearchResultBlock extends ReplyBlock {
  WebSearchResultBlock({
    required this.toolUseId,
    required this.kind,
    required this.content,
    required this.raw,
  });

  String toolUseId;
  String kind;
  List<dynamic> content;
  final Map<String, dynamic> raw;

  bool get failed => content.any(
    (item) => item is Map && item['type'] == 'web_search_tool_result_error',
  );

  @override
  String get type => 'web_search_tool_result';

  @override
  Map<String, dynamic> toJson() => {
    ...raw,
    'type': 'web_search_tool_result',
    'tool_use_id': toolUseId,
    'kind': kind,
    'content': content,
  };
}

class WebFetchResultBlock extends ReplyBlock {
  WebFetchResultBlock({
    required this.toolUseId,
    required this.kind,
    required this.content,
    this.signature,
    required this.raw,
  });

  String toolUseId;
  String kind;
  Map<String, dynamic> content;
  String? signature;
  final Map<String, dynamic> raw;

  bool get failed => content['type'] == 'web_fetch_tool_result_error';

  Map<String, dynamic>? get result =>
      content['type'] == 'web_fetch_result' ? content : null;

  String get url {
    final value = result?['url'];
    return value is String ? value : '';
  }

  String? get title {
    final value = result?['content'];
    if (value is! Map) return null;
    final title = value['title'];
    return title is String ? title : null;
  }

  @override
  String get type => 'web_fetch_tool_result';

  @override
  Map<String, dynamic> toJson() => {
    ...raw,
    'type': 'web_fetch_tool_result',
    'tool_use_id': toolUseId,
    'kind': kind,
    'content': content,
    if (signature != null) 'signature': signature,
  };
}

class FileAttachment {
  FileAttachment({
    required this.id,
    this.serverId,
    this.serverOrigin,
    required this.name,
    required this.size,
    required this.isImage,
    required this.mimeType,
    this.localPath,
    this.bytes,
    this.status = AttachmentStatus.ready,
    this.error,
  });

  final String id;
  String? serverId;
  String? serverOrigin;
  final String name;
  final int size;
  final bool isImage;
  final String mimeType;
  final String? localPath;
  Uint8List? bytes;
  AttachmentStatus status;
  String? error;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (serverId != null) 'server_id': serverId,
    if (serverOrigin != null) 'server_origin': serverOrigin,
    'name': name,
    'size': size,
    'is_image': isImage,
    'mime_type': mimeType,
    if (localPath != null) 'local_path': localPath,
  };

  static FileAttachment? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || name is! String) return null;
    return FileAttachment(
      id: id,
      serverId: value['server_id'] is String
          ? value['server_id'] as String
          : null,
      serverOrigin: value['server_origin'] is String
          ? value['server_origin'] as String
          : null,
      name: name,
      size: value['size'] is num ? (value['size'] as num).toInt() : 0,
      isImage: value['is_image'] == true,
      mimeType: value['mime_type'] is String
          ? value['mime_type'] as String
          : '',
      localPath: value['local_path'] is String
          ? value['local_path'] as String
          : null,
    );
  }
}

enum AttachmentStatus { ready, uploading, failed }

class ReplyError {
  const ReplyError({
    required this.kind,
    required this.message,
    this.status,
    this.localMessage,
    this.retryable = false,
  });

  final String kind;
  final String message;
  final int? status;
  final String? localMessage;
  final bool retryable;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'message': message,
    if (status != null) 'status': status,
    if (localMessage != null) 'local_message': localMessage,
    if (retryable) 'retryable': true,
  };

  static ReplyError? fromJson(Object? value) {
    if (value is! Map) return null;
    return ReplyError(
      kind: value['kind'] is String ? value['kind'] as String : 'protocol',
      message: value['message'] is String ? value['message'] as String : '',
      status: value['status'] is num ? (value['status'] as num).toInt() : null,
      localMessage: value['local_message'] is String
          ? value['local_message'] as String
          : null,
      retryable: value['retryable'] == true,
    );
  }

  String get displayMessage =>
      (localMessage != null && localMessage!.isNotEmpty)
      ? localMessage!
      : message;
}

abstract class ChatMessage {
  ChatMessage({
    required this.id,
    required this.createdAt,
    this.parentId,
    this.selectedChildId,
  });

  final String id;
  final int createdAt;
  String? parentId;
  String? selectedChildId;

  String get role;

  Map<String, dynamic> toJson();

  static ChatMessage? fromJson(Map<String, dynamic> json) {
    final role = json['role'];
    if (role == 'user') {
      final content = json['content'];
      if (content is! String) return null;
      final files = <FileAttachment>[];
      final rawFiles = json['files'];
      if (rawFiles is List) {
        for (final item in rawFiles) {
          final file = FileAttachment.fromJson(item);
          if (file != null) files.add(file);
        }
      }
      return UserMessage(
        id: json['id'] as String,
        createdAt: (json['created_at'] as num).toInt(),
        parentId: json['parent_id'] as String?,
        selectedChildId: json['selected_child_id'] as String?,
        content: content,
        files: files,
      );
    }
    if (role == 'assistant') {
      final blocks = <ReplyBlock>[];
      final rawBlocks = json['blocks'];
      if (rawBlocks is List) {
        for (final item in rawBlocks) {
          if (item is Map) {
            final block = ReplyBlock.fromJson(Map<String, dynamic>.from(item));
            if (block != null) blocks.add(block);
          }
        }
      }
      return AssistantMessage(
        id: json['id'] as String,
        createdAt: (json['created_at'] as num).toInt(),
        parentId: json['parent_id'] as String?,
        selectedChildId: json['selected_child_id'] as String?,
        model: json['model'] as String?,
        modelReference: ChatModelRef.fromJson(json['model_ref']),
        participantId: json['participant_id'] as String?,
        participantName: json['participant_name'] as String?,
        participantAvatarBase64: json['participant_avatar'] as String?,
        thinking: json['thinking'] == true,
        search: json['search'] == true,
        latestReminder: json['latest_reminder'] as String?,
        prefix: json['prefix'] != false,
        status: replyStatusFromWire(json['status'] as String?),
        blocks: blocks,
        stopReason: stopReasonFromWire(json['stop_reason'] as String?),
        stopDetails: json['stop_details'] is Map
            ? Map<String, dynamic>.from(json['stop_details'] as Map)
            : null,
        usage: MessageUsage.fromJson(json['usage']),
        error: ReplyError.fromJson(json['error']),
      );
    }
    return null;
  }
}

class UserMessage extends ChatMessage {
  UserMessage({
    required super.id,
    required super.createdAt,
    super.parentId,
    super.selectedChildId,
    required this.content,
    List<FileAttachment>? files,
  }) : files = files ?? [];

  String content;
  List<FileAttachment> files;

  @override
  String get role => 'user';

  @override
  Map<String, dynamic> toJson() => {
    'role': 'user',
    'id': id,
    'created_at': createdAt,
    if (parentId != null) 'parent_id': parentId,
    if (selectedChildId != null) 'selected_child_id': selectedChildId,
    'content': content,
    'files': files.map((file) => file.toJson()).toList(),
  };
}

class AssistantMessage extends ChatMessage {
  AssistantMessage({
    required super.id,
    required super.createdAt,
    super.parentId,
    super.selectedChildId,
    this.model,
    this.modelReference,
    this.participantId,
    this.participantName,
    this.participantAvatarBase64,
    this.thinking = false,
    this.search = false,
    this.latestReminder,
    this.prefix = true,
    this.status = ReplyStatus.pending,
    List<ReplyBlock>? blocks,
    this.stopReason,
    this.stopDetails,
    this.usage,
    this.error,
  }) : blocks = blocks ?? [];

  String? model;

  /// The server or hand-filled source that produced this reply, without the
  /// credential. Retries and continuations reuse it so they never silently
  /// switch to another server or to a model selected later.
  ChatModelRef? modelReference;
  final String? participantId;
  final String? participantName;
  final String? participantAvatarBase64;
  bool thinking;
  bool search;
  String? latestReminder;
  bool prefix;
  ReplyStatus status;
  List<ReplyBlock> blocks;
  StopReason? stopReason;
  Map<String, dynamic>? stopDetails;
  MessageUsage? usage;
  ReplyError? error;

  @override
  String get role => 'assistant';

  bool get isStreaming =>
      status == ReplyStatus.pending || status == ReplyStatus.streaming;

  String get text => blocks
      .whereType<TextBlock>()
      .where((block) => !block.isTemplate)
      .map((block) => block.text)
      .join();

  bool get hasTemplate =>
      blocks.any((block) => block is TextBlock && block.isTemplate);

  bool get canContinue {
    if (!prefix ||
        stopReason == StopReason.refusal ||
        stopReason == StopReason.toolUse ||
        blocks.any(
          (block) =>
              block is ServerToolUseBlock ||
              block is WebSearchResultBlock ||
              block is WebFetchResultBlock ||
              (block is TextBlock && block.isTemplate),
        )) {
      return false;
    }
    return status == ReplyStatus.stopped ||
        (status == ReplyStatus.done && stopReason == StopReason.maxTokens);
  }

  bool get isUsableContext =>
      (status == ReplyStatus.done || status == ReplyStatus.stopped) &&
      stopReason != StopReason.refusal &&
      !hasTemplate &&
      text.isNotEmpty;

  @override
  Map<String, dynamic> toJson() => {
    'role': 'assistant',
    'id': id,
    'created_at': createdAt,
    if (parentId != null) 'parent_id': parentId,
    if (selectedChildId != null) 'selected_child_id': selectedChildId,
    if (model != null) 'model': model,
    if (modelReference != null) 'model_ref': modelReference!.toJson(),
    if (participantId != null) 'participant_id': participantId,
    if (participantName != null) 'participant_name': participantName,
    if (participantAvatarBase64 != null)
      'participant_avatar': participantAvatarBase64,
    'thinking': thinking,
    'search': search,
    if (latestReminder != null) 'latest_reminder': latestReminder,
    'prefix': prefix,
    'status': status.name,
    'blocks': blocks.map((block) => block.toJson()).toList(),
    if (stopReason != null) 'stop_reason': stopReasonToWire(stopReason!),
    if (stopDetails != null) 'stop_details': stopDetails,
    if (usage != null) 'usage': usage!.toJson(),
    if (error != null) 'error': error!.toJson(),
  };
}

class SessionSummary {
  SessionSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  String title;
  final int createdAt;
  int updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  static SessionSummary? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    if (id is! String || !isSafeStorageId(id)) return null;
    return SessionSummary(
      id: id,
      title: value['title'] is String ? value['title'] as String : '',
      createdAt: value['created_at'] is num
          ? (value['created_at'] as num).toInt()
          : 0,
      updatedAt: value['updated_at'] is num
          ? (value['updated_at'] as num).toInt()
          : 0,
    );
  }
}

class ChatSession {
  ChatSession({
    required this.id,
    this.title = '',
    required this.createdAt,
    required this.updatedAt,
    List<ChatMessage>? messages,
    this.rootMessageId,
    this.selectedParticipantIds = const [],
    this.mode = ChatMode.chat,
    this.members = const [],
    this.selectedMemberIds = const [],
    this.model,
    String? personaId,
    String? chatPersonaId,
    String? workPersonaId,
  }) : messages = messages ?? [],
       chatPersonaId =
           chatPersonaId ?? (mode == ChatMode.chat ? personaId : null),
       workPersonaId =
           workPersonaId ?? (mode == ChatMode.work ? personaId : null);

  final String id;
  String title;
  final int createdAt;
  int updatedAt;
  List<ChatMessage> messages;
  String? rootMessageId;
  List<String> selectedParticipantIds;
  ChatMode mode;
  List<ChatMember> members;
  List<String> selectedMemberIds;
  ChatModelRef? model;
  String? chatPersonaId;
  String? workPersonaId;

  String? get personaId =>
      mode == ChatMode.chat ? chatPersonaId : workPersonaId;
  set personaId(String? value) {
    switch (mode) {
      case ChatMode.chat:
        chatPersonaId = value;
      case ChatMode.work:
        workPersonaId = value;
    }
  }

  bool get isEmpty => messages.isEmpty;

  ChatMessage? messageById(String id) {
    for (final message in messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  List<ChatMessage> get visibleMessages {
    if (rootMessageId == null) return List.unmodifiable(messages);
    final byId = {for (final message in messages) message.id: message};
    final path = <ChatMessage>[];
    String? cursor = rootMessageId;
    while (cursor != null) {
      final message = byId.remove(cursor);
      if (message == null) break;
      path.add(message);
      cursor = message.selectedChildId;
    }
    return path;
  }

  SessionSummary toSummary() => SessionSummary(
    id: id,
    title: title,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'messages': messages.map((message) => message.toJson()).toList(),
    if (rootMessageId != null) 'root_message_id': rootMessageId,
    if (selectedParticipantIds.isNotEmpty)
      'selected_participant_ids': selectedParticipantIds,
    if (mode != ChatMode.chat) 'mode': mode.name,
    if (chatPersonaId != null) 'chat_persona_id': chatPersonaId,
    if (workPersonaId != null) 'work_persona_id': workPersonaId,
    if (members.isNotEmpty)
      'members': members.map((member) => member.toJson()).toList(),
    if (selectedMemberIds.isNotEmpty)
      'selected_member_ids': List<String>.of(selectedMemberIds),
    if (model != null) 'model_ref': model!.toJson(),
  };

  static ChatSession? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || !isSafeStorageId(id)) return null;
    final messages = <ChatMessage>[];
    final rawMessages = json['messages'];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map) {
          final message = ChatMessage.fromJson(Map<String, dynamic>.from(item));
          if (message != null) messages.add(message);
        }
      }
    }
    final session = ChatSession(
      id: id,
      title: json['title'] is String ? json['title'] as String : '',
      createdAt: json['created_at'] is num
          ? (json['created_at'] as num).toInt()
          : nowMs(),
      updatedAt: json['updated_at'] is num
          ? (json['updated_at'] as num).toInt()
          : nowMs(),
      messages: messages,
      mode: ChatMode.fromWire(json['mode']),
      personaId:
          !json.containsKey('chat_persona_id') &&
              !json.containsKey('work_persona_id') &&
              json['persona_id'] is String
          ? json['persona_id'] as String
          : null,
      chatPersonaId: json['chat_persona_id'] is String
          ? json['chat_persona_id'] as String
          : null,
      workPersonaId: json['work_persona_id'] is String
          ? json['work_persona_id'] as String
          : null,
      model: ChatModelRef.fromJson(json['model_ref']),
      members: switch (json['members']) {
        List list => List.unmodifiable(
          list
              .map(ChatMember.fromJson)
              .nonNulls
              .where((member) => isSafeStorageId(member.id)),
        ),
        _ => const [],
      },
      selectedMemberIds: switch (json['selected_member_ids']) {
        List ids => List.unmodifiable(ids.whereType<String>()),
        _ => const [],
      },
      selectedParticipantIds: switch (json['selected_participant_ids']) {
        List ids => List.unmodifiable(ids.whereType<String>()),
        _ => const [],
      },
      rootMessageId: json['root_message_id'] is String
          ? json['root_message_id'] as String
          : null,
    );
    return session.normalized();
  }

  /// Fills parent/child links for legacy linear sessions.
  ChatSession normalized() {
    if (rootMessageId != null || messages.isEmpty) return this;
    rootMessageId = messages.first.id;
    for (var i = 0; i < messages.length; i++) {
      messages[i].parentId = i == 0 ? null : messages[i - 1].id;
      messages[i].selectedChildId = i + 1 < messages.length
          ? messages[i + 1].id
          : null;
    }
    return this;
  }

  ChatSession copy() => ChatSession.fromJson(toJson())!;
}

/// Appends [newMessages] below [parentId] and selects the new branch.
ChatSession appendBranch(
  ChatSession session,
  String? parentId,
  List<ChatMessage> newMessages,
) {
  final normalized = session.normalized();
  if (newMessages.isEmpty) return normalized;
  final first = newMessages.first;
  final updated = <ChatMessage>[];
  for (final message in normalized.messages) {
    if (message.id == parentId) {
      message.selectedChildId = first.id;
    }
    updated.add(message);
  }
  for (var i = 0; i < newMessages.length; i++) {
    final message = newMessages[i];
    message
      ..parentId = i == 0 ? parentId : newMessages[i - 1].id
      ..selectedChildId = i + 1 < newMessages.length
          ? newMessages[i + 1].id
          : null;
    updated.add(message);
  }
  normalized
    ..messages = updated
    ..rootMessageId = parentId == null ? first.id : normalized.rootMessageId
    ..updatedAt = nowMs();
  return normalized;
}

/// Switches the visible path to the sibling [messageId].
void selectVersion(ChatSession session, String messageId) {
  final message = session.messageById(messageId);
  if (message == null) return;
  final visible = session.visibleMessages;
  final hasSiblingOnPath = visible.any(
    (item) => item.parentId == message.parentId,
  );
  if (!hasSiblingOnPath) return;
  if (message.parentId == null) {
    session.rootMessageId = message.id;
  } else {
    final parent = session.messageById(message.parentId!);
    parent?.selectedChildId = message.id;
  }
  session.updatedAt = nowMs();
}

class MessageVersions {
  const MessageVersions(this.ids, this.index);
  final List<String> ids;
  final int index;
}

Map<String, MessageVersions> buildMessageVersions(ChatSession session) {
  final groups = <String?, List<String>>{};
  for (final message in session.messages) {
    final key = session.rootMessageId == null ? message.id : message.parentId;
    groups.putIfAbsent(key, () => []).add(message.id);
  }
  final versions = <String, MessageVersions>{};
  for (final ids in groups.values) {
    for (var i = 0; i < ids.length; i++) {
      versions[ids[i]] = MessageVersions(ids, i);
    }
  }
  return versions;
}
