import 'package:flutter/material.dart';

import '../core/models.dart';

/// Design tokens for the glass panel: frosted translucent surfaces over a soft
/// coloured backdrop, in a light and a dark variant.
@immutable
class PanelColors extends ThemeExtension<PanelColors> {
  const PanelColors({
    required this.background,
    required this.backdrop,
    required this.blobs,
    required this.glassFill,
    required this.glassBorder,
    required this.glassHighlight,
    required this.surface,
    required this.surfaceHigh,
    required this.textPrimary,
    required this.textMuted,
    required this.normal,
    required this.warning,
    required this.alarm,
    required this.info,
    required this.track,
  });

  /// Solid fallback behind everything.
  final Color background;

  /// Top-left → bottom-right gradient of the backdrop.
  final List<Color> backdrop;

  /// Soft colour glows behind the glass (what the blur picks up).
  final List<Color> blobs;

  /// Frosted glass: tinted fill, hairline border, light top edge.
  final Color glassFill;
  final Color glassBorder;
  final Color glassHighlight;

  /// Chips and the selected nav item, on top of glass.
  final Color surface;
  final Color surfaceHigh;

  final Color textPrimary;
  final Color textMuted;
  final Color normal;
  final Color warning;
  final Color alarm;
  final Color info;

  /// Gauge track, chart grid, dividers.
  final Color track;

  static const dark = PanelColors(
    background: Color(0xFF0A0F1E),
    backdrop: [Color(0xFF0B1022), Color(0xFF151A3A), Color(0xFF0A1A24)],
    blobs: [Color(0x803B82F6), Color(0x708B5CF6), Color(0x6014B8A6)],
    glassFill: Color(0x1AFFFFFF),
    glassBorder: Color(0x33FFFFFF),
    glassHighlight: Color(0x26FFFFFF),
    surface: Color(0x14FFFFFF),
    surfaceHigh: Color(0x29FFFFFF),
    textPrimary: Color(0xFFF2F4F8),
    textMuted: Color(0xFFA3ADC2),
    normal: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    alarm: Color(0xFFFF5A5F),
    info: Color(0xFF60A5FA),
    track: Color(0x2EFFFFFF),
  );

  static const light = PanelColors(
    background: Color(0xFFEEF2FB),
    backdrop: [Color(0xFFE6ECFF), Color(0xFFF4E8FF), Color(0xFFE2F6F1)],
    blobs: [Color(0x8060A5FA), Color(0x70C084FC), Color(0x605EEAD4)],
    glassFill: Color(0x8CFFFFFF),
    glassBorder: Color(0xB3FFFFFF),
    glassHighlight: Color(0xCCFFFFFF),
    surface: Color(0x66FFFFFF),
    surfaceHigh: Color(0xB3FFFFFF),
    textPrimary: Color(0xFF0F172A),
    textMuted: Color(0xFF526077),
    normal: Color(0xFF059669),
    warning: Color(0xFFD97706),
    alarm: Color(0xFFE11D48),
    info: Color(0xFF2563EB),
    track: Color(0x1F0F172A),
  );

  Color forState(AlarmState s, {bool sensorLost = false}) {
    if (sensorLost) return warning;
    return switch (s) {
      AlarmState.normal => normal,
      AlarmState.pending => warning,
      AlarmState.alarm => alarm,
      AlarmState.acknowledged => warning,
    };
  }

  @override
  PanelColors copyWith() => this;

  /// Lets light ⇄ dark cross-fade instead of snapping.
  @override
  PanelColors lerp(PanelColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> l(List<Color> a, List<Color> b) => [
      for (var i = 0; i < a.length; i++) c(a[i], b[i]),
    ];
    return PanelColors(
      background: c(background, other.background),
      backdrop: l(backdrop, other.backdrop),
      blobs: l(blobs, other.blobs),
      glassFill: c(glassFill, other.glassFill),
      glassBorder: c(glassBorder, other.glassBorder),
      glassHighlight: c(glassHighlight, other.glassHighlight),
      surface: c(surface, other.surface),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh),
      textPrimary: c(textPrimary, other.textPrimary),
      textMuted: c(textMuted, other.textMuted),
      normal: c(normal, other.normal),
      warning: c(warning, other.warning),
      alarm: c(alarm, other.alarm),
      info: c(info, other.info),
      track: c(track, other.track),
    );
  }
}

extension PanelThemeX on BuildContext {
  PanelColors get panel => Theme.of(this).extension<PanelColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}

ThemeData buildPanelTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? PanelColors.dark
      : PanelColors.light;
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.info,
      brightness: brightness,
      primary: c.info,
      surface: c.background,
    ),
    // The glass backdrop is painted by the shell, so the scaffold is clear.
    scaffoldBackgroundColor: Colors.transparent,
    // Panel UI: no splash ripples and big touch targets.
    splashFactory: NoSplash.splashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
  return base.copyWith(
    extensions: [c],
    textTheme: base.textTheme.apply(
      bodyColor: c.textPrimary,
      displayColor: c.textPrimary,
    ),
    iconTheme: IconThemeData(color: c.textPrimary),
    dividerColor: c.track,
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: c.surfaceHigh,
      selectedIconTheme: IconThemeData(color: c.info, size: 28),
      unselectedIconTheme: IconThemeData(color: c.textMuted, size: 26),
      selectedLabelTextStyle: TextStyle(
        color: c.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(color: c.textMuted),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.info,
      inactiveTrackColor: c.track,
      thumbColor: c.info,
      trackHeight: 6,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: c.glassBorder)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.surfaceHigh : c.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.info : c.textPrimary,
        ),
      ),
    ),
  );
}
