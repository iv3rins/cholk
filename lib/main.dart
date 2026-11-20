import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'demo/demo_data.dart';
import 'models/model_configuration.dart';
import 'state/chat_controller.dart';
import 'ui/settings/disclaimer_dialog.dart';

const bool _demoUi = bool.fromEnvironment('DEMO_UI');
const String _testModel = String.fromEnvironment('TEST_OPENAI_MODEL');
const String _proxyOriginOverride = String.fromEnvironment('PROXY_ORIGIN');
const String _demoProxyToken = String.fromEnvironment(
  'PROXY_TOKEN',
  defaultValue: 'client-token',
);

String _demoProxyOrigin() {
  if (_proxyOriginOverride.isNotEmpty) return _proxyOriginOverride;
  final base = Uri.base;
  if ((base.scheme == 'http' || base.scheme == 'https') &&
      base.host.isNotEmpty) {
    return '${base.scheme}://${base.host}:8787';
  }
  return 'http://127.0.0.1:8787';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    // Draw behind the system bars so Android reports the keyboard as a view
    // inset on every API level. Without this, some devices resize nothing and
    // report no inset, and the keyboard covers the focused field.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  final controller = ChatController();
  await controller.init();

  if (kIsWeb && _testModel.isNotEmpty) {
    controller.settings.modelConfiguration = ModelConfiguration(
      protocol: ApiProtocol.openaiCompatible,
      apiOrigin: '${Uri.base.origin}/v1',
      apiKey: 'local-preview',
      model: _testModel,
    );
  } else if (_demoUi && kIsWeb) {
    final origin = _demoProxyOrigin();
    controller.settings
      ..apiKey = _demoProxyToken
      ..apiOrigin = origin
      ..themePreference = Uri.base.queryParameters['theme'] == 'dark'
          ? 'dark'
          : 'light';
    controller.api.origin = origin;
    if (controller.summaries.isEmpty) {
      for (final session in createDemoSessions()) {
        controller.restoreSession(session);
      }
    }
  }

  final preview = kIsWeb && (_demoUi || _testModel.isNotEmpty);
  final showDisclaimer = !preview && !await disclaimerAccepted();
  runApp(
    DeepSeekChatApp(controller: controller, showDisclaimer: showDisclaimer),
  );
}
