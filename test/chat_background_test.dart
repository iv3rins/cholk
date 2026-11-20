import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/models/chat_preferences.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/storage/settings_store.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/app_scope.dart';
import 'package:deepseek_chat/ui/chat/chat_page.dart';
import 'package:deepseek_chat/ui/settings/settings_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ChatController> _pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(800, 1000),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = ChatController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(lightPalette),
      builder: (context, child) => ListenableBuilder(
        listenable: controller,
        builder: (_, _) => AppScope(
          controller: controller,
          strings: const S(false),
          palette: lightPalette,
          child: child!,
        ),
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

final _openSettings = Builder(
  builder: (context) => Scaffold(
    body: TextButton(
      onPressed: () => showSettingsDialog(context),
      child: const Text('Open settings'),
    ),
  ),
);

void main() {
  test('image path and dim survive a reload; clearing removes the path', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    var settings = await store.load();
    expect(settings.chatBackgroundImagePath, isNull);
    expect(settings.chatBackgroundDim, defaultChatBackgroundDim);

    await store.setChatBackgroundImage('/docs/chat_background/bg.png');
    await store.setChatBackgroundDim(.7);
    settings = await store.load();
    expect(settings.chatBackgroundImagePath, '/docs/chat_background/bg.png');
    expect(settings.chatBackgroundDim, .7);

    await store.setChatBackgroundImage(null);
    settings = await store.load();
    expect(settings.chatBackgroundImagePath, isNull);
    expect(settings.chatBackgroundDim, .7);
  });

  testWidgets('settings dialog has a labelled chat background entry', (
    tester,
  ) async {
    await _pump(tester, _openSettings);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    final entry = find.byKey(const Key('settings-chat-background'));
    await tester.ensureVisible(entry);
    expect(find.text('Chat background · Upload image'), findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('background-upload')), findsOneWidget);
    expect(find.text('Upload image'), findsOneWidget);
    expect(find.text('Restore default'), findsOneWidget);
  });

  testWidgets('mobile chat header opens the chat background screen', (
    tester,
  ) async {
    await _pump(tester, const ChatPage(), size: const Size(392, 800));

    final entry = find.byKey(const Key('mobile-chat-background'));
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('background-upload')), findsOneWidget);
  });

  testWidgets('restore default clears the picture, dim and pattern', (
    tester,
  ) async {
    final controller = await _pump(tester, _openSettings);
    await controller.setChatBackgroundImage('/missing/chat_background/bg.png');
    await controller.setChatBackgroundDim(.8);
    await controller.setChatBackground(ChatBackground.grid);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('settings-chat-background'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('background-dim')), findsOneWidget);
    expect(find.text('Replace image'), findsOneWidget);

    // Deleting the stored file is real I/O, so let it run outside fake time.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('background-restore-default')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(controller.settings.chatBackgroundImagePath, isNull);
    expect(controller.settings.chatBackgroundDim, defaultChatBackgroundDim);
    expect(controller.settings.chatBackground, ChatBackground.plain);
    expect(find.byKey(const Key('background-dim')), findsNothing);
    expect(find.text('Upload image'), findsOneWidget);

    final saved = await SettingsStore().load();
    expect(saved.chatBackgroundImagePath, isNull);
    expect(saved.chatBackgroundDim, defaultChatBackgroundDim);
    expect(saved.chatBackground, ChatBackground.plain);
  });
}
