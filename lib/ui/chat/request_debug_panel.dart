import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/chat_models.dart';
import '../../theme/app_theme.dart';

/// Non-modal so the composer remains available while recording requests.
class RequestDebugPanel extends StatelessWidget {
  const RequestDebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppScope.of(context).controller,
      builder: _buildPanel,
    );
  }

  Widget _buildPanel(BuildContext context, Widget? child) {
    final scope = AppScope.of(context);
    final chat = scope.controller;
    final zh = scope.strings.isZh;
    final records = chat.activeRequestDebug;
    String status(ReplyStatus value) => switch (value) {
      ReplyStatus.pending => zh ? '等待中' : 'Pending',
      ReplyStatus.streaming => zh ? '流式接收中' : 'Streaming',
      ReplyStatus.done => zh ? '已完成' : 'Done',
      ReplyStatus.stopped => zh ? '已停止' : 'Stopped',
      ReplyStatus.error => zh ? '失败' : 'Failed',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scope.palette.lineRule)),
      ),
      child: ListView(
        primary: false,
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    zh ? '请求调试' : 'Request debug',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: zh ? '关闭并清除记录' : 'Close and clear records',
                  icon: const Icon(Icons.close),
                  onPressed: () => chat.setDebugRecording(false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              zh
                  ? '仅记录打开后的请求，不保存到磁盘。关闭后清空。'
                  : 'Records new requests in memory only. Closing clears them.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                zh ? '当前会话暂无记录，发送消息即可开始。' : 'No requests for this conversation yet. Send a message to start.',
              ),
            )
          else
            for (final record in records)
              Builder(
                builder: (context) {
                  final started = TimeOfDay.fromDateTime(
                    DateTime.fromMillisecondsSinceEpoch(record.startedAt),
                  ).format(context);
                  final http = record.httpStatus;
                  final outcome = [
                    status(record.status),
                    ?record.errorKind,
                    if (http != null) 'HTTP $http',
                  ].join(' · ');
                  final names = [
                    for (final persona in record.personas) persona.name(zh),
                  ].join(' / ');
                  return ExpansionTile(
                    key: ObjectKey(record),
                    title: Text(
                      '${record.participantName ?? (zh ? '默认连接' : 'Default connection')} · ${record.model}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('$outcome · $started'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${record.protocol.name}${names.isEmpty ? '' : ' · $names'}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        zh
                            ? 'System Prompt · ${record.systemChars} 字符'
                            : 'System prompt · ${record.systemChars} characters',
                      ),
                      SelectableText(record.systemPrompt),
                      if (chat.settings.isAdvancedMode &&
                          record.errorMessage != null)
                        SelectableText(record.errorMessage!),
                    ],
                  );
                },
              ),
        ],
      ),
    );
  }
}
