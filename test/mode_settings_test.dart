import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/models/chat_participant.dart';
import 'package:deepseek_chat/models/model_configuration.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/storage/settings_store.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/chat/chat_page.dart';
import 'package:deepseek_chat/ui/persona/persona_page.dart';
import 'package:deepseek_chat/ui/settings/settings_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _open(
  WidgetTester tester,
  ChatController controller,
  Widget page,
) => tester.pumpWidget(
  MaterialApp(
    builder: (context, child) => ListenableBuilder(
      listenable: controller,
      builder: (_, _) => AppScope(
        controller: controller,
        strings: const S(true),
        palette: lightPalette,
        child: child!,
      ),
    ),
    home: page,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy settings start in normal mode and survive persisted mode changes',
    () async {
      SharedPreferences.setMockInitialValues({
        'deepseek_chat:api-key': 'legacy-key',
        'deepseek_chat:api-origin': 'https://proxy.example',
        'deepseek_chat:system-prompt': 'Global prompt',
        'deepseek_chat:persona': 'companion',
      });
      const profile = ChatParticipant(
        id: 'atlas',
        name: 'Atlas',
        configuration: ModelConfiguration(apiKey: 'atlas-key'),
        systemPrompt: 'Atlas prompt',
      );
      final store = SettingsStore();
      await store.saveParticipants([profile]);
      final controller = ChatController(settingsStore: store)
        ..settings = await store.load();
      addTearDown(controller.dispose);
      expect(controller.settings.isAdvancedMode, isFalse);
      for (final advanced in [true, false]) {
        await controller.setAdvancedMode(advanced);
        expect(controller.settings.isAdvancedMode, advanced);
        final restored = await SettingsStore().load();
        expect(restored.isAdvancedMode, advanced);
        expect(restored.apiKey, 'legacy-key');
        expect(restored.apiOrigin, 'https://proxy.example');
        expect(restored.systemPromptOverride, 'Global prompt');
        expect(restored.personaId, 'companion');
        expect(
          (await store.loadParticipants()).single.toJson(),
          profile.toJson(),
        );
      }
    },
  );

  testWidgets(
    'standard settings offer account login and direct API configuration',
    (tester) async {
      final controller = ChatController();
      addTearDown(controller.dispose);
      await _open(tester, controller, const SettingsDialog());
      expect(find.text(const S(true).language), findsOneWidget);
      expect(find.byKey(const Key('advanced-api-settings')), findsNothing);
      expect(find.byKey(const Key('system-prompt-settings')), findsNothing);
      expect(find.text(const S(true).manageParticipants), findsNothing);
      expect(find.byKey(const Key('quick-setup')), findsNothing);
      final address = find.byKey(const Key('server-address'));
      if (defaultAccountOrigin.isNotEmpty) {
        expect(address, findsNothing);
        await tester.tap(find.text(const S(true).advanced));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(address).controller!.text,
          defaultAccountOrigin,
        );
      }
      expect(address, findsOneWidget);
      expect(find.byKey(const Key('account-login')), findsOneWidget);
      expect(find.byKey(const Key('account-register')), findsOneWidget);
      expect(find.byKey(const Key('api-key')), findsNothing);
      final configureApi = find.byKey(const Key('manual-api-settings'));
      await tester.ensureVisible(configureApi);
      await tester.tap(configureApi);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('api-key')), findsOneWidget);
    },
  );

  testWidgets(
    'default persona page keeps presets but hides custom model editing',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ChatController();
      addTearDown(controller.dispose);
      await _open(tester, controller, const PersonaPage());
      expect(find.byKey(const Key('add-participant')), findsNothing);
      await tester.tap(find.text('严谨工程师'));
      await tester.pumpAndSettle();
      expect((await SettingsStore().load()).personaId, 'engineer');
    },
  );

  testWidgets(
    'normal chat opens connection settings and keeps its draft and participants',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ChatController();
      addTearDown(controller.dispose);
      await controller.saveParticipant(
        const ChatParticipant(
          id: 'atlas',
          name: 'Atlas',
          configuration: ModelConfiguration(apiKey: 'atlas-key'),
          systemPrompt: 'Atlas prompt',
        ),
      );
      await _open(tester, controller, const ChatPage());
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsNothing);
      expect(find.text(accountConnectionHint(true)), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-draft')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsOneWidget);
      await tester.tap(find.text(const S(true).close).last);
      await tester.pumpAndSettle();
      expect(controller.draftText, 'hello');
      await tester.tap(find.byKey(const Key('chat-recipients')));
      await tester.pumpAndSettle();
      expect(find.text(const S(true).manageParticipants), findsNothing);
      await tester.tap(find.byKey(const ValueKey('recipient-atlas')));
      await tester.tap(find.text(const S(true).done));
      await tester.pumpAndSettle();
      expect(controller.selectedParticipantIds, ['atlas']);
      expect(controller.hasChatConnection, isTrue);
    },
  );
}
