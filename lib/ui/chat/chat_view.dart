import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/chat_models.dart';
import '../../models/chat_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../common.dart';
import '../selection_feedback.dart';
import '../settings/chat_background_settings.dart';
import 'chat_background.dart';
import 'chat_input.dart';
import 'generation_monitor.dart';
import 'message_list.dart';
import 'request_debug_panel.dart';
import 'welcome_view.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.isMobile});

  final bool isMobile;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  bool _monitorOpen = false;

  void _toggleMonitor() => setState(() => _monitorOpen = !_monitorOpen);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.controller;
    final session = controller.activeSession;
    final isMobile = widget.isMobile;
    final inWorkMode = controller.chatMode == ChatMode.work;
    final showMonitor = inWorkMode && _monitorOpen;
    final visible = session?.visibleMessages ?? const <ChatMessage>[];
    final versions = session != null && visible.isNotEmpty
        ? buildMessageVersions(session)
        : const <String, MessageVersions>{};
    final inset = isMobile ? 12.0 : 32.0;
    final loading = controller.activeId != null && session == null;

    return Column(
      children: [
        _WorkspaceBar(
          isMobile: isMobile,
          isLoading: loading,
          monitorOpen: showMonitor,
          onToggleMonitor: inWorkMode ? _toggleMonitor : null,
        ),
        if (controller.debugRecording)
          const Flexible(
            key: Key('request-debug-panel'),
            child: RequestDebugPanel(),
          ),
        Expanded(
          key: const Key('chat-workspace'),
          flex: showMonitor ? 2 : 1,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                ChatPaper(option: controller.settings.chatBackground),
                Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, area) {
                          final docked = showMonitor && area.maxWidth >= 880;
                          final covered = showMonitor && !docked;
                          final panelWidth = (area.maxWidth * .34).clamp(
                            320.0,
                            420.0,
                          );
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  right: docked ? panelWidth : 0,
                                ),
                                child: Offstage(
                                  offstage: covered,
                                  child: ExcludeFocus(
                                    excluding: covered,
                                    child: session == null || visible.isEmpty
                                        ? loading
                                              ? Center(
                                                  child: Text(
                                                    scope.strings.noMessages,
                                                  ),
                                                )
                                              : const WelcomeView()
                                        : Align(
                                            alignment: Alignment.topCenter,
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 820,
                                              ),
                                              child: ListenableBuilder(
                                                listenable: controller,
                                                builder: (_, _) => MessageList(
                                                  session: session,
                                                  visible: visible,
                                                  versions: versions,
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              if (showMonitor)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  bottom: 0,
                                  width: docked ? panelWidth : area.maxWidth,
                                  child: GenerationMonitor(
                                    onClose: _toggleMonitor,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        inset,
                        // Reserved band: the centred notice draws in this gap
                        // instead of covering the composer or the messages.
                        showMonitor ? 0 : 6,
                        inset,
                        isMobile ? 8 : 16,
                      ),
                      child: Align(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 780,
                            maxHeight:
                                (constraints.maxHeight *
                                        (showMonitor ? .36 : .86))
                                    .clamp(0.0, 380.0),
                          ),
                          child: SingleChildScrollView(
                            reverse: true,
                            child: ChatInput(
                              key: ValueKey(controller.draftKey),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkspaceBar extends StatelessWidget {
  const _WorkspaceBar({
    required this.isMobile,
    required this.isLoading,
    required this.monitorOpen,
    required this.onToggleMonitor,
  });

  final bool isMobile;
  final bool isLoading;
  final bool monitorOpen;
  final VoidCallback? onToggleMonitor;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.controller;
    final title = controller.activeSession?.title.trim() ?? '';
    final strings = scope.strings;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scope.palette.lineInk, width: Lineism.base),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (!isMobile) ...[
            Expanded(
              child: Row(
                children: [
                  _PressLight(live: controller.activeStreaming),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      title.isEmpty ? strings.sessionTitlePlaceholder : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Lineism.display.copyWith(
                        fontSize: 21,
                        color: scope.palette.lineInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Semantics(
              label: strings.chatMode,
              child: SegmentedButton<ChatMode>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 14),
                ),
                segments: [
                  ButtonSegment(
                    value: ChatMode.chat,
                    label: Text(strings.modeChat),
                  ),
                  ButtonSegment(
                    value: ChatMode.work,
                    label: Text(strings.modeWork),
                  ),
                ],
                selected: {controller.chatMode},
                onSelectionChanged: controller.activeStreaming || isLoading
                    ? null
                    : (values) async {
                        final mode = values.single;
                        try {
                          await controller.setChatMode(mode);
                          if (!context.mounted) return;
                          showCenteredNotice(
                            context,
                            CenteredNotice.label(
                              dimension: strings.chatMode,
                              value: mode == ChatMode.chat
                                  ? strings.modeChat
                                  : strings.modeWork,
                              zh: strings.isZh,
                            ),
                          );
                        } catch (_) {
                          if (context.mounted) {
                            showToast(context, strings.settingsSaveFailed);
                          }
                        }
                      },
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (onToggleMonitor != null)
            AppIconButton(
              key: const Key('generation-monitor-toggle'),
              icon: monitorOpen
                  ? Icons.monitor_heart
                  : Icons.monitor_heart_outlined,
              tooltip: monitorOpen
                  ? strings.closeGenerationMonitor
                  : strings.generationMonitor,
              size: 44,
              onPressed: onToggleMonitor,
            ),
          AppIconButton(
            key: const Key('request-debug'),
            icon: controller.debugRecording
                ? Icons.bug_report
                : Icons.bug_report_outlined,
            tooltip: controller.debugRecording
                ? (strings.isZh ? '关闭请求调试' : 'Close request debug')
                : (strings.isZh ? '打开请求调试' : 'Open request debug'),
            size: 44,
            onPressed: () =>
                controller.setDebugRecording(!controller.debugRecording),
          ),
          AppIconButton(
            key: const Key('chat-background'),
            icon: Icons.grid_on_outlined,
            tooltip: strings.chatBackground,
            size: 44,
            onPressed: () => showChatBackgrounds(context),
          ),
        ],
      ),
    );
  }
}

/// A small press light: cobalt square at rest, vermilion while printing.
class _PressLight extends StatelessWidget {
  const _PressLight({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).palette;
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: still ? Duration.zero : const Duration(milliseconds: 220),
      width: 9,
      height: 9,
      transform: Matrix4.rotationZ(live ? .785 : 0),
      transformAlignment: Alignment.center,
      color: live ? p.signal : p.accent,
    );
  }
}
