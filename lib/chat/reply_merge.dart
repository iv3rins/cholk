import '../api/api_types.dart';
import '../models/chat_models.dart';

/// Merges one stream event into a mutable reply.
///
/// The temp [blockIndexes] map translates event indexes to indexes in
/// `reply.blocks`; skipped blocks (client tool use) occupy no slot.
void applyApiEvent(
  AssistantMessage reply,
  ApiEvent event,
  int now,
  Map<int, int> blockIndexes,
) {
  if (reply.status != ReplyStatus.streaming) {
    reply.status = ReplyStatus.streaming;
  }

  switch (event) {
    case MessageStartEvent():
      reply.model ??= event.model;
      reply.usage = event.usage ?? reply.usage;

    case ContentBlockStartEvent():
      blockIndexes.remove(event.index);
      final block = ReplyBlock.fromJson(event.block);
      if (block == null) {
        if (event.block['type'] == 'tool_use') {
          // Client tool traffic has no rendered block, but ends thinking.
          final previous = reply.blocks.lastOrNull;
          if (previous is ThinkingBlock) previous.endedAt ??= now;
          // Client tool traffic cannot be echoed as a continuation prefix.
          reply.prefix = false;
        }
        return;
      }
      blockIndexes[event.index] = reply.blocks.length;
      if (block is ThinkingBlock && block.startedAt == null) {
        block.startedAt = now;
      }
      reply.blocks.add(block);

    case ContentBlockDeltaEvent():
      final index = blockIndexes[event.index];
      if (index == null || index < 0 || index >= reply.blocks.length) return;
      final block = reply.blocks[index];
      final delta = event.delta;
      switch (delta.kind) {
        case ApiDeltaKind.text:
          if (block is TextBlock) block.text += delta.text;
        case ApiDeltaKind.thinking:
          if (block is ThinkingBlock) block.thinking += delta.text;
        case ApiDeltaKind.signature:
          if (block is ThinkingBlock) {
            block.signature = '${block.signature ?? ''}${delta.text}';
          }
        case ApiDeltaKind.citation:
          if (block is TextBlock && delta.citation != null) {
            block.citations.add(delta.citation!);
          }
      }

    case ContentBlockStopEvent():
      final index = blockIndexes.remove(event.index);
      if (index == null || index < 0 || index >= reply.blocks.length) return;
      final block = reply.blocks[index];
      if (block is ThinkingBlock &&
          block.startedAt != null &&
          block.endedAt == null) {
        block.endedAt = now;
      }

    case MessageDeltaEvent():
      reply.stopReason = event.stopReason;
      reply.stopDetails = event.stopDetails;
      reply.usage = event.usage ?? reply.usage;

    case MessageStopEvent():
      break;
  }
}

/// Finalizes a reply. A refusal drops thinking and body blocks that the
/// protocol says the client must discard; open thinking blocks are closed.
void settleReply(
  AssistantMessage reply,
  ReplyStatus status,
  int now, {
  ReplyError? error,
  int preserveBlockCount = 0,
}) {
  reply
    ..status = status
    ..error = error;
  if (reply.stopReason == StopReason.refusal) {
    // Continuations append to an existing reply. A refusal only discards the
    // content produced by this request, leaving the earlier answer intact.
    for (var i = reply.blocks.length - 1; i >= preserveBlockCount; i--) {
      final block = reply.blocks[i];
      if (block is ThinkingBlock || block is TextBlock) {
        reply.blocks.removeAt(i);
      }
    }
    return;
  }
  for (final block in reply.blocks) {
    if (block is ThinkingBlock &&
        block.startedAt != null &&
        block.endedAt == null) {
      block.endedAt = now;
    }
  }
}
