import 'package:material_ui/material_ui.dart';

import 'i18n/strings.dart';
import 'state/chat_controller.dart';
import 'theme/app_theme.dart';
import 'ui/app_scope.dart';
import 'ui/home/main_screen.dart';

export 'ui/app_scope.dart' show AppScope;

class DeepSeekChatApp extends StatelessWidget {
  const DeepSeekChatApp({super.key, required this.controller});

  static final _lightTheme = buildTheme(lightPalette);
  static final _darkTheme = buildTheme(darkPalette);

  final ChatController controller;

  ThemeMode get _themeMode => switch (controller.settings.themePreference) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.workspaceChanges,
      builder: (context, _) {
        final strings = S(controller.settings.isZh);
        return MaterialApp(
          title: 'Cholk',
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: _themeMode,
          locale: controller.settings.isZh
              ? const Locale('zh', 'CN')
              : const Locale('en', 'US'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const MainScreen(),
          builder: (context, child) {
            final palette = Theme.of(context).brightness == Brightness.dark
                ? darkPalette
                : lightPalette;
            return AppScope(
              controller: controller,
              strings: strings,
              palette: palette,
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}
