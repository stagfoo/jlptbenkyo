/// Colours and type.
///
/// The one thing this app has to get right that a normal app does not is
/// Japanese text at a size you can actually read. A 14pt kanji is a
/// smudge — you cannot tell 待 from 持 at body size on a phone, and being
/// unable to see the difference between two characters is indistinguishable
/// from not knowing it. So Japanese has its own scale, well above the
/// Material defaults, and everything else is laid out around that.
library;

import 'package:flutter/material.dart';

/// The one colour everything else is derived from.
class Palette {
  static const seed = Color(0xFF3F51B5);
}

/// Sizes for Japanese text, by how much of it there is.
class Jp {
  /// A single kanji being studied. Large enough to see every stroke.
  static const TextStyle character = TextStyle(
    fontSize: 120,
    height: 1.1,
    fontWeight: FontWeight.w400,
  );

  /// A vocabulary word on a card.
  static const TextStyle word = TextStyle(
    fontSize: 48,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );

  /// A grammar pattern.
  static const TextStyle pattern = TextStyle(
    fontSize: 32,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );

  /// A whole sentence. Smaller than a word because there is more of it,
  /// but still well above body size — and with generous line height,
  /// because Japanese has no spaces and a tight line is a wall.
  static const TextStyle sentence = TextStyle(
    fontSize: 26,
    height: 1.8,
  );

  /// Readings and furigana-ish annotations.
  static const TextStyle reading = TextStyle(
    fontSize: 22,
    height: 1.4,
  );
}

/// The colour each JLPT level is shown in, so a level is recognisable at
/// a glance without reading the label.
Color levelColour(int level) => switch (level) {
      5 => const Color(0xFF43A047),
      4 => const Color(0xFF1E88E5),
      3 => const Color(0xFF8E24AA),
      _ => const Color(0xFF757575),
    };

String levelName(int level) => level == 0 ? 'above N3' : 'N$level';

/// The four answer buttons, in order, with the colours people already
/// associate with them from every other SRS.
Color gradeColour(int index) => switch (index) {
      0 => const Color(0xFFE53935),
      1 => const Color(0xFFFB8C00),
      2 => const Color(0xFF43A047),
      _ => const Color(0xFF1E88E5),
    };

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.seed,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Big targets. This is an app used one-handed, at speed, many
        // times a day — a cramped answer row is a mis-grade, and a
        // mis-grade costs a card weeks of schedule.
        minimumSize: const Size(0, 56),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
