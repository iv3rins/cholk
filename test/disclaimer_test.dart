import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/i18n/strings_notice.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/app_scope.dart';
import 'package:deepseek_chat/ui/settings/disclaimer_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Widget home) async {
  final controller = ChatController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(lightPalette),
      builder: (context, child) => AppScope(
        controller: controller,
        strings: const S(true),
        palette: lightPalette,
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first launch requires accepting the disclaimer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, const DisclaimerGate(child: Text('home')));

    expect(find.byKey(const Key('disclaimer-dialog')), findsOneWidget);
    expect(find.textContaining('破甲'), findsOneWidget);
    expect(await disclaimerAccepted(), isFalse);

    // The barrier does not dismiss it.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('disclaimer-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('disclaimer-accept')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('disclaimer-dialog')), findsNothing);
    expect(await disclaimerAccepted(), isTrue);
  });

  testWidgets('disclaimer can be reopened and closed', (tester) async {
    SharedPreferences.setMockInitialValues({disclaimerAcceptedKey: true});
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDisclaimer(context),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(const S(true).disclaimerTitle), findsOneWidget);
    expect(find.byKey(const Key('disclaimer-accept')), findsNothing);
    await tester.tap(find.text(const S(true).close));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('disclaimer-dialog')), findsNothing);
  });
}
