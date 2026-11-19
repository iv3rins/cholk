import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/model_configuration.dart';
import '../../theme/app_theme.dart';
import 'chat_background_settings.dart';
import '../common.dart';
import '../persona/persona_page.dart';
import 'advanced_api_dialog.dart';
import 'prompt_editor.dart';
import 'server_account_section.dart';
import 'settings_frame.dart';

Future<void> showSettingsDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const SettingsDialog());

String accountConnectionHint(bool isZh) =>
    isZh ? '登录或配置 API' : 'Sign in or configure an API';

/// Everyday preferences and a connection summary; API forms have their own draft.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _location;
  bool _initialized = false;
  bool _savingLocation = false;
  bool _deleting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _location = TextEditingController(
      text: AppScope.of(context).controller.settings.locationName,
    );
  }

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  Future<void> _savePreference(Future<void> Function() save) async {
    setState(() => _error = null);
    try {
      await save();
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppScope.of(context).strings.settingsSaveFailed);
    }
  }

  Future<void> _saveLocation() async {
    if (_savingLocation) return;
    final scope = AppScope.of(context);
    setState(() => _savingLocation = true);
    await _savePreference(
      () => scope.controller.setLocationName(_location.text.trim()),
    );
    if (!mounted) return;
    setState(() => _savingLocation = false);
    if (_error == null) showToast(context, scope.strings.saved);
  }

  Future<void> _deleteAllChats() async {
    final scope = AppScope.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: scope.strings.deleteAllChats,
      message: scope.strings.deleteAllChatsConfirm,
      confirmLabel: scope.strings.deleteAll,
      cancelLabel: scope.strings.cancel,
    );
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    try {
      await scope.controller.deleteAllChats();
      if (!mounted) return;
      showToast(context, scope.strings.deletedAllChats);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = scope.strings.settingsSaveFailed);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _openPersonas() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const PersonaPage()));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final settings = scope.controller.settings;
    final config = settings.modelConfiguration;
    final palette = scope.palette;
    final helperStyle = TextStyle(
      fontSize: 12,
      height: 1.6,
      color: palette.lineInk2,
    );
    final apiButton = TextButton.icon(
      key: Key(
        settings.isAdvancedMode
            ? 'advanced-api-settings'
            : 'manual-api-settings',
      ),
      onPressed: () async {
        await showAdvancedApiSettings(context);
        if (mounted) setState(() {});
      },
      icon: const Icon(Icons.tune_outlined, size: 18),
      label: Text(
        settings.isAdvancedMode
            ? strings.advancedApiSettings
            : strings.configureApi,
      ),
    );
    return SettingsFrame(
      title: strings.settings,
      onClose: () => Navigator.of(context).pop(),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.close),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (settings.isAdvancedMode) ...[
            SettingsSectionTitle(strings.apiConnection),
            Text(
              config.apiKey.trim().isEmpty
                  ? strings.apiNotConfigured
                  : '${config.protocol == ApiProtocol.deepseek ? 'DeepSeek' : strings.openAiCompatible} · ${config.model}',
              style: TextStyle(fontSize: 14, color: palette.lineInk),
            ),
            const SizedBox(height: 16),
            SettingsSectionTitle(strings.advanced),
            apiButton,
            TextButton.icon(
              key: const Key('system-prompt-settings'),
              onPressed: () => showPromptEditor(context),
              icon: const Icon(Icons.subject_outlined, size: 18),
              label: Text(strings.promptEditor),
            ),
            TextButton.icon(
              key: const Key('manage-personas'),
              onPressed: _openPersonas,
              icon: const Icon(Icons.manage_accounts_outlined, size: 18),
              label: Text(strings.manageParticipants),
            ),
            const SizedBox(height: 26),
          ],
          const ServerAccountSection(),
          if (!settings.isAdvancedMode)
            Align(alignment: Alignment.centerLeft, child: apiButton),
          const SizedBox(height: 26),
          SettingsSectionTitle(strings.language),
          SegmentedButton<String>(
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 44),
            ),
            segments: const [
              ButtonSegment(value: 'zh-CN', label: Text('简体中文')),
              ButtonSegment(value: 'en-US', label: Text('English')),
            ],
            selected: {settings.locale},
            onSelectionChanged: (values) =>
                _savePreference(() => scope.controller.setLocale(values.first)),
          ),
          const SizedBox(height: 22),
          SettingsSectionTitle(strings.theme),
          SegmentedButton<String>(
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 44),
            ),
            segments: [
              ButtonSegment(value: 'light', label: Text(strings.themeLight)),
              ButtonSegment(value: 'dark', label: Text(strings.themeDark)),
              ButtonSegment(value: 'system', label: Text(strings.themeSystem)),
            ],
            selected: {settings.themePreference},
            onSelectionChanged: (values) => _savePreference(
              () => scope.controller.setThemePreference(values.first),
            ),
          ),
          const SizedBox(height: 22),
          SettingsSectionTitle(strings.chatBackground),
          const ChatBackgroundChoices(),
          const SizedBox(height: 8),
          Text(strings.preferencesSavedImmediately, style: helperStyle),
          const SizedBox(height: 26),
          TextField(
            key: const Key('settings-location'),
            controller: _location,
            enabled: !_savingLocation,
            onSubmitted: (_) => _saveLocation(),
            decoration: InputDecoration(
              labelText: strings.location,
              hintText: strings.locationPlaceholder,
              helperText: strings.locationDescription,
              helperMaxLines: 3,
              suffixIcon: IconButton(
                onPressed: _savingLocation ? null : _saveLocation,
                tooltip: strings.saveLocation,
                icon: const Icon(Icons.check_rounded),
              ),
            ),
          ),
          const SizedBox(height: 26),
          SettingsSectionTitle(strings.data),
          Text(strings.deleteAllChatsDescription, style: helperStyle),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _deleting ? null : _deleteAllChats,
              style: TextButton.styleFrom(foregroundColor: palette.lineInk),
              icon: Icon(
                Icons.delete_outline,
                color: palette.lineSignal,
                size: 18,
              ),
              label: Text(strings.deleteAllChats),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: palette.lineInk, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
