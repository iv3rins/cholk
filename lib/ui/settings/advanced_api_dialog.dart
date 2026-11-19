import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../theme/app_theme.dart';
import 'model_configuration_fields.dart';
import 'settings_frame.dart';

Future<void> showAdvancedApiSettings(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const AdvancedApiDialog(),
);

/// A connection draft stays separate from saved settings until Save succeeds.
class AdvancedApiDialog extends StatefulWidget {
  const AdvancedApiDialog({super.key});

  @override
  State<AdvancedApiDialog> createState() => _AdvancedApiDialogState();
}

class _AdvancedApiDialogState extends State<AdvancedApiDialog> {
  final _fieldsKey = GlobalKey<ModelConfigurationFieldsState>();
  bool _verifying = false;
  bool _saving = false;
  String? _saveError;

  Future<void> _save() async {
    final fields = _fieldsKey.currentState!;
    if (_saving || _verifying || !fields.validate()) return;
    final controller = AppScope.of(context).controller;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await controller.saveModelConfiguration(fields.draft);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = AppScope.of(context).strings.settingsSaveFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    return PopScope(
      canPop: !_saving,
      child: SettingsFrame(
        title: scope.controller.settings.isAdvancedMode
            ? strings.advancedApiSettings
            : strings.configureApi,
        onClose: _saving ? null : () => Navigator.of(context).pop(),
        actions: [
          TextButton(
            key: const Key('advanced-cancel'),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('advanced-save'),
            onPressed: _saving || _verifying ? null : _save,
            child: Text(_saving ? strings.saving : strings.save),
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ModelConfigurationFields(
              key: _fieldsKey,
              initialConfiguration:
                  scope.controller.settings.modelConfiguration,
              enabled: !_saving,
              onVerifyingChanged: (value) => setState(() => _verifying = value),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  _saveError!,
                  style: TextStyle(color: scope.palette.lineInk, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
