import 'package:flutter/material.dart' show Color;

abstract final class CatalogDanmakuCodec {
  static int namedMode(Object? mode) => switch (mode) {
    'top' => 5,
    'bottom' => 4,
    _ => 1,
  };
  static int giriMode(Object? mode) => switch (int.tryParse('$mode')) {
    2 => 5,
    3 => 4,
    _ => 1,
  };
  static int xmlMode(Object? mode) => switch (int.tryParse('$mode')) {
    4 => 4,
    5 => 5,
    _ => 1,
  };
  static Color color(Object? raw) {
    final text = '${raw ?? ''}'.trim();
    final parsed = text.startsWith('#')
        ? int.tryParse(text.substring(1), radix: 16)
        : text.toLowerCase().startsWith('0x')
        ? int.tryParse(text.substring(2), radix: 16)
        : int.tryParse(text);
    return Color(0xff000000 | ((parsed ?? 0xffffff) & 0xffffff));
  }
}
