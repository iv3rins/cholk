import 'dart:async';

import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/models/model_configuration.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/settings/advanced_api_dialog.dart';
import 'package:deepseek_chat/ui/settings/settings_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SettingsController extends ChatController {
  final List<ModelConfiguration> verified = [];
  final List<ModelConfiguration> saved = [];
  Completer<void>? verification;
  Completer<void>? saving;

  _SettingsController() {
    settings.isAdvancedMode = true;
    settings.apiKey = 'saved-key';
    settings.apiOrigin = 'https://saved.example';
  }

  @override
  Future<void> verifyModelConfiguration(ModelConfiguration value) async {
    verified.add(value);
    await verification?.future;
  }

  @override
  Future<void> saveModelConfiguration(ModelConfiguration value) async {
    saved.add(value);
    await saving?.future;
  }
}

Future<void> _openSettings(
  WidgetTester tester,
  _SettingsController controller, {
  bool isZh = true,
  bool dark = false,
  Size size = const Size(800, 1000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(dark ? darkPalette : lightPalette),
      builder: (context, child) => ListenableBuilder(
        listenable: controller,
        builder: (_, _) => AppScope(
          controller: controller,
          strings: S(isZh),
          palette: dark ? darkPalette : lightPalette,
          child: child!,
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showSettingsDialog(context),
            child: const Text('Open settings'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open settings'));
  await tester.pumpAndSettle();
}

Future<void> _openAdvanced(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('advanced-api-settings')));
  await tester.pumpAndSettle();
}

Future<void> _selectOpenAi(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('api-protocol')));
  await tester.tap(find.byKey(const Key('api-protocol')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OpenAI 兼容').last);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final field = find.byKey(Key(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

void main() {
  testWidgets(
    'normal settings offer account connection and personas without quick setup',
    (tester) async {
      final controller = _SettingsController();
      controller.settings.isAdvancedMode = false;
      await _openSettings(tester, controller);
      expect(find.byKey(const Key('api-key')), findsNothing);
      expect(find.byKey(const Key('quick-setup')), findsNothing);
      expect(find.byKey(const Key('server-address')), findsOneWidget);
      expect(find.byKey(const Key('account-login')), findsOneWidget);
      expect(find.byKey(const Key('account-register')), findsOneWidget);
      // Participant management stays in advanced mode, where the connection is
      // edited; normal mode only offers the account sign-in flow.
      expect(find.text(const S(true).manageParticipants), findsNothing);
      SharedPreferences.setMockInitialValues({});
      await controller.setAdvancedMode(true);
      await tester.pumpAndSettle();
      expect(find.text(const S(true).manageParticipants), findsOneWidget);
      expect(controller.saved, isEmpty);
      expect(controller.verified, isEmpty);
      expect(controller.settings.apiKey, 'saved-key');
    },
  );

  testWidgets(
    'verify uses the current draft and clears results after editing',
    (tester) async {
      final controller = _SettingsController();
      await _openSettings(tester, controller);
      await _openAdvanced(tester);
      await _selectOpenAi(tester);
      await _enter(tester, 'api-origin', 'https://draft.example/v1');
      await _enter(tester, 'api-key', 'draft-key');
      await _enter(tester, 'api-model', 'vision-model');
      await tester.ensureVisible(find.byKey(const Key('api-verify')));
      await tester.tap(find.byKey(const Key('api-verify')));
      await tester.pumpAndSettle();
      final verified = controller.verified.single;
      expect(verified.protocol, ApiProtocol.openaiCompatible);
      expect(verified.apiOrigin, 'https://draft.example/v1');
      expect(verified.apiKey, 'draft-key');
      expect(verified.model, 'vision-model');
      expect(verified.supportsImages, isFalse);
      expect(verified.supportsPdf, isFalse);
      expect(verified.supportsAudio, isFalse);
      expect(find.text('验证成功'), findsOneWidget);
      await _enter(tester, 'api-origin', 'https://changed.example/v1');
      expect(find.text('验证成功'), findsNothing);
      expect(controller.settings.apiOrigin, 'https://saved.example');
      expect(controller.saved, isEmpty);
    },
  );

  testWidgets('a stale verification cannot mark an edited draft verified', (
    tester,
  ) async {
    final controller = _SettingsController()..verification = Completer<void>();
    await _openSettings(tester, controller);
    await _openAdvanced(tester);
    await tester.ensureVisible(find.byKey(const Key('api-verify')));
    await tester.tap(find.byKey(const Key('api-verify')));
    await tester.pump();
    expect(controller.verified, hasLength(1));
    await _enter(tester, 'api-key', 'different-key');
    controller.verification!.complete();
    await tester.pumpAndSettle();
    expect(find.text('验证成功'), findsNothing);
    expect(find.text('验证中…'), findsNothing);
  });

  testWidgets(
    'cancelling advanced settings leaves the saved connection intact',
    (tester) async {
      final controller = _SettingsController();
      await _openSettings(tester, controller);
      await _openAdvanced(tester);
      await _enter(tester, 'api-key', 'discard-this-key');
      await tester.tap(find.byKey(const Key('advanced-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(AdvancedApiDialog), findsNothing);
      expect(find.byType(SettingsDialog), findsOneWidget);
      expect(controller.settings.apiKey, 'saved-key');
      expect(controller.saved, isEmpty);
    },
  );

  testWidgets('save requires a valid URL, key and model before committing', (
    tester,
  ) async {
    final controller = _SettingsController();
    await _openSettings(tester, controller);
    await _openAdvanced(tester);
    await _selectOpenAi(tester);
    await _enter(tester, 'api-origin', 'https://draft.example/v1?token=x');
    await _enter(tester, 'api-key', '');
    await _enter(tester, 'api-model', '');
    await tester.tap(find.byKey(const Key('advanced-save')));
    await tester.pumpAndSettle();
    expect(controller.saved, isEmpty);
    expect(find.text(const S(true).apiUrlInvalid), findsOneWidget);
    expect(find.text(const S(true).apiKeyRequired), findsOneWidget);
    expect(find.text(const S(true).modelNameRequired), findsOneWidget);
    await _enter(tester, 'api-origin', 'https://draft.example/v1');
    await _enter(tester, 'api-key', 'new-key');
    await _enter(tester, 'api-model', 'selected-model');
    await tester.tap(find.byKey(const Key('advanced-save')));
    await tester.pumpAndSettle();
    expect(controller.saved, hasLength(1));
    expect(controller.saved.single.model, 'selected-model');
    expect(controller.saved.single.supportsImages, isFalse);
    expect(controller.saved.single.supportsPdf, isFalse);
    expect(controller.saved.single.supportsAudio, isFalse);
    expect(find.byType(AdvancedApiDialog), findsNothing);
  });

  testWidgets(
    'saving disables repeat submits and keeps the draft after failure',
    (tester) async {
      final controller = _SettingsController()..saving = Completer<void>();
      await _openSettings(tester, controller);
      await _openAdvanced(tester);
      await tester.tap(find.byKey(const Key('advanced-save')));
      await tester.pump();
      expect(controller.saved, hasLength(1));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('advanced-save')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('advanced-cancel')))
            .onPressed,
        isNull,
      );
      controller.saving!.completeError(StateError('disk write failed'));
      await tester.pumpAndSettle();
      expect(find.byType(AdvancedApiDialog), findsOneWidget);
      expect(find.text(const S(true).settingsSaveFailed), findsOneWidget);
      expect(controller.saved, hasLength(1));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('api-key')))
            .controller!
            .text,
        'saved-key',
      );
    },
  );

  for (final advanced in [false, true]) {
    testWidgets('compact English dark settings, advanced=$advanced', (
      tester,
    ) async {
      final controller = _SettingsController();
      controller.settings.isAdvancedMode = advanced;
      await _openSettings(
        tester,
        controller,
        isZh: false,
        dark: true,
        size: const Size(375, 812),
      );
      expect(tester.takeException(), isNull);
      if (advanced) {
        expect(find.byKey(const Key('quick-setup')), findsNothing);
        await _openAdvanced(tester);
        expect(find.byKey(const Key('api-origin')), findsOneWidget);
      } else {
        // Initial setup lives in the server account section; there is no
        // separate quick-setup entry to look for.
        expect(find.byKey(const Key('server-address')), findsOneWidget);
        expect(find.byKey(const Key('account-login')), findsOneWidget);
        expect(find.byKey(const Key('advanced-api-settings')), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
