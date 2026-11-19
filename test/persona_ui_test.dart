import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/persona/persona_editor_page.dart';
import 'package:deepseek_chat/ui/persona/persona_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _fill(WidgetTester tester, String key, String text) async {
  final field = find.byKey(Key(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

void main() {
  testWidgets('normal mode saves a custom persona without clearing workflow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ChatController();
    addTearDown(controller.dispose);
    final existing = await controller.importPersona('''
{
  "version": 1,
  "name": "Editor",
  "system_prompt": "Be concise.",
  "workflow": ["Read", "Reply"]
}
''');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(lightPalette),
        builder: (context, child) => AppScope(
          controller: controller,
          strings: const S(false),
          palette: lightPalette,
          child: child!,
        ),
        home: PersonaEditorPage(persona: existing),
      ),
    );

    expect(find.byKey(const Key('persona-workflow')), findsNothing);
    await _fill(tester, 'persona-prompt', 'Be direct.');
    await tester.tap(find.byKey(const Key('persona-save')));
    await tester.pumpAndSettle();
    expect(controller.personaForId(existing.id).workflow, ['Read', 'Reply']);
    expect(controller.personaForId(existing.id).prompt(false), 'Be direct.');
  });

  testWidgets('advanced mode creates a persona with workflow and clears it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ChatController()..settings.isAdvancedMode = true;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(lightPalette),
        builder: (context, child) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) => AppScope(
            controller: controller,
            strings: const S(true),
            palette: lightPalette,
            child: child!,
          ),
        ),
        home: const PersonaPage(),
      ),
    );

    await tester.tap(find.byKey(const Key('add-persona')));
    await tester.pumpAndSettle();
    await _fill(tester, 'persona-name', 'Review');
    await _fill(tester, 'persona-prompt', 'Review the answer.');
    await _fill(tester, 'persona-workflow', 'Read question\n\nCheck facts');
    await tester.tap(find.byKey(const Key('persona-save')));
    await tester.pumpAndSettle();
    final saved = controller.personaOptions.singleWhere((p) => p.isCustom);
    expect(saved.workflow, ['Read question', 'Check facts']);

    final options = find.byKey(ValueKey('persona-options-${saved.id}'));
    expect(options, findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(options);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await _fill(tester, 'persona-workflow', '');
    await tester.tap(find.byKey(const Key('persona-save')));
    await tester.pumpAndSettle();
    expect(controller.personaForId(saved.id).workflow, isEmpty);
    expect(find.textContaining('不会在本地自动执行'), findsOneWidget);
  });
}
