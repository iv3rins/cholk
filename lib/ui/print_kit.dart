import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/lineism.dart';
import 'app_scope.dart';

/// Shared pieces of the printed look: a hard-offset slab, a halftone field,
/// registration marks, and a staggered entrance. Kept free of business state.

/// A block of ink with a hard second-drum offset behind it. Pressing it
/// "closes the registration": the face slides onto its shadow.
class PrintSlab extends StatefulWidget {
  const PrintSlab({
    super.key,
    required this.child,
    required this.onPressed,
    this.face,
    this.offsetColor,
    this.offset = Lineism.misprint,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Color? face;
  final Color? offsetColor;
  final Offset offset;
  final EdgeInsets padding;
  final String? semanticLabel;

  @override
  State<PrintSlab> createState() => _PrintSlabState();
}

class _PrintSlabState extends State<PrintSlab> {
  bool _down = false;
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).palette;
    final still = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.onPressed != null;
    final face = enabled ? (widget.face ?? p.accent) : p.border;
    final lift = !enabled
        ? Offset.zero
        : _down
        ? Offset.zero
        : _hover || _focus
        ? widget.offset * 1.6
        : widget.offset;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTap: widget.onPressed,
          child: Padding(
            padding: EdgeInsets.only(
              right: widget.offset.dx * 1.6,
              bottom: widget.offset.dy * 1.6,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Transform.translate(
                    offset: lift,
                    child: ColoredBox(
                      color: enabled
                          ? (widget.offsetColor ?? p.signal)
                          : Colors.transparent,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(
                    _down ? widget.offset.dx : 0,
                    _down ? widget.offset.dy : 0,
                    0,
                  ),
                  padding: widget.padding,
                  decoration: BoxDecoration(
                    color: face,
                    border: _focus
                        ? Border.all(color: p.textPrimary, width: Lineism.base)
                        : null,
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: p.onAccent),
                    child: IconTheme.merge(
                      data: IconThemeData(color: p.onAccent),
                      child: widget.child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A riso halftone: dots that grow toward one corner, printed in [color].
class HalftoneField extends StatelessWidget {
  const HalftoneField({
    super.key,
    required this.color,
    this.spacing = 11,
    this.origin = Alignment.topRight,
    this.reach = .9,
    this.maxRadius = 2.6,
  });

  final Color color;
  final double spacing;
  final Alignment origin;
  final double reach;
  final double maxRadius;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _HalftonePainter(color, spacing, origin, reach, maxRadius),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _HalftonePainter extends CustomPainter {
  const _HalftonePainter(
    this.color,
    this.spacing,
    this.origin,
    this.reach,
    this.maxRadius,
  );

  final Color color;
  final double spacing;
  final Alignment origin;
  final double reach;
  final double maxRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()..color = color;
    final anchor = origin.alongSize(size);
    final span = size.longestSide * reach;
    // Rotated screen, as a riso drum would print it.
    const angle = .26;
    final c = math.cos(angle), s = math.sin(angle);
    final extent = size.longestSide * 1.5;
    for (var v = -extent; v < extent; v += spacing) {
      for (var u = -extent; u < extent; u += spacing) {
        final x = size.width / 2 + u * c - v * s;
        final y = size.height / 2 + u * s + v * c;
        if (x < -spacing ||
            y < -spacing ||
            x > size.width + spacing ||
            y > size.height + spacing) {
          continue;
        }
        final t = 1 - ((Offset(x, y) - anchor).distance / span);
        if (t <= .02) continue;
        canvas.drawCircle(Offset(x, y), maxRadius * t * t, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HalftonePainter old) =>
      old.color != color ||
      old.spacing != spacing ||
      old.origin != origin ||
      old.reach != reach ||
      old.maxRadius != maxRadius;
}

/// A printer's registration target.
class RegistrationMark extends StatelessWidget {
  const RegistrationMark({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? AppScope.of(context).palette.textPrimary;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _RegistrationPainter(ink),
      ),
    );
  }
}

class _RegistrationPainter extends CustomPainter {
  const _RegistrationPainter(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final line = Paint()
      ..color = ink
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(c, r * .55, line);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), line);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), line);
  }

  @override
  bool shouldRepaint(_RegistrationPainter old) => old.ink != ink;
}

/// One entrance for a whole page: children rise and settle in order.
/// Driven by a single controller so the cost is one ticker per page.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.children,
    this.step = const Duration(milliseconds: 90),
    this.each = const Duration(milliseconds: 520),
    this.delay = Duration.zero,
    this.rise = 14,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final Duration step;
  final Duration each;
  final Duration delay;
  final double rise;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  );
  bool _started = false;

  Duration get _total =>
      widget.delay +
      widget.each +
      widget.step * math.max(0, widget.children.length - 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _total.inMicroseconds.toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.crossAxisAlignment,
      children: [
        for (final (i, child) in widget.children.indexed)
          _Rise(
            animation: CurvedAnimation(
              parent: _controller,
              curve: Interval(
                (widget.delay + widget.step * i).inMicroseconds / total,
                (widget.delay + widget.step * i + widget.each).inMicroseconds /
                    total,
                curve: Curves.easeOutCubic,
              ),
            ),
            rise: widget.rise,
            child: child,
          ),
      ],
    );
  }
}

class _Rise extends AnimatedWidget {
  const _Rise({
    required Animation<double> animation,
    required this.rise,
    required this.child,
  }) : super(listenable: animation);

  final double rise;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, rise * (1 - t)),
        child: child,
      ),
    );
  }
}

/// A short mono caption, like a printer's slug line: `NO.03 — 对话`.
class SlugLine extends StatelessWidget {
  const SlugLine(this.text, {super.key, this.color, this.size = 12});

  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).palette;
    return Text(
      text,
      style: Lineism.mono.copyWith(
        fontSize: size,
        color: color ?? p.textTertiary,
        letterSpacing: 1.2,
      ),
    );
  }
}

extension PaletteInk on AppPalette {
  /// Halftone ink that stays quiet in both themes.
  Color get halftone => accent.withValues(alpha: isDark ? .22 : .16);
}
