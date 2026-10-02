import 'package:flutter/material.dart';

class NestColors extends ThemeExtension<NestColors> {
  const NestColors({
    required this.bg,
    required this.surface,
    required this.socket,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.blocks,
  });

  final Color bg;
  final Color surface;
  final Color socket;
  final Color line;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color danger;
  final List<Color> blocks;

  static const blocksPalette = <Color>[
    Color(0xFFE07A5F),
    Color(0xFF3AA89A),
    Color(0xFFF0B429),
    Color(0xFF6B8AF2),
    Color(0xFFE16B8C),
    Color(0xFF7EAE55),
    Color(0xFFB07CC6),
    Color(0xFFF0943A),
    Color(0xFF4C9BE0),
    Color(0xFFD97B52),
  ];

  static const light = NestColors(
    bg: Color(0xFFF4F0E7),
    surface: Color(0xFFFFFCF8),
    socket: Color(0xFFE7DCCB),
    line: Color(0xFFD5C6B2),
    text: Color(0xFF2C2824),
    muted: Color(0xFF746C62),
    accent: Color(0xFF2F6F56),
    onAccent: Color(0xFFF7FBF8),
    danger: Color(0xFFC4544E),
    blocks: blocksPalette,
  );

  static const dark = NestColors(
    bg: Color(0xFF12141A),
    surface: Color(0xFF1B1E27),
    socket: Color(0xFF262B36),
    line: Color(0xFF3A4150),
    text: Color(0xFFF6F1E8),
    muted: Color(0xFFB3AA9E),
    accent: Color(0xFF8FCBB0),
    onAccent: Color(0xFF102019),
    danger: Color(0xFFE07A72),
    blocks: blocksPalette,
  );

  @override
  NestColors copyWith({
    Color? bg,
    Color? surface,
    Color? socket,
    Color? line,
    Color? text,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Color? danger,
    List<Color>? blocks,
  }) {
    return NestColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      socket: socket ?? this.socket,
      line: line ?? this.line,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      blocks: blocks ?? this.blocks,
    );
  }

  @override
  NestColors lerp(ThemeExtension<NestColors>? other, double t) {
    if (other is! NestColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return NestColors(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      socket: mix(socket, other.socket),
      line: mix(line, other.line),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      danger: mix(danger, other.danger),
      blocks: t < 0.5 ? blocks : other.blocks,
    );
  }
}

NestColors nestOf(BuildContext context) {
  return Theme.of(context).extension<NestColors>()!;
}

ThemeData nestTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? NestColors.dark
      : NestColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: brightness,
      ).copyWith(
        primary: colors.accent,
        onPrimary: colors.onAccent,
        surface: colors.surface,
        onSurface: colors.text,
        error: colors.danger,
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: colors.bg,
    splashColor: colors.accent.withValues(alpha: 0.12),
    highlightColor: colors.accent.withValues(alpha: 0.08),
    iconTheme: IconThemeData(color: colors.text),
    textTheme: base.textTheme.apply(
      bodyColor: colors.text,
      displayColor: colors.text,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.text,
        disabledForegroundColor: colors.muted.withValues(alpha: 0.4),
      ),
    ),
    extensions: [colors],
  );
}
