import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/chat_participant.dart';
import '../../models/model_configuration.dart';
import '../../theme/app_theme.dart';
import '../common.dart';
import 'participant_avatar.dart';
import 'participant_editor_page.dart';

enum _ProfileAction { edit, delete }

class ParticipantProfiles extends StatelessWidget {
  const ParticipantProfiles({super.key});

  Future<void> _delete(
    BuildContext context,
    ChatParticipant participant,
  ) async {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final confirm = await showConfirmDialog(
      context,
      title: strings.isZh ? '删除参与模型' : 'Delete model',
      message: strings.isZh
          ? '删除「${participant.name}」的配置？已有消息会保留。'
          : 'Delete the configuration for “${participant.name}”? Existing messages will be kept.',
      confirmLabel: strings.delete,
      cancelLabel: strings.cancel,
    );
    if (!confirm || !context.mounted) return;
    try {
      await scope.controller.deleteParticipant(participant.id);
    } catch (_) {
      if (context.mounted) showToast(context, strings.settingsSaveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = scope.palette;
    final zh = strings.isZh;
    final participants = scope.controller.participants;
    final muted = TextStyle(color: palette.lineInk2, fontSize: 13, height: 1.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                zh ? '参与模型' : 'Chat models',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const Key('add-participant'),
              onPressed: () => openParticipantEditor(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(zh ? '添加模型' : 'Add model'),
            ),
          ],
        ),
        if (participants.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            zh ? '为每个模型设置独立的连接和提示词，再从对话输入栏选择参与者。' : 'Give each model its own connection and prompt, then choose participants from the chat composer.',
            style: muted,
          ),
        ] else ...[
          const SizedBox(height: 8),
          for (final participant in participants) ...[
            Divider(height: 1, color: palette.lineRule),
            ListTile(
              key: ValueKey('participant-${participant.id}'),
              contentPadding: EdgeInsets.zero,
              onTap: () =>
                  openParticipantEditor(context, participant: participant),
              leading: ParticipantAvatar(
                name: participant.name,
                avatarBase64: participant.avatarBase64,
                size: 40,
              ),
              title: Text(
                participant.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${participant.configuration.protocol == ApiProtocol.deepseek ? 'DeepSeek' : strings.openAiCompatible} · ${participant.configuration.model}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
              trailing: PopupMenuButton<_ProfileAction>(
                tooltip: zh ? '模型选项' : 'Model options',
                onSelected: (action) {
                  switch (action) {
                    case _ProfileAction.edit:
                      openParticipantEditor(context, participant: participant);
                    case _ProfileAction.delete:
                      _delete(context, participant);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _ProfileAction.edit,
                    child: Text(strings.edit),
                  ),
                  PopupMenuItem(
                    value: _ProfileAction.delete,
                    child: Text(strings.delete),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
