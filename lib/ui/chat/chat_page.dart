import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../state/chat_controller.dart';
import '../../theme/lineism.dart';
import 'chat_view.dart';
import '../common.dart';
import '../settings/settings_dialog.dart';
import 'sider.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _askedForKey = false;
  ChatController? _deliveryController;
  ModalRoute<dynamic>? _chatRoute;
  AudioPlayer? _deliveryPlayer;
  AudioPlayer? _sendPlayer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context).controller;
    _chatRoute = ModalRoute.of(context);
    if (_deliveryController != controller) {
      _unbindDelivery();
      _deliveryController = controller;
      controller.onReplyDelivered = _playDelivery;
      controller.onMessageAccepted = _playSend;
    }
    if (_askedForKey) return;
    _askedForKey = true;
    if (controller.settings.isAdvancedMode && !controller.hasChatConnection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showSettingsDialog(context);
      });
    }
  }

  Future<void> _playDelivery() async {
    if (_chatRoute?.isCurrent != true) return;
    final visibility = WidgetsBinding.instance.lifecycleState;
    if (visibility == AppLifecycleState.hidden ||
        visibility == AppLifecycleState.paused ||
        visibility == AppLifecycleState.detached) {
      return;
    }
    final player = _deliveryPlayer ??= AudioPlayer();
    await player.play(
      AssetSource('sounds/envelope-delivery.wav'),
      volume: 0.38,
    );
  }

  Future<void> _playSend() async {
    if (!mounted || _chatRoute?.isCurrent != true) return;
    final player = _sendPlayer ??= AudioPlayer();
    await player.play(AssetSource('sounds/message-send.wav'), volume: 0.42);
  }

  void _unbindDelivery() {
    final controller = _deliveryController;
    if (controller == null) return;
    if (controller.onReplyDelivered == _playDelivery) {
      controller.onReplyDelivered = null;
    }
    if (controller.onMessageAccepted == _playSend) {
      controller.onMessageAccepted = null;
    }
  }

  @override
  void dispose() {
    _unbindDelivery();
    for (final player in [_deliveryPlayer, _sendPlayer].nonNulls) {
      unawaited(player.dispose().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.controller;
    final palette = scope.palette;
    final strings = scope.strings;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 900;
    final collapsed = controller.settings.siderCollapsed && !isMobile;
    final activeTitle = controller.activeId == null
        ? ''
        : (controller.summaryFor(controller.activeId!)?.title ?? '');

    final overlayStyle = palette.isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: palette.background,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: palette.background,
        drawer: isMobile
            ? Drawer(
                width: 280,
                backgroundColor: palette.sidebar,
                shape: const RoundedRectangleBorder(),
                child: Sider(
                  mobile: true,
                  onClose: () => Navigator.of(context).pop(),
                ),
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              if (controller.initError)
                Material(
                  color: palette.error.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: palette.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings.initFailed,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    if (!isMobile && !collapsed) const Sider(),
                    if (!isMobile && collapsed) const _CollapsedRail(),
                    Expanded(
                      child: Column(
                        children: [
                          if (isMobile)
                            _MobileHeader(
                              title: activeTitle.isEmpty
                                  ? strings.appName
                                  : activeTitle,
                              onMenu: () =>
                                  _scaffoldKey.currentState?.openDrawer(),
                              onHome: () => Navigator.of(context).maybePop(),
                              onNewChat: controller.newChat,
                            ),
                          Expanded(child: ChatView(isMobile: isMobile)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.title,
    required this.onMenu,
    required this.onHome,
    required this.onNewChat,
  });

  final String title;
  final VoidCallback onMenu;
  final VoidCallback onHome;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: palette.border, width: Lineism.hair),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          AppIconButton(
            icon: Icons.menu_rounded,
            tooltip: scope.strings.expandSider,
            onPressed: onMenu,
            size: 48,
            iconSize: 21,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 170),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, ?current],
              ),
              child: Text(
                title,
                key: ValueKey(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Lineism.display.copyWith(
                  fontSize: 19,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.home_outlined,
            tooltip: scope.strings.backToHome,
            onPressed: onHome,
            size: 48,
            iconSize: 19,
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.edit_square,
            tooltip: scope.strings.newChat,
            onPressed: onNewChat,
            size: 48,
            iconSize: 19,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _CollapsedRail extends StatelessWidget {
  const _CollapsedRail();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.controller;
    final palette = scope.palette;
    return Container(
      width: 52,
      decoration: BoxDecoration(
        color: palette.sidebar,
        border: Border(
          right: BorderSide(color: palette.border, width: Lineism.hair),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          AppIconButton(
            icon: Icons.home_outlined,
            tooltip: scope.strings.backToHome,
            onPressed: () => Navigator.of(context).maybePop(),
            size: 36,
          ),
          const SizedBox(height: 4),
          AppIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: scope.strings.expandSider,
            onPressed: () => controller.setSiderCollapsed(false),
            size: 36,
          ),
          const SizedBox(height: 6),
          AppIconButton(
            icon: Icons.add_rounded,
            tooltip: scope.strings.newChat,
            onPressed: controller.newChat,
            size: 36,
            iconSize: 20,
          ),
          const Spacer(),
          AppIconButton(
            icon: Icons.settings_outlined,
            tooltip: scope.strings.settings,
            onPressed: () => showSettingsDialog(context),
            size: 36,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
