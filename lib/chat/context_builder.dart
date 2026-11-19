import 'dart:convert';

import '../models/chat_models.dart';
import '../models/model_configuration.dart';

Map<String, dynamic> _fileBlock(FileAttachment file) => {
  'type': file.isImage ? 'image' : 'document',
  'source': {'type': 'file', 'file_id': file.serverId},
};

List<Map<String, dynamic>> fileBlocks(Iterable<FileAttachment> files) {
  return [
    for (final file in files)
      if (file.serverId != null && file.serverId!.isNotEmpty) _fileBlock(file),
  ];
}

Map<String, dynamic> userParam(UserMessage message) {
  final blocks = fileBlocks(message.files);
  if (blocks.isEmpty) {
    return {'role': 'user', 'content': message.content};
  }
  return {
    'role': 'user',
    'content': [
      ...blocks,
      if (message.content.isNotEmpty) {'type': 'text', 'text': message.content},
    ],
  };
}

/// Converts an assistant reply back into request blocks.
///
/// Citations are stripped, historical thinking is omitted (except the current
/// continuation turn), and only read-link tool traffic with a signature is
/// echoed back so the server can restore the page context.
Map<String, dynamic> assistantParam(
  AssistantMessage reply, {
  bool prefix = false,
  bool thinking = false,
}) {
  final unsignedReadLinks = <String>{};
  for (final block in reply.blocks) {
    if (block is WebFetchResultBlock &&
        block.kind == 'read_link' &&
        !block.failed &&
        (block.signature == null || block.signature!.trim().isEmpty)) {
      unsignedReadLinks.add(block.toolUseId);
    }
  }

  final content = <Map<String, dynamic>>[];
  Map<String, dynamic>? text;

  for (final block in reply.blocks) {
    if (prefix && block is ThinkingBlock && block.thinking.trim().isEmpty) {
      continue;
    }
    if (block is TextBlock) {
      if (text != null) {
        text['text'] = '${text['text']}${block.text}';
      } else {
        final hasPreviousText =
            content.isNotEmpty && content.last['type'] == 'text';
        text = {
          'type': 'text',
          'text': '${hasPreviousText ? '\n\n' : ''}${block.text}',
        };
        content.add(text);
      }
      continue;
    }
    text = null;
    if (prefix && thinking && block is ThinkingBlock) {
      content.add({
        'type': 'thinking',
        'thinking': block.thinking,
        'signature': block.signature ?? '',
      });
    } else if (block is ServerToolUseBlock &&
        block.kind == 'read_link' &&
        !unsignedReadLinks.contains(block.id)) {
      content.add({
        'type': block.type,
        'id': block.id,
        'name': block.name,
        'input': block.input,
        'kind': block.kind,
      });
    } else if (block is WebFetchResultBlock &&
        block.kind == 'read_link' &&
        !unsignedReadLinks.contains(block.toolUseId)) {
      content.add(block.toJson());
    }
  }

  content.removeWhere(
    (block) => block['type'] == 'text' && (block['text'] as String).isEmpty,
  );
  return {'role': 'assistant', 'content': content};
}

final _cjk = RegExp(
  r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]',
  unicode: true,
);

/// Rough estimate for trimming history: one token per CJK character and one
/// per four other characters.
int estimateTokens(String text) {
  var cjk = 0;
  var other = text.runes.length;
  for (final _ in _cjk.allMatches(text)) {
    cjk++;
    other--;
  }
  return cjk + ((other + 3) ~/ 4);
}

Iterable<(UserMessage, AssistantMessage)> contextRounds(
  List<ChatMessage> history, {
  int budgetTokens = defaultHistoryBudgetTokens,
}) {
  final rounds = <(UserMessage, AssistantMessage)>[];
  var remaining = budgetTokens;
  for (var i = history.length - 1; i > 0; i--) {
    final user = history[i - 1];
    final reply = history[i];
    if (user is UserMessage &&
        (user.content.isNotEmpty || user.files.isNotEmpty) &&
        reply is AssistantMessage &&
        reply.isUsableContext) {
      var cost = estimateTokens(user.content) + 1000 * user.files.length;
      cost += estimateTokens(reply.latestReminder ?? '');
      final blocks =
          assistantParam(reply)['content'] as List<Map<String, dynamic>>;
      for (final block in blocks) {
        cost += estimateTokens(
          block['type'] == 'text' ? block['text'] as String : jsonEncode(block),
        );
      }
      if (cost > remaining) break;
      remaining -= cost;
      rounds.add((user, reply));
      i--;
    }
  }
  return rounds.reversed;
}

/// Builds the `messages` array for a request: complete question/answer pairs,
/// then the current question, optionally followed by an assistant prefix for
/// continuation.
List<Map<String, dynamic>> toRequestMessages({
  required List<ChatMessage> history,
  required UserMessage question,
  AssistantMessage? prefix,
  bool thinking = false,
  String? latestReminder,
  int budgetTokens = defaultHistoryBudgetTokens,
}) {
  final messages = <Map<String, dynamic>>[];
  String? previousReminder;

  void appendReminder(String? reminder) {
    if (reminder != null &&
        reminder.isNotEmpty &&
        reminder != previousReminder) {
      messages.add({'role': 'latest_reminder', 'content': reminder});
      previousReminder = reminder;
    }
  }

  for (final (user, reply) in contextRounds(
    history,
    budgetTokens: budgetTokens,
  )) {
    if (user.content.isEmpty && fileBlocks(user.files).isEmpty) {
      continue;
    }
    appendReminder(reply.latestReminder);
    messages
      ..add(userParam(user))
      ..add(assistantParam(reply));
  }

  appendReminder(latestReminder);
  messages.add(userParam(question));

  if (prefix != null && prefix.prefix) {
    final assistant = assistantParam(prefix, prefix: true, thinking: thinking);
    final content = assistant['content'];
    final hasUsable =
        content is List &&
        content.any(
          (block) =>
              block is Map &&
              ((block['type'] == 'text' &&
                      (block['text'] as String).trim().isNotEmpty) ||
                  (block['type'] == 'thinking' &&
                      (block['thinking'] as String).trim().isNotEmpty)),
        );
    if (hasUsable) {
      messages.add(assistant);
    }
  }

  return messages;
}
