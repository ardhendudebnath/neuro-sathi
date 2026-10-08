import 'package:flutter/material.dart';

/// The part of the day the home screen's sky shows. Evening starts at 5 PM,
/// like the evening greeting; night runs until 4 AM.
enum DayPart {
  morning,
  afternoon,
  evening,
  night;

  static DayPart of(int hour) {
    if (hour >= 4 && hour < 12) return morning;
    if (hour >= 12 && hour < 17) return afternoon;
    if (hour >= 17 && hour < 20) return evening;
    return night;
  }
}

/// Colors of the hills header for one part of the day: the sky, four hill
/// layers from far to near, the sun or moon, and the text drawn on top.
class SkyPalette {
  const SkyPalette({
    required this.skyTop,
    required this.skyBottom,
    required this.hills,
    required this.mist,
    required this.sun,
    required this.sunRadius,
    required this.sunCore,
    required this.sunGlow,
    required this.ink,
    this.moon = false,
    this.stars = false,
    this.birds = false,
    this.fireflies = false,
  });

  final Color skyTop;
  final Color skyBottom;
  final List<Color> hills;
  final Color mist;

  /// Where the sun or moon sits, as a fraction of the header's size.
  final Offset sun;
  final double sunRadius;
  final List<Color> sunCore;
  final Color sunGlow;

  /// Text on the sky: dark by day, white in the evening and at night.
  final Color ink;
  final bool moon;
  final bool stars;
  final bool birds;
  final bool fireflies;

  bool get darkSky => ink == Colors.white;

  /// The sky color behind the greeting, which sits a little above the middle.
  Color get behindGreeting => Color.lerp(skyTop, skyBottom, 0.55)!;

  static SkyPalette of(DayPart part) => switch (part) {
        DayPart.morning => morning,
        DayPart.afternoon => afternoon,
        DayPart.evening => evening,
        DayPart.night => night,
      };

  static const morning = SkyPalette(
    skyTop: Color(0xFF8FCBEA),
    skyBottom: Color(0xFFFFE3BC),
    hills: [Color(0xFFAFCBD2), Color(0xFF86B5A8), Color(0xFF4F9273), Color(0xFF2E6A4E)],
    mist: Color(0xFFFFFFFF),
    sun: Offset(0.2, 0.5),
    sunRadius: 20,
    sunCore: [Color(0xFFFFFDF0), Color(0xFFFFD45C), Color(0xFFFFA51F)],
    sunGlow: Color(0xFFFFBE50),
    ink: Color(0xFF0F2C3D),
    birds: true,
  );

  static const afternoon = SkyPalette(
    skyTop: Color(0xFF4FA8EA),
    skyBottom: Color(0xFFD4EEFF),
    hills: [Color(0xFFA9CFE0), Color(0xFF7DB89E), Color(0xFF4C9670), Color(0xFF2B7250)],
    mist: Color(0xFFFFFFFF),
    sun: Offset(0.8, 0.2),
    sunRadius: 19,
    sunCore: [Color(0xFFFFFFF4), Color(0xFFFFEF80), Color(0xFFFFC433)],
    sunGlow: Color(0xFFFFE16E),
    ink: Color(0xFF0F2C3D),
    birds: true,
  );

  static const evening = SkyPalette(
    skyTop: Color(0xFF3A2A8C),
    skyBottom: Color(0xFFF29A6E),
    hills: [Color(0xFFB07B9A), Color(0xFF7C5A8B), Color(0xFF523D72), Color(0xFF2D2047)],
    mist: Color(0xFFFFD6C8),
    sun: Offset(0.72, 0.56),
    sunRadius: 22,
    sunCore: [Color(0xFFFFF1D4), Color(0xFFFFAE5A), Color(0xFFEE6436)],
    sunGlow: Color(0xFFFF8250),
    ink: Colors.white,
    fireflies: true,
  );

  static const night = SkyPalette(
    skyTop: Color(0xFF0A1432),
    skyBottom: Color(0xFF26306C),
    hills: [Color(0xFF33477A), Color(0xFF24355F), Color(0xFF172548), Color(0xFF0D1632)],
    mist: Color(0xFFAABEFF),
    sun: Offset(0.78, 0.18),
    sunRadius: 16,
    sunCore: [Color(0xFFFFFFFF), Color(0xFFE8ECF8), Color(0xFFB9C1DB)],
    sunGlow: Color(0xFFBECDFF),
    ink: Colors.white,
    moon: true,
    stars: true,
    fireflies: true,
  );
}

/// WCAG contrast ratio between two colors (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
