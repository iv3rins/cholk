import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/chat_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../common.dart';
import '../participants/participant_avatar.dart';
import 'markdown_view.dart';

class GenerationMonitor extends StatefulWidget {
  const GenerationMonitor({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<GenerationMonitor> createState() => _GenerationMonitorState();
}

class _GenerationMonitorState extends State<GenerationMonitor> {
  String? _sessionId;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.controller;
    final strings = scope.strings;
    final selectedId = controller.summaries.any((s) => s.id == _sessionId)
        ? _sessionId
        : null;
    final id = selectedId ?? controller.activeId;
    return Material(
      color: scope.palette.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: scope.palette.lineRule,
              width: Lineism.hair,
            ),
          ),
        ),
        child: ListView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      strings.generationMonitor,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                AppIconButton(
                  icon: Icons.close_rounded,
                  tooltip: strings.closeGenerationMonitor,
                  size: 44,
                  onPressed: widget.onClose,
                ),
              ],
            ),
            _MonitorSelect<String>(
              fieldKey: const Key('monitor-session'),
              label: strings.monitorSession,
              value: selectedId ?? '',
              items: [
                DropdownMenuItem(
                  value: '',
                  child: _option(strings.followActiveSession),
                ),
                for (final summary in controller.summaries)
                  DropdownMenuItem(
                    value: summary.id,
                    child: _option(
                      summary.title.trim().isEmpty
                          ? strings.sessionTitlePlaceholder
                          : summary.title,
                    ),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _sessionId = value == '' ? null : value),
            ),
            if (id == null)
              _MonitorNotice(strings.monitorNoReplies)
            else
              _MonitoredSession(key: ValueKey(id), id: id),
          ],
        ),
      ),
    );
  }
}

// A record distinguishes the default connection (null ID) from no selection.
typedef _Role = (String?,);

class _MonitoredSession extends StatefulWidget {
  const _MonitoredSession({super.key, required this.id});
  final String id;

  @override
  State<_MonitoredSession> createState() => _MonitoredSessionState();
}

class _MonitoredSessionState extends State<_MonitoredSession> {
  Future<ChatSession?>? _read;
  _Role? _selectedRole;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context).controller;
    if (controller.cachedSession(widget.id) == null) {
      _read ??= controller.readSession(widget.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final cached = scope.controller.cachedSession(widget.id);
    return FutureBuilder<ChatSession?>(
      future: _read,
      builder: (context, snapshot) {
        final session = cached ?? snapshot.data;
        if (session == null) {
          return _MonitorNotice(
            snapshot.connectionState == ConnectionState.waiting
                ? scope.strings.monitorLoading
                : scope.strings.monitorUnavailable,
          );
        }
        return ListenableBuilder(
          listenable: scope.controller,
          builder: (context, _) => _buildReplies(context, session),
        );
      },
    );
  }

  Widget _buildReplies(BuildContext context, ChatSession session) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final live = scope.controller.isStreaming(session.id);
    final entries = <_Role, AssistantMessage>{};
    for (final reply in session.visibleMessages.whereType<AssistantMessage>()) {
      final role = (reply.participantId,);
      final previous = entries[role];
      if (!live || previous?.isStreaming != true || reply.isStreaming) {
        entries[role] = reply;
      }
    }
    if (entries.isEmpty) return _MonitorNotice(strings.monitorNoReplies);
    final role = entries.containsKey(_selectedRole)
        ? _selectedRole!
        : (entries.entries
                  .where((entry) => live && entry.value.isStreaming)
                  .firstOrNull
                  ?.key ??
              entries.keys.first);
    final reply = entries[role]!;
    final status = switch (reply.status) {
      ReplyStatus.pending when live => strings.replyQueued,
      ReplyStatus.streaming when live => strings.waiting,
      ReplyStatus.pending ||
      ReplyStatus.streaming ||
      ReplyStatus.stopped => strings.replyStopped,
      ReplyStatus.done => strings.replyDone,
      ReplyStatus.error => strings.errorOccurred,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonitorSelect<_Role>(
          fieldKey: const Key('monitor-role'),
          label: strings.monitorParticipant,
          value: role,
          items: [
            for (final entry in entries.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Row(
                  children: [
                    ParticipantAvatar(
                      size: 24,
                      name:
                          entry.value.participantName ??
                          strings.defaultAssistant,
                      avatarBase64: entry.value.participantAvatarBase64,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _option(
                        entry.value.participantName ?? strings.defaultAssistant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (value) => setState(() => _selectedRole = value),
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(status, style: Theme.of(context).textTheme.labelMedium),
        ),
        const SizedBox(height: 12),
        if (reply.text.isNotEmpty)
          MarkdownView(key: ValueKey(reply.id), data: reply.text)
        else if (reply.stopReason != StopReason.refusal &&
            reply.status == ReplyStatus.done)
          Text(strings.noReplyText),
        if (reply.stopReason == StopReason.refusal) Text(strings.replyRefusal),
      ],
    );
  }
}

Widget _option(String text) =>
    Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

class _MonitorSelect<T> extends StatelessWidget {
  const _MonitorSelect({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      Semantics(
        label: label,
        child: DropdownButton<T>(
          key: fieldKey,
          isExpanded: true,
          value: value,
          items: items,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

class _MonitorNotice extends StatelessWidget {
  const _MonitorNotice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(message),
  );
}
