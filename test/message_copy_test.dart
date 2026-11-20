import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/models/chat_models.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/app_scope.dart';
import 'package:deepseek_chat/ui/chat/assistant_message.dart';
import 'package:deepseek_chat/ui/chat/selection_feedback.dart';
import 'package:deepseek_chat/ui/chat/user_message.dart';

void main() {
  late List<String> copied;

  setUp(() => copied = []);

  Future<ChatController> pump(WidgetTester tester, Widget body) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = ChatController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(lightPalette).copyWith(
          platform: TargetPlatform.android,
        ),
        builder: (context, child) => AppScope(
          controller: controller,
          strings: const S(false),
          palette: lightPalette,
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: body)),
      ),
    );
    return controller;
  }

  testWidgets('long-press assistant message copies markdown source', (
    tester,
  ) async {
    const source = '# Title\n\nSome **bold** answer.';
    final reply = AssistantMessage(
      id: 'a',
      createdAt: 1,
      status: ReplyStatus.done,
    )..blocks.add(TextBlock(text: source));
    await pump(
      tester,
      AssistantMessageTile(
        message: reply,
        streaming: false,
        versions: null,
        onRegenerate: () {},
        onContinue: () {},
        onSwitchVersion: (_) {},
      ),
    );

    // Visible copy button exists on touch, not only on hover.
    expect(find.byTooltip('Copy'), findsWidgets);

    await tester.longPress(find.text('Title'));
    await tester.pumpAndSettle();
    expect(find.text('Select text'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Copy'));
    await tester.pumpAndSettle();

    expect(copied, [source]);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('long-press user message offers select-text page', (
    tester,
  ) async {
    final message = UserMessage(id: 'u', createdAt: 1, content: 'Hello there');
    await pump(
      tester,
      UserMessageTile(
        message: message,
        versions: null,
        onEdit: (_) {},
        onSwitchVersion: (_) {},
      ),
    );

    await tester.longPress(find.text('Hello there'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Copy'));
    await tester.pumpAndSettle();
    expect(copied, ['Hello there']);

    await tester.longPress(find.text('Hello there'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select text'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectMessageTextPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SelectMessageTextPage),
        matching: find.byType(SelectableText),
      ),
      findsOneWidget,
    );
  });
}
