import '../models/chat_models.dart';

class S {
  const S(this.isZh);

  final bool isZh;

  String get appName => 'Cholk';
  String get welcome => isZh ? '今天有什么可以帮到你？' : 'How can I help you?';
  String get contentCaveat =>
      isZh ? '内容由 AI 生成，请仔细甄别' : 'AI-generated content. Please verify.';

  String get newChat => isZh ? '开启新对话' : 'New chat';
  String get settings => isZh ? '设置' : 'Settings';
  String get collapseSider => isZh ? '收起侧边栏' : 'Collapse sidebar';
  String get expandSider => isZh ? '展开侧边栏' : 'Expand sidebar';
  String get sessionTitlePlaceholder => isZh ? '新对话' : 'New chat';
  String get noSessions => isZh ? '还没有对话' : 'No chats yet';
  String get today => isZh ? '今天' : 'Today';
  String get yesterday => isZh ? '昨天' : 'Yesterday';
  String get last7Days => isZh ? '最近 7 天' : 'Previous 7 days';
  String get earlier => isZh ? '更早' : 'Earlier';
  String get rename => isZh ? '重命名' : 'Rename';
  String get delete => isZh ? '删除' : 'Delete';
  String get deleteSessionTitle => isZh ? '删除对话' : 'Delete chat';
  String get deleteSessionMessage => isZh
      ? '删除后无法恢复，确定要删除这个对话吗？'
      : 'This chat will be permanently deleted. Continue?';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get confirm => isZh ? '确定' : 'Confirm';
  String get save => isZh ? '保存' : 'Save';
  String get close => isZh ? '关闭' : 'Close';

  String get inputPlaceholder => isZh ? '给 Cholk 发送消息' : 'Message Cholk';
  String get workPlaceholder =>
      isZh ? '描述任务或写下要交付的内容' : 'Describe a task or the result you need';
  String get workWelcome => isZh ? '今天要完成什么？' : 'What are we working on?';
  String get modeChat => isZh ? '聊天' : 'Chat';
  String get modeWork => isZh ? '工作' : 'Work';
  String get chatMode => isZh ? '会话模式' : 'Conversation mode';
  String get you => isZh ? '你' : 'You';
  String get generationMonitor => isZh ? '生成监控' : 'Generation monitor';
  String get closeGenerationMonitor =>
      isZh ? '关闭生成监控' : 'Close generation monitor';
  String get monitorSession => isZh ? '查看会话' : 'Monitor conversation';
  String get followActiveSession =>
      isZh ? '跟随当前会话' : 'Follow active conversation';
  String get monitorParticipant => isZh ? '查看角色' : 'Monitor role';
  String get monitorNoReplies => isZh
      ? '这场会话还没有模型回复。发送消息后可在这里查看生成进度。'
      : 'No replies in this conversation yet. Send a message to see generation here.';
  String get monitorLoading => isZh ? '正在读取会话…' : 'Loading conversation…';
  String get monitorUnavailable =>
      isZh ? '无法读取这场会话' : 'Conversation unavailable';
  String get replyQueued => isZh ? '等待生成…' : 'Waiting to generate…';
  String get replyDone => isZh ? '生成完成' : 'Generation complete';
  String get noReplyText => isZh ? '没有正文' : 'No reply text';
  String get chatPersona => isZh ? '会话人格' : 'Conversation persona';
  String get followDefaults => isZh ? '沿用默认设置' : 'Use defaults';
  String get mentionAgent => isZh ? '提及智能体' : 'Mention an agent';
  String get mentionNeedsGroup => isZh
      ? '选择至少两位智能体后可使用 @ 提及'
      : 'Select at least two agents to use @mentions';
  String get replyTo => isZh ? '本轮回复' : 'Replying this turn';
  String get noMatchingAgents => isZh ? '没有匹配的智能体' : 'No matching agents';
  String get chatBackground => isZh ? '聊天背景' : 'Chat background';
  String get backgroundPlain => isZh ? '素纸' : 'Plain';
  String get backgroundRuled => isZh ? '横线' : 'Ruled';
  String get backgroundGrid => isZh ? '方格' : 'Grid';
  String get backgroundDots => isZh ? '点阵' : 'Dots';
  String get moreTools => isZh ? '对话工具' : 'Conversation tools';
  String get promptEditor => isZh ? '系统提示词' : 'System prompt';
  String get promptEditorDescription => isZh
      ? '替换所有模型的基础系统提示词。人格和工作模式指令仍会追加；留空则使用接口默认值。'
      : 'Replaces the base system prompt for all models. Personas and Work mode instructions are still appended. Leave blank to use each provider’s default.';
  String get promptEditorPlaceholder =>
      isZh ? '输入自定义系统提示词' : 'Enter a custom system prompt';
  String get useBuiltInPrompt => isZh ? '使用默认提示词' : 'Use default prompt';
  String get coil => isZh ? '线圈' : 'Coil';
  String get web => isZh ? '蛛网' : 'Web';
  String get lineStudies => isZh ? '平面线条' : 'Line studies';
  String get tugLines => isZh ? '轻拉线条' : 'Tug the lines';
  String get dragLines => isZh ? '拖拽线条' : 'Drag the lines';
  String get enableTilt => isZh ? '开启倾斜感应' : 'Enable tilt';
  String get disableTilt => isZh ? '关闭倾斜感应' : 'Disable tilt';
  String get tiltUnavailable => isZh
      ? '无法读取设备姿态，仍可拖拽线条。'
      : 'Device orientation is unavailable. You can still drag the lines.';
  String get defaultAssistant => isZh ? '默认助手' : 'Default assistant';
  String get replyParticipants => isZh ? '选择回复的模型' : 'Choose who replies';
  String get sharedChatHistory => isZh
      ? '所选模型会各自回复，并共享这场对话的历史。'
      : 'Selected models reply independently and share this conversation’s history.';
  String get manageParticipants =>
      isZh ? '管理模型与人格' : 'Manage models and personas';
  String recipientCount(int count) => isZh ? '$count 个模型' : '$count models';
  String get thinkingSwitch => isZh ? '深度思考' : 'DeepThink';
  String get search => isZh ? '智能搜索' : 'Search';
  String get uploadFile => isZh ? '上传文件' : 'Upload file';
  String get send => isZh ? '发送' : 'Send';
  String get stop => isZh ? '停止生成' : 'Stop generating';

  String get copy => isZh ? '复制' : 'Copy';
  String get copied => isZh ? '已复制' : 'Copied';
  String get edit => isZh ? '编辑' : 'Edit';
  String get regenerate => isZh ? '重新生成' : 'Regenerate';
  String get continueReply => isZh ? '继续生成' : 'Continue';
  String get retry => isZh ? '重试' : 'Retry';

  String get thinking => isZh ? '深度思考中' : 'Deep thinking';
  String get thinkingStopped => isZh ? '已停止思考' : 'Thinking stopped';
  String get searching => isZh ? '正在搜索…' : 'Searching…';
  String get readingLink => isZh ? '正在阅读链接…' : 'Reading link…';
  String get openedPages => isZh ? '正在打开网页…' : 'Opening page…';
  String get searched => isZh ? '搜索' : 'Search';
  String get searchResults => isZh ? '搜索结果' : 'Search results';
  String get sources => isZh ? '来源' : 'Sources';
  String get noSources => isZh ? '没有找到结果' : 'No results';
  String get reference => isZh ? '参考来源' : 'Sources';

  String thoughtFor(int seconds) =>
      isZh ? '已思考 $seconds 秒' : 'Thought for $seconds seconds';
  String get replyStopped => isZh ? '已停止生成' : 'Generation stopped';
  String get replyRefusal =>
      isZh ? '该内容无法生成，请换一个话题试试' : 'This request was declined.';
  String get errorOccurred => isZh ? '回答出错' : 'Something went wrong';
  String get waiting => isZh ? '正在生成…' : 'Generating…';

  String get settingsApiKey => 'API Key';
  String get apiKeyDescription => isZh
      ? '仅保存在本机。直连时填 DeepSeek API Key，使用代理时填代理 Token。'
      : 'Stored locally. Use a DeepSeek API key for direct access, or a proxy token when using a proxy.';
  String get apiKeyPlaceholder =>
      isZh ? 'DeepSeek API Key 或代理 Token' : 'DeepSeek API key or proxy token';
  String get getApiKey => isZh ? '获取 API Key' : 'Get an API key';
  String get showKey => isZh ? '显示' : 'Show';
  String get hideKey => isZh ? '隐藏' : 'Hide';
  String get verify => isZh ? '验证' : 'Verify';
  String get verifying => isZh ? '验证中…' : 'Verifying…';
  String get verified => isZh ? '验证成功' : 'Verified';
  String get verifyFailed => isZh ? '验证失败' : 'Verification failed';
  String get apiKeyRequired => isZh ? '请先填写 API Key' : 'API key required';
  String get apiOrigin => isZh ? 'API 地址' : 'API base URL';
  String get apiOriginDescription => isZh
      ? '默认 https://api.deepseek.com；使用自建代理时填写代理地址。'
      : 'Defaults to https://api.deepseek.com. Enter your proxy URL when using a proxy.';
  String get advanced => isZh ? '高级' : 'Advanced';
  String get apiConnection => isZh ? '模型连接' : 'Model connection';
  String get configureApi => isZh ? '配置 API' : 'Configure API';
  String get apiNotConfigured => isZh ? '尚未配置 API' : 'API not configured';
  String get quickSetup => isZh ? '一键配置（即将推出）' : 'Quick setup (coming soon)';
  String get quickSetupDescription => isZh
      ? '一键配置暂未开放。你可以在首页切换到进阶模式，手动设置 API。'
      : 'Quick setup is not available yet. Switch to Advanced mode on the home screen to configure an API.';
  String get advancedApiSettings =>
      isZh ? '高级 API 设置' : 'Advanced API settings';
  String get apiProtocol => isZh ? '接口协议' : 'API protocol';
  String get openAiCompatible => isZh ? 'OpenAI 兼容' : 'OpenAI compatible';
  String get modelName => isZh ? '模型名称' : 'Model name';
  String get modelNameRequired => isZh ? '请填写模型名称' : 'Enter a model name';
  String get apiUrlInvalid => isZh
      ? '请输入完整的 http(s) 地址，且不含查询参数或 # 片段'
      : 'Enter a full http(s) URL without a query or fragment';
  String get apiBaseUrlHelp => isZh
      ? '按服务商要求填写基础地址，可包含 /v1 等路径。'
      : 'Use your provider’s base URL, including a path such as /v1 if required.';
  String get apiKeyLocal =>
      isZh ? 'API Key 仅保存在本机。' : 'Your API key is stored locally.';
  String get modelCapabilities => isZh ? '模型输入能力' : 'Model inputs';
  String get capabilitiesDescription => isZh
      ? '仅开启服务商与当前模型确实支持的输入。能力开关不会为模型增加能力。'
      : 'Enable only inputs supported by your provider and model. These switches do not add model capabilities.';
  String get acceptsImages => isZh ? '图片' : 'Images';
  String get acceptsPdf => isZh ? 'PDF 文件' : 'PDF files';
  String get acceptsAudio => isZh ? '语音（WAV / MP3）' : 'Audio (WAV / MP3)';
  String get localFileDescription => isZh
      ? '文本文件在本地读取后发送。图片、PDF、WAV / MP3 由兼容模型接收；Office 等格式不提供通用解析。'
      : 'Text files are read locally before sending. Images, PDFs and WAV / MP3 require a compatible model; Office and other formats have no general parser.';
  String get deepseekInputDescription => isZh
      ? 'DeepSeek 使用现有文件接口；图片与语音输入请切换到支持相应能力的 OpenAI 兼容模型。'
      : 'DeepSeek uses its existing file API. For image or audio inputs, choose an OpenAI-compatible model with the required capabilities.';
  String get settingsSaveFailed =>
      isZh ? '保存失败，请重试。' : 'Could not save. Please try again.';
  String get saving => isZh ? '保存中…' : 'Saving…';
  String get saved => isZh ? '已保存' : 'Saved';
  String get saveLocation => isZh ? '保存位置' : 'Save location';
  String get preferencesSavedImmediately => isZh
      ? '语言、主题和聊天背景更改即时保存。'
      : 'Language, theme and chat background changes are saved immediately.';

  String get language => isZh ? '语言' : 'Language';
  String get theme => isZh ? '主题' : 'Theme';
  String get themeLight => isZh ? '浅色' : 'Light';
  String get themeDark => isZh ? '深色' : 'Dark';
  String get themeSystem => isZh ? '跟随系统' : 'System';
  String get location => isZh ? '位置' : 'Location';
  String get locationDescription => isZh
      ? '可选。会随每条消息提供给模型，用于本地化建议。'
      : 'Optional. Sent with each message for localized answers.';
  String get locationPlaceholder => isZh ? '例如：北京市' : 'e.g. Beijing';

  String get data => isZh ? '数据' : 'Data';
  String get deleteAllChats => isZh ? '删除所有对话' : 'Delete all chats';
  String get deleteAllChatsDescription => isZh
      ? '清空本机的全部对话、附件与草稿，API Key 和设置会保留。'
      : 'Remove all local chats, attachments and drafts. Your API key and settings stay.';
  String get deleteAllChatsConfirm => isZh
      ? '确定要删除所有对话吗？此操作无法撤销。'
      : 'Delete every chat? This cannot be undone.';
  String get deletedAllChats => isZh ? '已删除所有对话' : 'All chats deleted';

  String get uploadUnsupported => isZh ? '不支持的文件格式' : 'Unsupported file type';
  String get uploadFailed => isZh ? '上传失败' : 'Upload failed';
  String get uploadRetry => isZh ? '点击重试' : 'Tap to retry';
  String get attachmentRemove => isZh ? '移除附件' : 'Remove attachment';
  String get image => isZh ? '图片' : 'Image';
  String get document => isZh ? '文档' : 'Document';

  String get editPromptTitle => isZh ? '编辑提问' : 'Edit message';
  String get editPromptHint =>
      isZh ? '修改后将从这里重新生成回答' : 'The reply will be regenerated from here';
  String get attachedFiles => isZh ? '附件' : 'Attachments';
  String get noMessages => isZh ? '还没有消息' : 'No messages yet';
  String get initFailed =>
      isZh ? '本地数据加载失败，部分记录可能不可用' : 'Failed to load local data';
  String get renameHint => isZh ? '输入对话名称' : 'Chat name';
  String get deleteAll => isZh ? '全部删除' : 'Delete all';
  String get about => isZh ? '关于' : 'About';
  String get aboutDescription => isZh
      ? 'Cholk，基于 DeepSeek API 的 Flutter 聊天客户端。'
      : 'Cholk, a Flutter chat client for the DeepSeek API.';
  String get versionLabel => isZh ? '版本' : 'Version';

  String get startChat => isZh ? '开始对话' : 'Start chat';
  String get persona => isZh ? '人格' : 'Persona';
  String get startChatSub => 'START CHAT';
  String get personaSub => 'PERSONA';
  String get settingsSub => 'SETTINGS';
  String get backToHome => isZh ? '返回主界面' : 'Back to home';
  String get home => isZh ? '主界面' : 'Home';
  String get personaPageDescription => isZh
      ? '选择对话时的身份与语气。人格会作为系统提示的一部分发送给模型。'
      : 'Choose the identity and tone for conversations. The persona is sent as part of the system prompt.';
  String get personaNote => isZh
      ? '切换人格只影响之后新发送的消息，不会改写已有对话。'
      : 'Changing a persona only affects new messages; existing conversations are not rewritten.';
  String get personaActive => isZh ? '当前' : 'Active';
  String get done => isZh ? '完成' : 'Done';

  String get selectPrompt => isZh ? '选择一项开始' : 'Choose an option to begin';
}

String plainReplyError(ReplyError e, bool zh) {
  final status = e.status;
  if (e.kind == 'auth' || status == 401 || status == 403) {
    return zh
        ? '登录已失效或密钥不对。去「设置 → 账号」重新登录即可。'
        : 'Your sign-in expired or the key is wrong. Sign in again in Settings → Account.';
  }
  if (e.kind == 'network') {
    return zh
        ? '网络没连上。检查网络后点「重新生成」。'
        : "Can't reach the network. Check your connection, then tap Regenerate.";
  }
  if (e.kind == 'interrupted') {
    return zh
        ? '回复被中断了，已保留写好的部分。点「继续」或「重新生成」。'
        : 'The reply was interrupted; what was written is kept. Tap Continue or Regenerate.';
  }
  if (status == 429) {
    return zh
        ? '请求太频繁，稍等几秒再试。'
        : 'Too many requests. Wait a few seconds and try again.';
  }
  if ((status != null && status >= 500 && status < 600) ||
      e.message == 'upstream_unavailable') {
    return zh
        ? '模型服务暂时不可用，不是你的问题。稍后再试。'
        : 'The model service is temporarily unavailable — not your fault. Try again shortly.';
  }
  return zh
      ? '出了点问题。点「重新生成」再试一次。'
      : 'Something went wrong. Tap Regenerate to try again.';
}
