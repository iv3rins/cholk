import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/lineism.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 32,
    this.iconSize = 18,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.zero,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: onPressed,
          hoverColor: palette.hover,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: iconSize,
              color: onPressed == null
                  ? palette.textCaption
                  : (color ?? palette.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class PillToggle extends StatelessWidget {
  const PillToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: palette.hover,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? palette.lineInk : palette.lineRule,
              width: selected ? Lineism.base : Lineism.hair,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? palette.lineInk : palette.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.4,
                  color: selected ? palette.lineInk : palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VersionSwitcher extends StatelessWidget {
  const VersionSwitcher({
    super.key,
    required this.index,
    required this.count,
    required this.onPrevious,
    required this.onNext,
  });

  final int index;
  final int count;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _arrow(
          context,
          Icons.chevron_left_rounded,
          index > 0 ? onPrevious : null,
          palette,
        ),
        Text(
          '${index + 1}/$count',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 0.3,
            color: palette.textTertiary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        _arrow(
          context,
          Icons.chevron_right_rounded,
          index < count - 1 ? onNext : null,
          palette,
        ),
      ],
    );
  }

  Widget _arrow(
    BuildContext context,
    IconData icon,
    VoidCallback? onTap,
    AppPalette palette,
  ) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.zero,
      child: InkWell(
        borderRadius: BorderRadius.zero,
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(
            icon,
            size: 16,
            color: onTap == null ? palette.textCaption : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = true,
}) async {
  final palette = AppScope.of(context).palette;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(
        message,
        style: TextStyle(color: palette.textSecondary, height: 1.6),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            cancelLabel,
            style: TextStyle(color: palette.textSecondary),
          ),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: destructive ? palette.lineSignal : palette.lineInk,
            side: BorderSide(
              color: destructive ? palette.lineSignal : palette.lineInk,
              width: Lineism.base,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Opens only web links; other schemes (`file:`, `javascript:`, …) are ignored.
Future<void> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String formatSessionDate(int millis, bool zh) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return zh ? '今天' : 'Today';
  if (diff == 1) return zh ? '昨天' : 'Yesterday';
  if (diff < 7) {
    return zh ? '${diff + 1} 天前' : '${diff + 1} days ago';
  }
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
