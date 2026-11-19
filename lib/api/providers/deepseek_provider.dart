import 'package:dio/dio.dart';

import '../../chat/attachments.dart';
import '../../chat/chat_request.dart';
import '../../chat/context_builder.dart';
import '../../models/chat_models.dart';
import '../../models/model_configuration.dart';
import '../api_client.dart';
import '../api_types.dart';

/// DeepSeek application protocol: file IDs, signed tools, reminders and titles
/// remain here rather than becoming requirements of every chat provider.
class DeepSeekProvider {
  DeepSeekProvider(this._client, this._readAttachment, this._uploadedFiles);

  final ApiClient _client;
  final AttachmentReader _readAttachment;
  final Map<(String, String, String), String> _uploadedFiles;

  Stream<ApiEvent> stream({
    required ModelConfiguration configuration,
    required ChatRequest request,
    required CancelToken cancelToken,
    void Function()? onAttachmentChanged,
  }) async* {
    final rounds = contextRounds(request.history);
    final files = <FileAttachment>[
      for (final (user, _) in rounds) ...user.files,
      ...request.question.files,
    ];
    final seen = <String>{};
    for (final file in files) {
      if (!seen.add(file.id)) continue;
      if ((file.isImage && !configuration.supportsImages) ||
          (fileExtension(file.name) == 'pdf' && !configuration.supportsPdf) ||
          file.mimeType.startsWith('audio/')) {
        throw ApiException('unsupported', '当前模型不支持附件：${file.name}');
      }
      final cacheKey = (
        configuration.normalizedOrigin,
        configuration.apiKey.trim(),
        file.id,
      );
      final cachedId = _uploadedFiles[cacheKey];
      if (cachedId != null) {
        file
          ..serverId = cachedId
          ..serverOrigin = configuration.normalizedOrigin;
        continue;
      }
      file
        ..status = AttachmentStatus.uploading
        ..error = null;
      onAttachmentChanged?.call();
      try {
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        final bytes = await _readAttachment(file);
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        final uploaded = await _client.uploadFile(
          apiKey: configuration.apiKey.trim(),
          bytes: bytes,
          name: file.name,
          mimeType: file.mimeType,
          purpose: uploadPurpose(file.name, file.isImage),
          cancelToken: cancelToken,
        );
        file
          ..serverId = uploaded.id
          ..serverOrigin = configuration.normalizedOrigin
          ..status = AttachmentStatus.ready;
        _uploadedFiles[cacheKey] = uploaded.id;
      } catch (error) {
        if (error is DioException && CancelToken.isCancel(error)) {
          file.status = AttachmentStatus.ready;
          rethrow;
        }
        file
          ..status = AttachmentStatus.failed
          ..error = error.toString();
        if (error is ApiException) rethrow;
        throw ApiException('attachment', '读取附件失败 ${file.name}: $error');
      } finally {
        onAttachmentChanged?.call();
      }
    }

    // FileAttachment metadata is shared with the UI. Materialize account-local
    // IDs so another request cannot swap them during a multi-file upload.
    UserMessage scopedUser(UserMessage user) => UserMessage(
      id: user.id,
      createdAt: user.createdAt,
      content: user.content,
      files: [
        for (final file in user.files)
          FileAttachment(
            id: file.id,
            name: file.name,
            size: file.size,
            isImage: file.isImage,
            mimeType: file.mimeType,
            serverId:
                _uploadedFiles[(
                  configuration.normalizedOrigin,
                  configuration.apiKey.trim(),
                  file.id,
                )],
          ),
      ],
    );

    yield* _client.streamMessage(
      apiKey: configuration.apiKey.trim(),
      cancelToken: cancelToken,
      body: {
        'model': configuration.model.trim(),
        'system': request.systemPrompt,
        'messages': toRequestMessages(
          history: [
            for (final (user, reply) in rounds) ...[scopedUser(user), reply],
          ],
          question: scopedUser(request.question),
          prefix: request.prefix,
          thinking: request.thinking,
          latestReminder: request.latestReminder,
        ),
        'thinking': {'type': request.thinking ? 'enabled' : 'disabled'},
        'safety_check': {'level': 'high'},
        'tools': <Map<String, String>>[
          {'type': 'deepseek_read_url', 'name': 'deepseek_read_url'},
          if (request.search)
            {'type': 'deepseek_web_search', 'name': 'deepseek_web_search'},
        ],
        if (request.titleRequest) 'title': {'enabled': true},
      },
    );
  }
}
