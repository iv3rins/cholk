import 'strings.dart';

extension ModelListStrings on S {
  String get fetchModels => isZh ? '获取模型列表' : 'Fetch models';
  String get fetchingModels => isZh ? '正在获取模型…' : 'Fetching models…';
  String get fetchModelsFailed =>
      isZh ? '获取模型列表失败' : 'Could not fetch the model list';
  String get noModelsFound => isZh ? '没有可用的模型' : 'No models found';
  String get chooseModel => isZh ? '选择模型' : 'Choose a model';
  String get filterModels => isZh ? '筛选模型' : 'Filter models';
}
