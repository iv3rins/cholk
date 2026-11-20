import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';

/// Shared dialog chrome; each settings surface owns its form state.
class SettingsFrame extends StatelessWidget {
  const SettingsFrame({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.onClose,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    // While the keyboard is open every pixel above it goes to the form.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: typing ? 8 : 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 740),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: scope.palette.lineInk,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: scope.strings.close,
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Divider(height: Lineism.hair, color: scope.palette.lineRule),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(22, typing ? 12 : 20, 22, 22),
                child: body,
              ),
            ),
            Divider(height: Lineism.hair, color: scope.palette.lineRule),
            Padding(
              padding: EdgeInsets.fromLTRB(22, typing ? 6 : 12, 22, typing ? 8 : 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppScope.of(context).palette.lineInk,
        ),
      ),
    );
  }
}
