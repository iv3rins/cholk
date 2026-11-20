import 'package:dio/dio.dart';

import '../chat/chat_request.dart';
import '../models/model_configuration.dart';
import 'api_client.dart';
import 'api_types.dart';
import 'providers/deepseek_provider.dart';
import 'providers/openai_provider.dart';

/// Chooses a wire adapter from an immutable connection snapshot. Providers
/// return the same events, so reply merging and rendering remain independent
/// of the upstream protocol.
class ChatGateway {
  ChatGateway({required ApiClient legacyClient, required this._readAttachment})
    : _client = legacyClient;

  final ApiClient _client;
  final AttachmentReader _readAttachment;
  // File IDs belong to an account as well as an endpoint. Persisted IDs are
  // descriptive only; a fresh gateway starts with an empty trusted cache.
  final Map<(String, String, String), String> _uploadedFiles = {};

  Future<void> verify(ModelConfiguration configuration) {
    configuration = _validated(configuration);
    return _client
        .forOrigin(configuration.normalizedOrigin)
        .verifyApiKey(configuration.apiKey.trim());
  }

  /// Lists models for a draft whose model name may still be empty.
  Future<List<String>> listModels(ModelConfiguration configuration) {
    configuration = _validated(
      configuration.copyWith(
        model: configuration.model.trim().isEmpty ? '-' : configuration.model,
      ),
    );
    return _client
        .forOrigin(configuration.normalizedOrigin)
        .listModels(configuration.apiKey);
  }

  Stream<ApiEvent> stream({
    required ModelConfiguration configuration,
    required ChatRequest request,
    required CancelToken cancelToken,
    void Function()? onAttachmentChanged,
    bool followRedirects = true,
  }) async* {
    configuration = _validated(configuration);
    final client = _client.forOrigin(configuration.normalizedOrigin);
    switch (configuration.protocol) {
      case ApiProtocol.deepseek:
        yield* DeepSeekProvider(client, _readAttachment, _uploadedFiles).stream(
          configuration: configuration,
          request: request,
          cancelToken: cancelToken,
          onAttachmentChanged: onAttachmentChanged,
        );
      case ApiProtocol.openaiCompatible:
        yield* OpenAiProvider(client, _readAttachment).stream(
          configuration: configuration,
          request: request,
          cancelToken: cancelToken,
          onAttachmentChanged: onAttachmentChanged,
          followRedirects: followRedirects,
        );
    }
  }

  ModelConfiguration _validated(ModelConfiguration configuration) {
    try {
      return configuration.validated();
    } on FormatException catch (error) {
      throw ApiException('configuration', error.message);
    }
  }
}
