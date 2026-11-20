import 'strings.dart';

extension BackgroundStrings on S {
  String get uploadBackground => isZh ? '上传图片' : 'Upload image';
  String get replaceBackground => isZh ? '更换图片' : 'Replace image';
  String get backgroundImageLabel => isZh ? '背景图片' : 'Background image';
  String get backgroundImageHint => isZh
      ? '上传一张图片作为聊天背景，图片会保存在本机。'
      : 'Upload a picture to show behind the chat. It stays on this device.';
  String get backgroundPatternLabel => isZh ? '纹理' : 'Pattern';
  String get backgroundDim => isZh ? '背景遮罩' : 'Dim picture';
  String get restoreDefaultBackground => isZh ? '恢复默认' : 'Restore default';
  String get backgroundUploadFailed =>
      isZh ? '无法使用这张图片' : 'Could not use this picture';
  String get backgroundUploadUnsupported => isZh
      ? '网页版暂不支持上传背景图片'
      : 'Uploading a background picture is not available on the web';
}
