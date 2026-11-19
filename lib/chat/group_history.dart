import '../models/chat_models.dart';

/// Flattens a shared turn into one assistant message for protocols that expect
/// alternating user and assistant roles. Only visible answers are shared;
/// provider-specific reasoning, tool payloads and reminders stay in the UI.
List<ChatMessage> sharedGroupHistory(List<ChatMessage> history) {
  final transcript = <ChatMessage>[];
  UserMessage? question;
  final answers = <String>[];

  void finishTurn() {
    final user = question;
    if (user == null || answers.isEmpty) return;
    transcript
      ..add(user)
      ..add(
        AssistantMessage(
          id: user.id,
          createdAt: user.createdAt,
          status: ReplyStatus.done,
          blocks: [TextBlock(text: answers.join('\n\n'))],
        ),
      );
  }

  for (final message in history) {
    switch (message) {
      case UserMessage():
        finishTurn();
        question = message;
        answers.clear();
      case AssistantMessage() when message.isUsableContext:
        final name = message.participantName ?? message.model ?? 'Assistant';
        answers.add('[$name]\n${message.text}');
    }
  }
  finishTurn();
  return transcript;
}
