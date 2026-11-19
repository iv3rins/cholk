import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../chat/reply_view.dart';
import '../../i18n/strings.dart';
import '../../models/chat_models.dart';
import '../../theme/app_theme.dart';
import '../common.dart';
import '../../theme/lineism.dart';
import '../participants/participant_avatar.dart';
import 'group_message.dart';
import 'markdown_view.dart';

class AssistantMessageTile extends StatefulWidget {
  const AssistantMessageTile({
    super.key,
    required this.message,
    required this.streaming,
    required this.versions,
    required this.onRegenerate,
    required this.onContinue,
    required this.onSwitchVersion,
    this.groupChat = false,
    this.actionsEnabled = true,
    this.canRequestAgain = true,
    this.canContinue = true,
  });

  final AssistantMessage message;
  final bool streaming;
  final bool groupChat;
  final bool actionsEnabled;
  final bool canRequestAgain;
  final bool canContinue;
  final MessageVersions? versions;
  final VoidCallback onRegenerate;
  final VoidCallback onContinue;
  final void Function(String messageId) onSwitchVersion;

  @override
  State<AssistantMessageTile> createState() => _AssistantMessageTileState();
}

class _AssistantMessageTileState extends State<AssistantMessageTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final strings = scope.strings;
    final reply = widget.message;
    final view = buildReplyView(reply, streaming: widget.streaming);
    final hasAnswer = view.hasAnswer;
    final hasError = reply.status == ReplyStatus.error;
    final error = reply.error;
    final messageText = reply.text;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final name = reply.participantName ?? strings.defaultAssistant;
    final canRequestAgain = widget.actionsEnabled && widget.canRequestAgain;
    final waiting =
        (reply.status == ReplyStatus.pending || widget.streaming) &&
        view.steps.isEmpty &&
        !hasAnswer;
    final isTouch =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;

    final avatar = ParticipantAvatar(
      name: name,
      avatarBase64: reply.participantAvatarBase64,
    );
    final header = Padding(
      padding: EdgeInsets.only(bottom: widget.groupChat ? 4 : 12),
      child: Row(
        children: [
          if (!widget.groupChat) ...[avatar, const SizedBox(width: 10)],
          Flexible(
            child: Text(name, style: Theme.of(context).textTheme.titleSmall),
          ),
          if (waiting) ...[
            const SizedBox(width: 12),
            _WaitingStroke(color: palette.lineSignal, label: strings.waiting),
          ] else if (widget.streaming) ...[
            const SizedBox(width: 12),
            Semantics(
              label: strings.waiting,
              child: SizedBox(
                width: 6,
                height: 6,
                child: ColoredBox(color: palette.lineSignal),
              ),
            ),
          ],
        ],
      ),
    );
    final content = <Widget>[
      for (final step in view.steps) _buildStep(context, step, view),
      if (hasAnswer)
        MarkdownView(
          data: view.answerMarkdown!,
          onCitation: (index) => _showSources(context, view.sources, index),
        ),
      if (reply.stopReason == StopReason.refusal)
        _Notice(
          palette: palette,
          icon: Icons.info_outline_rounded,
          message: strings.replyRefusal,
          color: palette.textSecondary,
        ),
      if (hasError)
        _ErrorNotice(
          message: error == null
              ? strings.errorOccurred
              : scope.controller.settings.isAdvancedMode
              ? error.displayMessage
              : plainReplyError(error, strings.isZh),
          palette: palette,
          onRetry: canRequestAgain ? widget.onRegenerate : null,
          strings: strings,
        ),
      if (!hasAnswer && !hasError && reply.status == ReplyStatus.stopped)
        _Notice(
          palette: palette,
          icon: Icons.stop_circle_outlined,
          message: strings.replyStopped,
          color: palette.textSecondary,
        ),
      if (view.sources.isNotEmpty)
        _SourcesBar(
          sources: view.sources,
          palette: palette,
          strings: strings,
          onTap: () => _showSources(context, view.sources, null),
        ),
    ];
    final message = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (widget.groupChat)
          GroupBubble(
            child: content.isEmpty
                ? Text(waiting ? strings.waiting : strings.noReplyText)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: content,
                  ),
          )
        else
          ...content,
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AnimatedOpacity(
              opacity: _hovering || widget.streaming || isTouch ? 1 : 0.65,
              duration: Duration(milliseconds: reduceMotion ? 0 : 150),
              child: Wrap(
                children: [
                  if (messageText.isNotEmpty)
                    AppIconButton(
                      icon: Icons.copy_rounded,
                      tooltip: strings.copy,
                      size: 44,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: messageText));
                        showToast(context, strings.copied);
                      },
                    ),
                  if (canRequestAgain && !widget.streaming && !hasError)
                    AppIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: strings.regenerate,
                      size: 44,
                      onPressed: widget.onRegenerate,
                    ),
                  if (canRequestAgain &&
                      widget.canContinue &&
                      reply.canContinue)
                    AppIconButton(
                      icon: Icons.play_arrow_rounded,
                      tooltip: strings.continueReply,
                      size: 44,
                      onPressed: widget.onContinue,
                    ),
                ],
              ),
            ),
            if (widget.actionsEnabled &&
                widget.versions != null &&
                widget.versions!.ids.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: VersionSwitcher(
                  index: widget.versions!.index,
                  count: widget.versions!.ids.length,
                  onPrevious: () => widget.onSwitchVersion(
                    widget.versions!.ids[widget.versions!.index - 1],
                  ),
                  onNext: () => widget.onSwitchVersion(
                    widget.versions!.ids[widget.versions!.index + 1],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: widget.groupChat
            ? GroupMessage(avatar: avatar, child: message)
            : message,
      ),
    );
  }

  Widget _buildStep(BuildContext context, ReplyStep step, ReplyView view) {
    final scope = AppScope.of(context);
    return switch (step) {
      ThinkingStep() => _ThinkingStepView(
        step: step,
        active: _isThinking(step),
        streaming: widget.streaming,
        hasAnswer: view.hasAnswer,
      ),
      SearchStep() => _SearchStepView(step: step),
      ReadLinkStep() => _LinkStepView(
        title: scope.strings.readingLink,
        links: step.links,
      ),
      OpenPageStep() => _LinkStepView(
        title: scope.strings.openedPages,
        links: step.pages,
      ),
      FindInPageStep() => _FindStepView(step: step),
      TextStep() => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: MarkdownView(data: step.markdown),
      ),
    };
  }

  bool _isThinking(ThinkingStep step) {
    final reply = widget.message;
    final block = reply.blocks.reversed
        .skipWhile((block) => block is TextBlock && block.isTemplate)
        .firstOrNull;
    return widget.streaming &&
        reply.stopReason == null &&
        block is ThinkingBlock &&
        block.endedAt == null &&
        block.elapsedSeconds == null &&
        block.thinking.trim().isNotEmpty &&
        identical(step.blocks.last, block);
  }

  void _showSources(
    BuildContext context,
    List<ReplySource> sources,
    int? highlight,
  ) {
    if (sources.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) =>
          _SourceSheet(sources: sources, highlight: highlight),
    );
  }
}

class _WaitingStroke extends StatefulWidget {
  const _WaitingStroke({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  State<_WaitingStroke> createState() => _WaitingStrokeState();
}

class _WaitingStrokeState extends State<_WaitingStroke>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 740),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      child: SizedBox(
        width: 22,
        height: 2,
        child: AnimatedBuilder(
          animation: _controller,
          child: ColoredBox(color: widget.color),
          builder: (_, child) => FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor:
                .3 + .7 * Curves.easeInOut.transform(_controller.value),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ThinkingStepView extends StatefulWidget {
  const _ThinkingStepView({
    required this.step,
    required this.active,
    required this.streaming,
    required this.hasAnswer,
  });

  final ThinkingStep step;
  final bool active;
  final bool streaming;
  final bool hasAnswer;

  @override
  State<_ThinkingStepView> createState() => _ThinkingStepViewState();
}

class _ThinkingStepViewState extends State<_ThinkingStepView> {
  bool? _expanded;
  bool _manuallyToggled = false;

  bool get _isExpanded => _expanded ?? (!widget.hasAnswer && widget.streaming);

  @override
  void didUpdateWidget(_ThinkingStepView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_manuallyToggled && oldWidget.hasAnswer != widget.hasAnswer) {
      _expanded = !widget.hasAnswer && widget.streaming;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final strings = scope.strings;
    final seconds = widget.step.seconds;
    final text = widget.step.blocks.map((block) => block.thinking).join('\n\n');
    final title = widget.active
        ? strings.thinking
        : seconds == null
        ? strings.thinkingSwitch
        : strings.thoughtFor(seconds);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: palette.lineRule, width: Lineism.base),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.zero,
            onTap: () => setState(() {
              _manuallyToggled = true;
              _expanded = !_isExpanded;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 15,
                    color: palette.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.5,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  if (widget.active)
                    SizedBox(
                      key: const ValueKey('thinking-thread'),
                      width: 24,
                      height: 16,
                      child: MediaQuery.disableAnimationsOf(context)
                          ? CustomPaint(
                              painter: _ThinkingThreadPainter(palette.signal),
                            )
                          : _AnimatedThinkingThread(color: palette.signal),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    _isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: palette.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Opacity(opacity: 0.78, child: MarkdownView(data: text)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedThinkingThread extends StatefulWidget {
  const _AnimatedThinkingThread({required this.color});

  final Color color;

  @override
  State<_AnimatedThinkingThread> createState() =>
      _AnimatedThinkingThreadState();
}

class _AnimatedThinkingThreadState extends State<_AnimatedThinkingThread>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ThinkingThreadPainter(widget.color, _motion));
}

class _ThinkingThreadPainter extends CustomPainter {
  _ThinkingThreadPainter(this.color, [this.motion]) : super(repaint: motion);

  final Color color;
  final Animation<double>? motion;

  @override
  void paint(Canvas canvas, Size size) {
    final pull = Curves.easeInOutSine.transform(motion?.value ?? 0.45);
    final thread = Path();
    final center = size.center(Offset.zero);
    const samples = 80;
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final angle = (2.7 - 0.32 * pull) * 2 * math.pi * t + 0.3;
      final radius = (1 - 0.79 * t) * (1 - 0.33 * pull);
      final x =
          center.dx +
          1.7 * pull +
          10.4 * radius * math.cos(angle) +
          0.5 * math.sin(3 * angle) * radius;
      final y =
          center.dy + 6.0 * radius * math.sin(angle) - 0.15 * (x - center.dx);
      if (i == 0) {
        thread.moveTo(x, y);
      } else {
        thread.lineTo(x, y);
      }
    }
    canvas.drawPath(
      thread,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = Lineism.base
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ThinkingThreadPainter oldDelegate) =>
      color != oldDelegate.color || motion != oldDelegate.motion;
}

class _SearchStepView extends StatelessWidget {
  const _SearchStepView({required this.step});

  final SearchStep step;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final strings = scope.strings;
    final title = step.queries
        .where((query) => query.trim().isNotEmpty)
        .join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: palette.lineRule, width: Lineism.base),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('search-${step.key}'),
          initiallyExpanded: step.status == ToolStatus.wip,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Icon(
            Icons.travel_explore_rounded,
            size: 17,
            color: palette.textTertiary,
          ),
          title: Text(
            title.isEmpty ? strings.searchResults : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.5,
              color: palette.textSecondary,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (step.status == ToolStatus.wip)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              else
                Text(
                  '${step.results.length}',
                  style: TextStyle(fontSize: 12, color: palette.textTertiary),
                ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: palette.textTertiary,
              ),
            ],
          ),
          children: [
            if (step.queries
                .where((query) => query.trim().isNotEmpty)
                .isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final query
                          in step.queries
                              .where((query) => query.trim().isNotEmpty)
                              .toSet())
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            border: Border.all(
                              color: palette.lineRule,
                              width: Lineism.hair,
                            ),
                          ),
                          child: Text(
                            query,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (step.results.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  step.status == ToolStatus.wip
                      ? strings.searching
                      : strings.noSources,
                  style: TextStyle(fontSize: 13, color: palette.textTertiary),
                ),
              )
            else
              Column(
                children: [
                  for (final source in step.results) _SourceRow(source: source),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkStepView extends StatelessWidget {
  const _LinkStepView({required this.title, required this.links});

  final String title;
  final List<PageItem> links;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.link_rounded,
              size: 15,
              color: palette.textTertiary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
                for (final link in links)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: InkWell(
                      onTap: link.url.isEmpty
                          ? null
                          : () => openExternalUrl(link.url),
                      child: Text(
                        link.title.isEmpty ? link.url : link.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: link.url.isEmpty
                              ? palette.textTertiary
                              : palette.lineInk,
                          decoration: link.url.isEmpty
                              ? null
                              : TextDecoration.underline,
                          decorationColor: palette.lineInk,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FindStepView extends StatelessWidget {
  const _FindStepView({required this.step});
  final FindInPageStep step;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            Icons.manage_search_rounded,
            size: 15,
            color: palette.textTertiary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              step.patterns.map((item) => item.pattern).join(' · '),
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcesBar extends StatelessWidget {
  const _SourcesBar({
    required this.sources,
    required this.palette,
    required this.strings,
    required this.onTap,
  });

  final List<ReplySource> sources;
  final AppPalette palette;
  final S strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final source in sources.take(6))
            Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border.all(
                  color: palette.lineRule,
                  width: Lineism.hair,
                ),
              ),
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${source.index}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: palette.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          source.siteName.isEmpty
                              ? source.title
                              : source.siteName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (sources.length > 6)
            Text(
              '+${sources.length - 6}',
              style: TextStyle(fontSize: 12, color: palette.textTertiary),
            ),
        ],
      ),
    );
  }
}

class _SiteIcon extends StatelessWidget {
  const _SiteIcon({required this.source});

  final ReplySource source;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    final iconUrl = source.siteIcon;
    final fallback = Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: palette.lineRule, width: Lineism.hair),
      ),
      child: Text(
        source.siteName.isEmpty
            ? '?'
            : source.siteName.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: palette.textTertiary,
        ),
      ),
    );
    if (iconUrl == null || iconUrl.isEmpty) return fallback;
    final uri = Uri.tryParse(iconUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: Image.network(
        iconUrl,
        width: 16,
        height: 16,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source});
  final ReplySource source;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return InkWell(
      onTap: source.url.isEmpty ? null : () => openExternalUrl(source.url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border.all(
                  color: palette.lineRule,
                  width: Lineism.hair,
                ),
              ),
              child: Text(
                '${source.index}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: palette.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SiteIcon(source: source),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          source.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (source.snippet != null && source.snippet!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        source.snippet!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: palette.textTertiary,
                        ),
                      ),
                    ),
                  if (source.siteName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        source.siteName,
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.textCaption,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.sources, this.highlight});

  final List<ReplySource> sources;
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(color: palette.lineRule, width: Lineism.base),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      scope.strings.reference,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.close_rounded,
                    tooltip: scope.strings.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                itemCount: sources.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: palette.border),
                itemBuilder: (context, index) {
                  final source = sources[index];
                  final highlighted = highlight == source.index;
                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: highlighted
                              ? palette.lineSignal
                              : Colors.transparent,
                          width: Lineism.emphasis,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _SourceRow(source: source),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.palette,
    required this.icon,
    required this.message,
    required this.color,
  });

  final AppPalette palette;
  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 14, height: 1.6, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({
    required this.message,
    required this.palette,
    required this.onRetry,
    required this.strings,
  });

  final String message;
  final AppPalette palette;
  final VoidCallback? onRetry;
  final S strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: palette.error,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message.isEmpty ? strings.errorOccurred : message,
              style: TextStyle(fontSize: 14, height: 1.6, color: palette.error),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(strings.retry, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
