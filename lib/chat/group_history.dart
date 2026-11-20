import '../models/chat_models.dart';

/// History for one group member, as that member should see it.
///
/// Only the member's own earlier replies stay `assistant` turns. The user's
/// questions and every other speaker's replies are delivered as `user` content
/// with an explicit attribution, so the model never mistakes another member's
/// words for its own and has no labeled transcript to imitate. Replies made in
/// the same turn run in parallel, so other members' replies of a turn are
/// shown before the member's next turn rather than before its own answer.
///
/// Providers pair history strictly as user/assistant rounds, so material that
/// has no own reply after it is merged into the next user message. What is
/// still pending after the last turn is returned as [pending] and belongs in
/// front of the current question (see [withGroupContext]).
({List<ChatMessage> history, String pending}) groupHistoryFor(
  List<ChatMessage> history, {
  required String? participantId,
  required bool zh,
}) {
  final transcript = <ChatMessage>[];
  final pending = <String>[];
  UserMessage? question;
  final own = <AssistantMessage>[];
  final others = <AssistantMessage>[];

  void finishTurn() {
    final user = question;
    if (user == null) return;
    if (own.isEmpty) {
      final said = _userSaid(user, zh);
      if (said != null) pending.add(said);
    } else {
      final name = own.first.participantName;
      transcript
        ..add(
          UserMessage(
            id: user.id,
            createdAt: user.createdAt,
            content: [...pending, user.content]
                .where((part) => part.isNotEmpty)
                .join('\n\n'),
            files: user.files,
          ),
        )
        ..add(
          AssistantMessage(
            id: own.first.id,
            createdAt: own.first.createdAt,
            status: ReplyStatus.done,
            blocks: [
              TextBlock(
                text: own
                    .map(
                      (reply) => name == null
                          ? reply.text
                          : stripLeadingNameTag(reply.text, name),
                    )
                    .join('\n\n'),
              ),
            ],
          ),
        );
      pending.clear();
    }
    for (final reply in others) {
      pending.add(_memberSaid(reply, zh));
    }
  }

  for (final message in history) {
    switch (message) {
      case UserMessage():
        finishTurn();
        question = message;
        own.clear();
        others.clear();
      case AssistantMessage() when message.isUsableContext:
        (message.participantId == participantId ? own : others).add(message);
    }
  }
  finishTurn();
  return (history: transcript, pending: pending.join('\n\n'));
}

/// The current question with the pending group context in front of it. The
/// same attachment objects are kept so upload state still lands on them.
UserMessage withGroupContext(UserMessage question, String pending) =>
    pending.isEmpty
    ? question
    : UserMessage(
        id: question.id,
        createdAt: question.createdAt,
        content: [
          pending,
          question.content,
        ].where((part) => part.isNotEmpty).join('\n\n'),
        files: question.files,
      );

String? _userSaid(UserMessage user, bool zh) {
  final text = [
    user.content,
    for (final file in user.files) zh ? '[附件：${file.name}]' : '[Attachment: ${file.name}]',
  ].where((part) => part.isNotEmpty).join('\n');
  if (text.isEmpty) return null;
  return zh ? '用户说：$text' : 'The user said: $text';
}

String _memberSaid(AssistantMessage reply, bool zh) {
  final name = reply.participantName ?? reply.model ?? (zh ? '助手' : 'Assistant');
  final text = stripLeadingNameTag(reply.text, name);
  return zh ? '「$name」说：$text' : '$name said: $text';
}

/// Removes a leading self-label such as `[name]`, `【name】`, `「name」`,
/// `name:` or `name：` (and the whitespace after it). A name that appears
/// later in the text is left alone.
String stripLeadingNameTag(String text, String name) {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) return text;
  final n = RegExp.escape(trimmedName);
  final tag = RegExp(
    '^\\s*(?:\\[$n\\]|【$n】|「$n」|$n\\s*[:：])\\s*',
    caseSensitive: false,
  );
  return text.replaceFirst(tag, '');
}
