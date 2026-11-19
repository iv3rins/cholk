import '../models/chat_participant.dart';

final _boundary = RegExp(r'[\s,.;:!?()\[\]<>"“”‘’，。？！、；：（）【】《》…]');
final _reservedInName = RegExp(r'[@{}\r\n]');

/// Mentions are scoped to current group members. Ambiguous names use stable IDs.
class AgentMentions {
  AgentMentions(List<ChatParticipant> participants) {
    final counts = <String, int>{};
    for (final participant in participants) {
      counts.update(
        participant.name.toLowerCase(),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    for (final participant in participants) {
      final unique = counts[participant.name.toLowerCase()] == 1;
      final handle = unique && !_reservedInName.hasMatch(participant.name)
          ? '@${participant.name}'
          : '@{${participant.id}}';
      options.add((participant: participant, handle: handle));
    }
  }

  final options = <MentionOption>[];

  List<ChatParticipant> resolve(String message) {
    if (options.isEmpty || !message.contains('@')) return const [];
    final sorted = [
      ...options,
      for (final option in options)
        if (!option.handle.startsWith('@{'))
          (
            participant: option.participant,
            handle: '@{${option.participant.id}}',
          ),
    ]..sort((a, b) => b.handle.length.compareTo(a.handle.length));
    final found = <ChatParticipant>[];
    final seen = <String>{};
    for (var at = message.indexOf('@'); at >= 0;) {
      var next = at + 1;
      if (canStartAt(message, at)) {
        for (final option in sorted) {
          final end = at + option.handle.length;
          if (end > message.length ||
              (end < message.length && !_boundary.hasMatch(message[end])) ||
              message.substring(at, end).toLowerCase() !=
                  option.handle.toLowerCase()) {
            continue;
          }
          if (seen.add(option.participant.id)) found.add(option.participant);
          next = end;
          break;
        }
      }
      at = message.indexOf('@', next);
    }
    return found;
  }

  static MentionQuery? queryAt(String text, int caret) {
    if (caret <= 0 || caret > text.length) return null;
    final at = text.lastIndexOf('@', caret - 1);
    if (at < 0 || !canStartAt(text, at)) return null;
    final query = text.substring(at + 1, caret);
    if (query.contains('\n')) return null;
    return (start: at, end: caret, query: query.toLowerCase());
  }

  static bool canStartAt(String text, int offset) =>
      offset == 0 || _boundary.hasMatch(text[offset - 1]);
}

typedef MentionOption = ({ChatParticipant participant, String handle});
typedef MentionQuery = ({int start, int end, String query});
