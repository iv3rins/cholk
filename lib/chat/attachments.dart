import 'package:path/path.dart' as p;

import '../models/model_configuration.dart';

const int maxFileSizeMb = 64;
const int maxUserDataSizeMb = 32;
const int maxFileCount = 50;

const Set<String> _deepSeekImageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'svg',
  'tiff',
  'tif',
  'ico',
};

/// A practical subset of the web client's extension whitelist, covering the
/// formats users actually send to a chat model.
const Set<String> acceptedExtensions = {
  // images
  ..._deepSeekImageExtensions,
  // documents
  'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt', 'md', 'csv',
  'tsv', 'json', 'html', 'xml', 'yaml', 'yml', 'log', 'ini', 'conf', 'epub',
  // code
  'c', 'h', 'cpp', 'hpp', 'cc', 'cxx', 'cs', 'java', 'js', 'mjs', 'ts',
  'tsx', 'jsx', 'css', 'scss', 'less', 'php', 'py', 'rb', 'go', 'rs', 'swift',
  'kt',
  'kts',
  'dart',
  'lua',
  'sh',
  'bash',
  'ps1',
  'bat',
  'sql',
  'vue',
  'svelte',
};

/// Formats that can be decoded locally and sent as UTF-8 message content.
/// Office files and EPUB are binary containers and need a document parser.
const Set<String> textFileExtensions = {
  'txt',
  'md',
  'csv',
  'tsv',
  'json',
  'html',
  'xml',
  'yaml',
  'yml',
  'log',
  'ini',
  'conf',
  'c',
  'h',
  'cpp',
  'hpp',
  'cc',
  'cxx',
  'cs',
  'java',
  'js',
  'mjs',
  'ts',
  'tsx',
  'jsx',
  'css',
  'scss',
  'less',
  'php',
  'py',
  'rb',
  'go',
  'rs',
  'swift',
  'kt',
  'kts',
  'dart',
  'lua',
  'sh',
  'bash',
  'ps1',
  'bat',
  'sql',
  'vue',
  'svelte',
};

const Set<String> compatibleImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
};
const Set<String> compatibleAudioExtensions = {'wav', 'mp3'};

/// The picker and controller use the same policy. Capabilities describe the
/// selected model, rather than assuming all compatible endpoints accept media.
Set<String> acceptedExtensionsFor(ModelConfiguration configuration) {
  if (configuration.protocol == ApiProtocol.deepseek) {
    if (configuration.supportsImages && configuration.supportsPdf) {
      return acceptedExtensions;
    }
    return Set.unmodifiable(
      acceptedExtensions.where(
        (extension) =>
            (configuration.supportsImages ||
                !_deepSeekImageExtensions.contains(extension)) &&
            (configuration.supportsPdf || extension != 'pdf'),
      ),
    );
  }
  return Set.unmodifiable({
    ...textFileExtensions,
    if (configuration.supportsImages) ...compatibleImageExtensions,
    if (configuration.supportsPdf) 'pdf',
    if (configuration.supportsAudio) ...compatibleAudioExtensions,
  });
}

String fileExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
}

bool isAcceptedFile(String name, {ModelConfiguration? configuration}) =>
    (configuration == null
            ? acceptedExtensions
            : acceptedExtensionsFor(configuration))
        .contains(fileExtension(name));

/// Null means the filename is supported. Decoding and transport still validate
/// the actual bytes before a request is sent.
String? attachmentSupportError(
  String name,
  ModelConfiguration configuration, {
  bool isZh = true,
}) {
  if (isAcceptedFile(name, configuration: configuration)) return null;
  final extension = fileExtension(name);
  final imageTypes = configuration.protocol == ApiProtocol.deepseek
      ? _deepSeekImageExtensions
      : compatibleImageExtensions;
  if (!configuration.supportsImages && imageTypes.contains(extension)) {
    return isZh
        ? '当前模型未启用图片读取，请在高级 API 设置中确认模型能力。'
        : 'Image input is disabled. Check model capabilities in advanced API settings.';
  }
  if (!configuration.supportsPdf && extension == 'pdf') {
    return isZh
        ? '当前模型未启用 PDF 读取，请在高级 API 设置中确认模型能力。'
        : 'PDF input is disabled. Check model capabilities in advanced API settings.';
  }
  if (configuration.protocol == ApiProtocol.openaiCompatible) {
    if (compatibleAudioExtensions.contains(extension)) {
      return isZh
          ? '当前模型未启用音频读取，请在高级 API 设置中确认模型能力。'
          : 'Audio input is disabled. Check model capabilities in advanced API settings.';
    }
    return isZh
        ? '当前接口不支持文件“$name”。请使用 UTF-8 文本、代码，或模型已启用的图片、PDF、WAV/MP3 音频。'
        : 'This endpoint does not support “$name”. Use UTF-8 text, code, or enabled image, PDF, WAV/MP3 inputs.';
  }
  return isZh ? '不支持的文件格式：$name' : 'Unsupported file format: $name';
}

bool isImageMime(String mime) => mime.toLowerCase().startsWith('image/');

String? uploadPurpose(String name, bool isImage) {
  if (isImage) return null;
  const layout = {'pdf', 'doc', 'docx', 'ppt', 'pptx'};
  return layout.contains(fileExtension(name))
      ? 'rich_layout_recognition'
      : 'user_data';
}

int maxSizeMbFor(
  String name,
  bool isImage, {
  ModelConfiguration? configuration,
}) => configuration?.protocol == ApiProtocol.openaiCompatible
    ? (textFileExtensions.contains(fileExtension(name))
          ? maxUserDataSizeMb
          : maxFileSizeMb)
    : uploadPurpose(name, isImage) == 'user_data'
    ? maxUserDataSizeMb
    : maxFileSizeMb;

String baseName(String path) => p.basename(path);
