enum ChatMode {
  chat,
  work;

  static ChatMode fromWire(Object? value) => value == work.name ? work : chat;
}

enum ChatBackground {
  plain,
  ruled,
  grid,
  dots;

  static ChatBackground fromWire(Object? value) =>
      values.where((option) => option.name == value).firstOrNull ?? plain;
}
