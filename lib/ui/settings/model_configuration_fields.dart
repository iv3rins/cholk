import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/model_configuration.dart';
import '../../theme/app_theme.dart';
import 'settings_frame.dart';

/// Shared API draft form for the main connection and individual participants.
class ModelConfigurationFields extends StatefulWidget {
  const ModelConfigurationFields({
    super.key,
    required this.initialConfiguration,
    this.enabled = true,
    this.onVerifyingChanged,
  });

  final ModelConfiguration initialConfiguration;
  final bool enabled;
  final ValueChanged<bool>? onVerifyingChanged;

  @override
  ModelConfigurationFieldsState createState() =>
      ModelConfigurationFieldsState();
}

class ModelConfigurationFieldsState extends State<ModelConfigurationFields> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _origin;
  late final TextEditingController _key;
  late final TextEditingController _model;
  late ApiProtocol _protocol;
  bool _images = false;
  bool _pdf = false;
  bool _audio = false;
  bool _obscure = true;
  bool _verifying = false;
  int _revision = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfiguration;
    _protocol = config.protocol;
    _origin = TextEditingController(text: config.apiOrigin);
    _key = TextEditingController(text: config.apiKey);
    _model = TextEditingController(text: config.model);
    // DeepSeek attachment support does not imply OpenAI model capabilities.
    _images =
        _protocol == ApiProtocol.openaiCompatible && config.supportsImages;
    _pdf = _protocol == ApiProtocol.openaiCompatible && config.supportsPdf;
    _audio = _protocol == ApiProtocol.openaiCompatible && config.supportsAudio;
  }

  @override
  void dispose() {
    _origin.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  void _draftChanged() {
    setState(() {
      _revision++;
      _status = null;
    });
  }

  bool validate() => _formKey.currentState!.validate();

  ModelConfiguration get draft => ModelConfiguration(
    protocol: _protocol,
    apiOrigin: _origin.text.trim(),
    apiKey: _key.text.trim(),
    model: _model.text.trim(),
    supportsImages: _protocol == ApiProtocol.deepseek || _images,
    supportsPdf: _protocol == ApiProtocol.deepseek || _pdf,
    supportsAudio: _protocol == ApiProtocol.openaiCompatible && _audio,
  );

  Future<void> _verify() async {
    if (_verifying || !validate()) return;
    final controller = AppScope.of(context).controller;
    final revision = _revision;
    final configuration = draft;
    setState(() {
      _verifying = true;
      _status = null;
    });
    widget.onVerifyingChanged?.call(true);
    try {
      await controller.verifyModelConfiguration(configuration);
      if (!mounted) return;
      setState(() {
        _verifying = false;
        if (revision == _revision) {
          _status = AppScope.of(context).strings.verified;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        if (revision == _revision) {
          _status = AppScope.of(context).strings.verifyFailed;
        }
      });
    } finally {
      if (mounted) widget.onVerifyingChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = scope.palette;
    final helperStyle = TextStyle(
      fontSize: 12,
      height: 1.6,
      color: palette.lineInk2,
    );
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<ApiProtocol>(
            key: const Key('api-protocol'),
            initialValue: _protocol,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.apiProtocol),
            items: [
              const DropdownMenuItem(
                value: ApiProtocol.deepseek,
                child: Text('DeepSeek'),
              ),
              DropdownMenuItem(
                value: ApiProtocol.openaiCompatible,
                child: Text(strings.openAiCompatible),
              ),
            ],
            onChanged: !widget.enabled
                ? null
                : (value) {
                    if (value == null) return;
                    _protocol = value;
                    _draftChanged();
                  },
          ),
          const SizedBox(height: 18),
          TextFormField(
            key: const Key('api-origin'),
            controller: _origin,
            enabled: widget.enabled,
            onChanged: (_) => _draftChanged(),
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: strings.apiOrigin,
              helperText: strings.apiBaseUrlHelp,
              helperMaxLines: 3,
              errorMaxLines: 3,
              errorStyle: TextStyle(color: palette.lineInk),
            ),
            validator: (value) {
              final uri = Uri.tryParse(value?.trim() ?? '');
              if (uri == null ||
                  (uri.scheme != 'http' && uri.scheme != 'https') ||
                  uri.host.isEmpty ||
                  uri.hasQuery ||
                  uri.hasFragment ||
                  uri.userInfo.isNotEmpty) {
                return strings.apiUrlInvalid;
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          TextFormField(
            key: const Key('api-key'),
            controller: _key,
            enabled: widget.enabled,
            onChanged: (_) => _draftChanged(),
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API Key',
              helperText: strings.apiKeyLocal,
              errorStyle: TextStyle(color: palette.lineInk),
              suffixIcon: IconButton(
                tooltip: _obscure ? strings.showKey : strings.hideKey,
                onPressed: !widget.enabled
                    ? null
                    : () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? strings.apiKeyRequired
                : null,
          ),
          const SizedBox(height: 18),
          TextFormField(
            key: const Key('api-model'),
            controller: _model,
            enabled: widget.enabled,
            onChanged: (_) => _draftChanged(),
            autocorrect: false,
            decoration: InputDecoration(
              labelText: strings.modelName,
              errorStyle: TextStyle(color: palette.lineInk),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? strings.modelNameRequired
                : null,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const Key('api-verify'),
              onPressed: !widget.enabled || _verifying ? null : _verify,
              child: Text(_verifying ? strings.verifying : strings.verify),
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _status!,
                style: TextStyle(color: palette.lineInk, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 26),
          SettingsSectionTitle(strings.modelCapabilities),
          if (_protocol == ApiProtocol.openaiCompatible) ...[
            Text(strings.capabilitiesDescription, style: helperStyle),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.acceptsImages),
              value: _images,
              onChanged: !widget.enabled
                  ? null
                  : (value) {
                      _images = value;
                      _draftChanged();
                    },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.acceptsPdf),
              value: _pdf,
              onChanged: !widget.enabled
                  ? null
                  : (value) {
                      _pdf = value;
                      _draftChanged();
                    },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.acceptsAudio),
              value: _audio,
              onChanged: !widget.enabled
                  ? null
                  : (value) {
                      _audio = value;
                      _draftChanged();
                    },
            ),
            const SizedBox(height: 8),
            Text(strings.localFileDescription, style: helperStyle),
          ] else
            Text(strings.deepseekInputDescription, style: helperStyle),
        ],
      ),
    );
  }
}
