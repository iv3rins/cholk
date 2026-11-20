import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/chat_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../common.dart';
import '../print_kit.dart';
import 'session_groups.dart';
import '../settings/settings_dialog.dart';

class Sider extends StatelessWidget {
  const Sider({super.key, this.mobile = false, this.onClose});

  final bool mobile;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.controller;
    final palette = scope.palette;
    final strings = scope.strings;
    final groups = groupSessions(controller.summaries, strings);
    final actionSize = mobile ? 48.0 : 36.0;

    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: palette.sidebar,
        border: Border(
          right: BorderSide(color: palette.lineInk, width: Lineism.base),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Row(
                children: [
                  AppIconButton(
                    icon: Icons.home_outlined,
                    tooltip: strings.backToHome,
                    onPressed: () => _goHome(context),
                    size: actionSize,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'CHOLK',
                    style: Lineism.display.copyWith(
                      fontSize: 19,
                      letterSpacing: 2,
                      color: palette.lineInk,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(width: 6, height: 6, color: palette.signal),
                  const Spacer(),
                  AppIconButton(
                    icon: mobile
                        ? Icons.close_rounded
                        : Icons.chevron_left_rounded,
                    tooltip: mobile ? strings.close : strings.collapseSider,
                    onPressed: mobile
                        ? onClose
                        : () => controller.setSiderCollapsed(true),
                    size: actionSize,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: _NewChatButton(
                label: strings.newChat,
                onTap: () {
                  controller.newChat();
                  if (mobile) onClose?.call();
                },
              ),
            ),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Text(
                        strings.noSessions,
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.textSecondary,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: [
                        for (final group in groups) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 14, 8, 4),
                            child: Semantics(
                              header: true,
                              child: Row(
                                children: [
                                  Text(
                                    group.label,
                                    style: Lineism.display.copyWith(
                                      fontSize: 14,
                                      letterSpacing: .8,
                                      color: palette.accent,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Divider(
                                      height: 1,
                                      color: palette.lineRule,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          for (final session in group.sessions)
                            _SessionItem(
                              key: ValueKey(session.id),
                              session: session,
                              active: controller.activeId == session.id,
                              mobile: mobile,
                              onTap: () {
                                controller.selectSession(session.id);
                                if (mobile) onClose?.call();
                              },
                              onRename: () => _rename(context, session),
                              onDelete: () => _delete(context, session),
                            ),
                        ],
                      ],
                    ),
            ),
            Divider(height: 1, color: palette.border),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton.icon(
                onPressed: () => showSettingsDialog(context),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(strings.settings),
                style: TextButton.styleFrom(
                  foregroundColor: palette.textSecondary,
                  alignment: Alignment.centerLeft,
                  minimumSize: Size(0, mobile ? 48 : 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goHome(BuildContext context) {
    final navigator = Navigator.of(context);
    if (mobile) {
      navigator.pop();
    }
    navigator.maybePop();
  }

  Future<void> _rename(BuildContext context, SessionSummary session) async {
    final scope = AppScope.of(context);
    final textController = TextEditingController(
      text: session.title.isEmpty
          ? scope.strings.sessionTitlePlaceholder
          : session.title,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(scope.strings.rename),
        content: TextField(
          scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(hintText: scope.strings.renameHint),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(scope.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(textController.text),
            child: Text(scope.strings.save),
          ),
        ],
      ),
    );
    textController.dispose();
    if (result != null && result.trim().isNotEmpty) {
      await scope.controller.renameSession(session.id, result);
    }
  }

  Future<void> _delete(BuildContext context, SessionSummary session) async {
    final scope = AppScope.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: scope.strings.deleteSessionTitle,
      message: scope.strings.deleteSessionMessage,
      confirmLabel: scope.strings.delete,
      cancelLabel: scope.strings.cancel,
    );
    if (!confirmed) return;
    await scope.controller.deleteSession(session.id);
  }
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;

    return PrintSlab(
      onPressed: onTap,
      semanticLabel: label,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.add_rounded, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                label,
                style: Lineism.display.copyWith(
                  fontSize: 18,
                  letterSpacing: .6,
                  color: palette.onAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionItem extends StatelessWidget {
  const _SessionItem({
    super.key,
    required this.session,
    required this.active,
    required this.mobile,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final SessionSummary session;
  final bool active;
  final bool mobile;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final title = session.title.isEmpty
        ? scope.strings.sessionTitlePlaceholder
        : session.title;
    final streaming = scope.controller.isStreaming(session.id);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);
    final minHeight = mobile ? 48.0 : 42.0;

    return Padding(
      padding: EdgeInsets.only(bottom: mobile ? 8 : 2),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        color: active ? palette.accentWash : Colors.transparent,
        child: Material(
          color: Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  selected: active,
                  child: InkWell(
                    onTap: onTap,
                    hoverColor: palette.hover,
                    focusColor: palette.active,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minHeight),
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                            child: Row(
                              children: [
                                if (streaming)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: palette.lineSignal,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const SizedBox.square(
                                        dimension: 5,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: active
                                          ? palette.textPrimary
                                          : palette.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedScale(
                            scale: active ? 1 : 0,
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            child: Container(
                              color: palette.accent,
                              width: 3,
                              height: 26,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: scope.strings.isZh ? '对话选项' : 'Chat options',
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  minimumSize: Size(mobile ? 48 : 36, minHeight),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: palette.textSecondary,
                ),
                onSelected: (value) {
                  if (value == 'rename') onRename();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(scope.strings.rename),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      scope.strings.delete,
                      style: TextStyle(color: palette.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
