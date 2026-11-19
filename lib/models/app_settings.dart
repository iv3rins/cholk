import 'chat_member.dart';
import 'chat_preferences.dart';
import 'model_configuration.dart';

const defaultAccountOrigin = String.fromEnvironment('ACCOUNT_ORIGIN');

/// User preferences are independent of how they are stored or sent over HTTP.
class AppSettings {
  AppSettings({
    this.isAdvancedMode = false,
    this.apiKey = '',
    this.serverAddress = defaultAccountOrigin,
    this.locale = 'zh-CN',
    this.themePreference = 'light',
    this.locationName = '',
    this.thinking = false,
    this.search = false,
    this.siderCollapsed = false,
    this.ttsVoice = 'stella',
    this.personaId = 'default',
    this.chatBackground = ChatBackground.plain,
    this.chatBackgroundImageBase64,
    this.memorySync = false,
    this.systemPromptOverride = '',
    this.apiOrigin = defaultApiOrigin,
    this.protocol = ApiProtocol.deepseek,
    this.model = defaultModel,
    this.supportsImages = true,
    this.supportsPdf = true,
    this.supportsAudio = false,
    this.preferredChatModel,
  });

  bool isAdvancedMode;
  String apiKey;
  String serverAddress;
  String locale;
  String themePreference;
  String locationName;
  bool thinking;
  bool search;
  bool siderCollapsed;
  String ttsVoice;
  String personaId;
  ChatBackground chatBackground;

  /// The imported background picture as base64 bytes, or null for no picture.
  /// It lives beside [chatBackground] rather than replacing it, so the tiled
  /// presets stay available when no picture is set.
  String? chatBackgroundImageBase64;

  /// Lets chat conversations share what they remember across sessions.
  bool memorySync;
  String systemPromptOverride;
  String apiOrigin;
  ApiProtocol protocol;
  String model;
  bool supportsImages;
  bool supportsPdf;
  bool supportsAudio;

  /// The assistant model last chosen for a new conversation. It is only a
  /// preference: [ChatController] falls back when the reference no longer
  /// exists, and it never contains a credential.
  ChatModelRef? preferredChatModel;

  bool get isZh => locale == 'zh-CN';

  /// Each request owns a snapshot, so changing settings cannot redirect a
  /// running request or mix credentials between attachment uploads.
  ModelConfiguration get modelConfiguration => ModelConfiguration(
    protocol: protocol,
    apiOrigin: apiOrigin,
    apiKey: apiKey,
    model: model,
    supportsImages: supportsImages,
    supportsPdf: supportsPdf,
    supportsAudio: supportsAudio,
  );

  set modelConfiguration(ModelConfiguration value) {
    protocol = value.protocol;
    apiOrigin = value.apiOrigin;
    apiKey = value.apiKey;
    model = value.model;
    supportsImages = value.supportsImages;
    supportsPdf = value.supportsPdf;
    supportsAudio = value.supportsAudio;
  }
}
