import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../../models/chat_models.dart';
import '../../models/chat_preferences.dart';
import 'assistant_message.dart';
import 'user_message.dart';

class MessageList extends StatefulWidget {
  const MessageList({
    super.key,
    required this.session,
    required this.visible,
    required this.versions,
  });

  final ChatSession session;
  final List<ChatMessage> visible;
  final Map<String, MessageVersions> versions;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scrollController = ScrollController();
  Map<String, int> _messageIndexes = const {};
  int _latestPrompt = -1;
  Map<String, int> _arrivals = const {};
  Timer? _arrivalTimer;
  bool _showScrollButton = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _indexMessages();
    final visible = widget.visible;
    if (_latestPrompt >= 0 &&
        visible
            .skip(_latestPrompt + 1)
            .any(
              (message) => message is AssistantMessage && message.isStreaming,
            )) {
      _recordArrivals(visible.skip(_latestPrompt));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() {
    _arrivalTimer?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  bool get _nearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 160;
  }

  void _onScroll() {
    final shouldShow =
        _scrollController.hasClients &&
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels >
            220;
    if (shouldShow != _showScrollButton) {
      setState(() => _showScrollButton = shouldShow);
    }
  }

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged = oldWidget.session.id != widget.session.id;
    final visible = widget.visible;
    if (sessionChanged) {
      _arrivalTimer?.cancel();
      _arrivals = const {};
    } else if (oldWidget.visible != visible) {
      final added = visible.where(
        (message) => !_messageIndexes.containsKey(message.id),
      );
      if (added.isNotEmpty) _recordArrivals(added);
    }
    if (oldWidget.visible != visible) _indexMessages();
    if (sessionChanged ||
        _nearBottom ||
        oldWidget.visible.length != visible.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    }
  }

  void _indexMessages() {
    final visible = widget.visible;
    _messageIndexes = {
      for (var index = 0; index < visible.length; index++)
        visible[index].id: index,
    };
    _latestPrompt = visible.lastIndexWhere((message) => message is UserMessage);
  }

  void _jumpToBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _recordArrivals(Iterable<ChatMessage> messages) {
    var order = 0;
    _arrivals = {for (final message in messages) message.id: order++};
    _arrivalTimer?.cancel();
    _arrivalTimer = Timer(const Duration(milliseconds: 300), () {
      _arrivals = const {};
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.controller;
    final palette = scope.palette;
    final visible = widget.visible;
    final streaming = controller.isStreaming(widget.session.id);
    final groupChat = widget.session.mode == ChatMode.chat;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: visible.length,
          findChildIndexCallback: (key) =>
              key is ValueKey<String> ? _messageIndexes[key.value] : null,
          itemBuilder: (context, index) {
            final message = visible[index];
            final version = widget.versions[message.id];
            final Widget tile;
            if (message is UserMessage) {
              tile = UserMessageTile(
                message: message,
                versions: version,
                onEdit: (text) =>
                    controller.editPrompt(message.id, text, message.files),
                onSwitchVersion: controller.switchVersion,
                streaming: streaming,
                groupChat: groupChat,
              );
            } else if (message is AssistantMessage) {
              tile = AssistantMessageTile(
                message: message,
                streaming: streaming && message.isStreaming,
                groupChat: groupChat,
                actionsEnabled: !streaming,
                canRequestAgain: !streaming && controller.canReplyAs(message),
                canContinue: index > _latestPrompt,
                versions: version,
                onRegenerate: () => controller.regenerate(message.id),
                onContinue: () => controller.continueReply(message.id),
                onSwitchVersion: controller.switchVersion,
              );
            } else {
              return const SizedBox.shrink();
            }
            final order = _arrivals[message.id];
            return _MessageArrival(
              key: ValueKey(message.id),
              order: reduceMotion ? null : order,
              child: tile,
            );
          },
        ),
        if (_showScrollButton)
          Positioned(
            right: 8,
            bottom: 12,
            child: Container(
              decoration: BoxDecoration(
                color: palette.background,
                border: Border.all(
                  color: palette.lineRule,
                  width: Lineism.base,
                ),
              ),
              child: InkWell(
                onTap: reduceMotion
                    ? _jumpToBottom
                    : () => _scrollController.animateTo(
                        _scrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                      ),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    size: 17,
                    color: palette.lineInk,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MessageArrival extends StatelessWidget {
  const _MessageArrival({super.key, required this.order, required this.child});

  final int? order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: order == null ? 1 : 0, end: 1),
      duration: Duration(milliseconds: 200 + (order ?? 0).clamp(0, 3) * 28),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, progress, child) => Opacity(
        opacity: .55 + .45 * progress,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - progress)),
          child: child,
        ),
      ),
    );
  }
}
