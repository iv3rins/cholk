import 'dart:convert';

class SseEvent {
  const SseEvent(this.event, this.data);

  final String? event;
  final String data;
}

/// Parses a `text/event-stream` byte stream into events.
///
/// Handles multi-line `data:` fields, CRLF/LF line endings, comments and
/// ignores `id` / `retry` fields. A final event without a trailing blank line
/// is still emitted.
Stream<SseEvent> parseSse(Stream<List<int>> byteStream) async* {
  String? event;
  final data = <String>[];

  final lines = byteStream
      .map<List<int>>((chunk) => chunk)
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final rawLine in lines) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        yield SseEvent(event, data.join('\n'));
        data.clear();
      }
      event = null;
      continue;
    }
    if (line.startsWith(':')) {
      continue;
    }
    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    switch (field) {
      case 'event':
        event = value;
      case 'data':
        data.add(value);
      default:
        break;
    }
  }

  if (data.isNotEmpty) {
    yield SseEvent(event, data.join('\n'));
  }
}
