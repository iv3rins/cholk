const String defaultApiOrigin = 'https://api.deepseek.com';
const String defaultModel = 'deepseek-flash';
const int defaultHistoryBudgetTokens = 24000;

enum ApiProtocol { deepseek, openaiCompatible }

/// A snapshot of one model connection. Capabilities are explicit because an
/// OpenAI-compatible endpoint does not imply that its model accepts media.
class ModelConfiguration {
  const ModelConfiguration({
    this.protocol = ApiProtocol.deepseek,
    this.apiOrigin = defaultApiOrigin,
    this.apiKey = '',
    this.model = defaultModel,
    bool? supportsImages,
    bool? supportsPdf,
    this.supportsAudio = false,
  }) : supportsImages = supportsImages ?? (protocol == ApiProtocol.deepseek),
       supportsPdf = supportsPdf ?? (protocol == ApiProtocol.deepseek);

  final ApiProtocol protocol;
  final String apiOrigin;
  final String apiKey;
  final String model;
  final bool supportsImages;
  final bool supportsPdf;
  final bool supportsAudio;

  String get normalizedOrigin =>
      apiOrigin.trim().replaceAll(RegExp(r'/+$'), '');

  ModelConfiguration validated() {
    final uri = Uri.tryParse(normalizedOrigin);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('API URL must be an HTTP(S) base URL');
    }
    if (apiKey.trim().isEmpty) {
      throw const FormatException('API Key is required');
    }
    if (model.trim().isEmpty) {
      throw const FormatException('Model name is required');
    }
    return copyWith(
      apiOrigin: normalizedOrigin,
      apiKey: apiKey.trim(),
      model: model.trim(),
    );
  }

  ModelConfiguration copyWith({
    ApiProtocol? protocol,
    String? apiOrigin,
    String? apiKey,
    String? model,
    bool? supportsImages,
    bool? supportsPdf,
    bool? supportsAudio,
  }) => ModelConfiguration(
    protocol: protocol ?? this.protocol,
    apiOrigin: apiOrigin ?? this.apiOrigin,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    supportsImages: supportsImages ?? this.supportsImages,
    supportsPdf: supportsPdf ?? this.supportsPdf,
    supportsAudio: supportsAudio ?? this.supportsAudio,
  );

  Map<String, dynamic> toJson() => {
    'protocol': protocol.name,
    'api_origin': normalizedOrigin,
    'api_key': apiKey,
    'model': model,
    'supports_images': supportsImages,
    'supports_pdf': supportsPdf,
    'supports_audio': supportsAudio,
  };

  static ModelConfiguration fromJson(Object? value) {
    if (value is! Map) return const ModelConfiguration();
    final protocol = value['protocol'] == ApiProtocol.openaiCompatible.name
        ? ApiProtocol.openaiCompatible
        : ApiProtocol.deepseek;
    String read(String key, String fallback) =>
        value[key] is String ? value[key] as String : fallback;
    return ModelConfiguration(
      protocol: protocol,
      apiOrigin: read('api_origin', defaultApiOrigin),
      apiKey: read('api_key', ''),
      model: read('model', defaultModel),
      supportsImages: value['supports_images'] is bool
          ? value['supports_images'] as bool
          : protocol == ApiProtocol.deepseek,
      supportsPdf: value['supports_pdf'] is bool
          ? value['supports_pdf'] as bool
          : protocol == ApiProtocol.deepseek,
      supportsAudio: value['supports_audio'] == true,
    );
  }
}
