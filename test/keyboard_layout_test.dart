import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/app_scope.dart';
import 'package:deepseek_chat/ui/participants/participant_editor_page.dart';
import 'package:deepseek_chat/ui/persona/persona_editor_page.dart';
import 'package:deepseek_chat/ui/settings/advanced_api_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A phone-sized screen with a software keyboard covering the lower 330 px.
const _keyboard = 330.0;
const _screen = Size(392, 800);
const _keyboardTop = 800.0 - _keyboard;

Future<void> _pump(WidgetTester tester, Widget home) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

Future<void> _expectAboveKeyboard(WidgetTester tester, Finder field) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pump();
  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
  await tester.pumpAndSettle();
  final rect = tester.getRect(field);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(_keyboardTop));
}

void main() {
  testWidgets('API dialog keeps the model field above the keyboard', (
    tester,
  ) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showAdvancedApiSettings(context),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _expectAboveKeyboard(tester, find.byKey(const Key('api-model')));
  });

  testWidgets('persona editor keeps the prompt above the keyboard', (
    tester,
  ) async {
    await _pump(tester, const PersonaEditorPage());
    await _expectAboveKeyboard(tester, find.byKey(const Key('persona-prompt')));
  });

  testWidgets('participant editor keeps fields above the keyboard', (
    tester,
  ) async {
    await _pump(tester, const ParticipantEditorPage());
    await _expectAboveKeyboard(
      tester,
      find.byKey(const Key('participant-prompt')),
    );
    expect(find.byKey(const Key('participant-save')), findsNothing);
  });
}
