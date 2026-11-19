import 'dart:typed_data';

import '../models/chat_models.dart';

typedef AttachmentReader = Future<Uint8List> Function(
  FileAttachment attachment,
);

/// Chat intent shared by providers; wire roles, tools and content blocks belong
/// to the protocol adapters, rather than the controller.
class ChatRequest {
  const ChatRequest({
    required this.history,
    required this.question,
    this.prefix,
    required this.systemPrompt,
    this.latestReminder,
    required this.thinking,
    required this.search,
    required this.titleRequest,
  });

  final List<ChatMessage> history;
  final UserMessage question;
  final AssistantMessage? prefix;
  final String systemPrompt;
  final String? latestReminder;
  final bool thinking;
  final bool search;
  final bool titleRequest;
}
