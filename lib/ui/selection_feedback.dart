import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/lineism.dart';

/// A temporary, non-interactive notice that names the selected value.
class CenteredNotice extends StatefulWidget {
  const CenteredNotice({
    super.key,
    required this.message,
    required this.palette,
    this.onHidden,
    this.duration = const Duration(milliseconds: 2200),
  });

  final String message;
  final AppPalette palette;
  final VoidCallback? onHidden;
  final Duration duration;

  /// Names the value that took effect, e.g. `Model: deepseek-chat`.
  /// Chinese uses the full-width colon so the line reads as one phrase.
  static String label({
    required String dimension,
    required String value,
    required bool zh,
  }) => '$dimension${zh ? '\uFF1A' : ': '}$value';

  @override
  State<CenteredNotice> createState() => _CenteredNoticeState();
}

class _CenteredNoticeState extends State<CenteredNotice> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(CenteredNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.duration != widget.duration) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(widget.duration, () {
      if (mounted) widget.onHidden?.call();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: widget.message,
        child: Container(
          key: const Key('centered-notice'),
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: palette.background,
            border: Border.all(color: palette.lineInk, width: Lineism.base),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 18, color: palette.lineInk),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: Lineism.serif.copyWith(
                    fontSize: 15,
                    height: 1.45,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

OverlayEntry? _activeNotice;

/// Replaces the current notice. By default it centers above the composer.
void showCenteredNotice(
  BuildContext context,
  String message, {
  bool centerInViewport = false,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final palette = AppScope.maybeOf(context)?.palette;
  if (overlay == null || palette == null) return;
  final anchor = context.findRenderObject();
  final composerTop = anchor is RenderBox && anchor.hasSize
      ? anchor.localToGlobal(Offset.zero).dy
      : MediaQuery.sizeOf(context).height * .5;
  final topPadding = MediaQuery.paddingOf(context).top;

  // The band runs from the top safe area down to the composer, so the notice
  // never covers the draft field nor the messages above it.
  final bandHeight = centerInViewport
      ? MediaQuery.sizeOf(context).height
      : composerTop - topPadding;
  hideCenteredNotice();
  if (bandHeight < 48) return;

  late final OverlayEntry notice;
  void remove() {
    if (notice.mounted) notice.remove();
    if (identical(_activeNotice, notice)) _activeNotice = null;
  }

  notice = OverlayEntry(
    builder: (context) => Positioned(
      left: 16,
      right: 16,
      top: 0,
      height: bandHeight,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: Center(
          child: CenteredNotice(
            message: message,
            palette: palette,
            onHidden: remove,
          ),
        ),
      ),
    ),
  );
  _activeNotice = notice;
  overlay.insert(notice);
}

/// Dismisses any visible centred notice; used when leaving the chat.
void hideCenteredNotice() {
  _activeNotice?.remove();
  _activeNotice = null;
}
