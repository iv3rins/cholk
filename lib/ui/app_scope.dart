import 'package:material_ui/material_ui.dart';

import '../i18n/strings.dart';
import '../state/chat_controller.dart';
import '../theme/app_theme.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.controller,
    required this.strings,
    required this.palette,
    required super.child,
  });

  final ChatController controller;
  final S strings;
  final AppPalette palette;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing');
    return scope!;
  }

  /// For overlay builders whose context sits outside the app scope subtree.
  static AppScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>();

  @override
  bool updateShouldNotify(AppScope oldWidget) => true;
}
