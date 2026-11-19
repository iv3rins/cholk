import 'package:material_ui/material_ui.dart';

/// Lineism, printed: a two-drum risograph on newsprint.
///
/// One working ink (cobalt) carries every primary action; vermilion is the
/// second drum — used only for live state, focus and the occasional
/// mis-registered offset. Everything else is paper, blue-black text and rules.
/// Offsets are hard (no blur): ink sits on paper, it does not float.
class Lineism {
  const Lineism._();

  // Newsprint.
  static const paper = Color(0xFFF2ECDF);
  static const paper2 = Color(0xFFE9E1CF);
  // Blue-black text ink and its wash.
  static const ink = Color(0xFF171B2E);
  static const ink2 = Color(0xFF585B6B);
  static const rule = Color(0xFFCDC3AE);
  // Drum one: riso cobalt. Drum two: vermilion.
  static const cobalt = Color(0xFF2547C9);
  static const signal = Color(0xFFFF4F2B);

  static const double hair = 0.75;
  static const double base = 1.25;
  static const double emphasis = 2;
  static const double hero = 3;

  /// The hard offset of a second print pass.
  static const Offset misprint = Offset(3, 3);

  static const String serifFamily = 'Cholk Serif';
  static const List<String> serifFallback = [
    'Noto Serif CJK SC',
    'Songti SC',
    'SimSun',
    'Georgia',
    'serif',
  ];

  /// Display: 得意黑 Smiley Sans, an oblique grotesque with Chinese cuts.
  static const String displayFamily = 'Cholk Display';

  /// Meta: Xanh Mono, a calligraphic monospace for numbers and captions.
  static const String monoFamily = 'Cholk Mono';

  static const serif = TextStyle(
    fontFamily: serifFamily,
    fontFamilyFallback: serifFallback,
  );

  static const display = TextStyle(
    fontFamily: displayFamily,
    fontFamilyFallback: [serifFamily, ...serifFallback],
    height: 1.15,
  );

  static const mono = TextStyle(
    fontFamily: monoFamily,
    fontFamilyFallback: [serifFamily, 'Consolas', 'Menlo', 'monospace'],
    letterSpacing: .4,
  );
}
