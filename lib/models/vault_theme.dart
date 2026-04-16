import 'package:flutter/material.dart';

@immutable
class VaultThemeColors extends ThemeExtension<VaultThemeColors> {
  final Color background;
  final Color backgroundAlt;
  final Color surface;
  final Color surfaceAlt;
  final Color accent;
  final Color accent2;
  final Color header;
  final Color border;
  final Color text;
  final Color textSoft;
  final Color buttonText;
  final Color danger;

  const VaultThemeColors({
    required this.background,
    required this.backgroundAlt,
    required this.surface,
    required this.surfaceAlt,
    required this.accent,
    required this.accent2,
    required this.header,
    required this.border,
    required this.text,
    required this.textSoft,
    required this.buttonText,
    required this.danger,
  });

  @override
  VaultThemeColors copyWith({
    Color? background,
    Color? backgroundAlt,
    Color? surface,
    Color? surfaceAlt,
    Color? accent,
    Color? accent2,
    Color? header,
    Color? border,
    Color? text,
    Color? textSoft,
    Color? buttonText,
    Color? danger,
  }) {
    return VaultThemeColors(
      background: background ?? this.background,
      backgroundAlt: backgroundAlt ?? this.backgroundAlt,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      header: header ?? this.header,
      border: border ?? this.border,
      text: text ?? this.text,
      textSoft: textSoft ?? this.textSoft,
      buttonText: buttonText ?? this.buttonText,
      danger: danger ?? this.danger,
    );
  }

  @override
  VaultThemeColors lerp(ThemeExtension<VaultThemeColors>? other, double t) {
    if (other is! VaultThemeColors) return this;
    return VaultThemeColors(
      background: Color.lerp(background, other.background, t) ?? background,
      backgroundAlt:
          Color.lerp(backgroundAlt, other.backgroundAlt, t) ?? backgroundAlt,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t) ?? surfaceAlt,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accent2: Color.lerp(accent2, other.accent2, t) ?? accent2,
      header: Color.lerp(header, other.header, t) ?? header,
      border: Color.lerp(border, other.border, t) ?? border,
      text: Color.lerp(text, other.text, t) ?? text,
      textSoft: Color.lerp(textSoft, other.textSoft, t) ?? textSoft,
      buttonText: Color.lerp(buttonText, other.buttonText, t) ?? buttonText,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
    );
  }
}

@immutable
class VaultThemePalette {
  final String id;
  final String name;
  final String description;
  final Color background;
  final Color backgroundAlt;
  final Color surface;
  final Color surfaceAlt;
  final Color accent;
  final Color accent2;
  final Color header;
  final Color border;
  final Color text;
  final Color textSoft;
  final Color buttonText;
  final Color danger;

  const VaultThemePalette({
    required this.id,
    required this.name,
    required this.description,
    required this.background,
    required this.backgroundAlt,
    required this.surface,
    required this.surfaceAlt,
    required this.accent,
    required this.accent2,
    required this.header,
    required this.border,
    required this.text,
    required this.textSoft,
    required this.buttonText,
    required this.danger,
  });

  VaultThemeColors get colors => VaultThemeColors(
    background: background,
    backgroundAlt: backgroundAlt,
    surface: surface,
    surfaceAlt: surfaceAlt,
    accent: accent,
    accent2: accent2,
    header: header,
    border: border,
    text: text,
    textSoft: textSoft,
    buttonText: buttonText,
    danger: danger,
  );

  ThemeData toThemeData() {
    final scheme = ColorScheme.dark(
      primary: accent,
      secondary: accent2,
      tertiary: header,
      surface: surface,
      error: danger,
      onPrimary: buttonText,
      onSecondary: buttonText,
      onTertiary: buttonText,
      onSurface: text,
      onError: Colors.white,
      outline: border,
      outlineVariant: border.withValues(alpha: 0.6),
      surfaceContainerHighest: surfaceAlt,
      surfaceContainerHigh: surfaceAlt,
      surfaceContainer: surface,
      surfaceContainerLow: backgroundAlt,
      surfaceContainerLowest: background,
      brightness: Brightness.dark,
    );

    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: border.withValues(alpha: 0.7),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.25,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: accent,
        disabledColor: surfaceAlt.withValues(alpha: 0.5),
        labelStyle: TextStyle(color: text),
        secondaryLabelStyle: TextStyle(color: buttonText),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      iconTheme: IconThemeData(color: text),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: text,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.4,
          height: 1.04,
        ),
        headlineMedium: TextStyle(
          color: text,
          fontSize: 28,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.25,
          height: 1.08,
        ),
        headlineSmall: TextStyle(
          color: text,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.15,
          height: 1.12,
        ),
        titleLarge: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
          height: 1.18,
        ),
        titleMedium: TextStyle(
          color: header,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.35,
          height: 1.22,
        ),
        bodyLarge: TextStyle(color: text, fontSize: 16, height: 1.45),
        bodyMedium: TextStyle(color: text, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: textSoft, fontSize: 12, height: 1.35),
        labelLarge: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: buttonText,
          disabledBackgroundColor: surfaceAlt,
          disabledForegroundColor: textSoft,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: buttonText,
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: TextStyle(color: textSoft),
        labelStyle: TextStyle(color: textSoft),
        counterStyle: TextStyle(color: textSoft),
        border: outlineBorder,
        enabledBorder: outlineBorder,
        focusedBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return buttonText;
          return Colors.white70;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accent.withValues(alpha: 0.35);
          }
          return surfaceAlt;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return surfaceAlt;
        }),
        checkColor: WidgetStateProperty.all(buttonText),
        side: BorderSide(color: border),
      ),
      extensions: <ThemeExtension<dynamic>>[colors],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'background': _colorToHex(background),
      'backgroundAlt': _colorToHex(backgroundAlt),
      'surface': _colorToHex(surface),
      'surfaceAlt': _colorToHex(surfaceAlt),
      'accent': _colorToHex(accent),
      'accent2': _colorToHex(accent2),
      'header': _colorToHex(header),
      'border': _colorToHex(border),
      'text': _colorToHex(text),
      'textSoft': _colorToHex(textSoft),
      'buttonText': _colorToHex(buttonText),
      'danger': _colorToHex(danger),
    };
  }

  factory VaultThemePalette.fromJson(Map<String, dynamic> json) {
    return VaultThemePalette(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : 'custom',
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Custom',
      description: (json['description'] as String?)?.trim().isNotEmpty == true
          ? (json['description'] as String).trim()
          : 'Custom palette',
      background: _parseColor(
        json['background'],
        fallback: const Color(0xFF0F0014),
      ),
      backgroundAlt: _parseColor(
        json['backgroundAlt'],
        fallback: const Color(0xFF140019),
      ),
      surface: _parseColor(json['surface'], fallback: const Color(0xFF19001F)),
      surfaceAlt: _parseColor(
        json['surfaceAlt'],
        fallback: const Color(0xFF22002C),
      ),
      accent: _parseColor(json['accent'], fallback: const Color(0xFFFF2DAA)),
      accent2: _parseColor(json['accent2'], fallback: const Color(0xFFB97BFF)),
      header: _parseColor(json['header'], fallback: const Color(0xFFB97BFF)),
      border: _parseColor(json['border'], fallback: const Color(0xFF3A0D4B)),
      text: _parseColor(json['text'], fallback: const Color(0xFFF8F2FF)),
      textSoft: _parseColor(
        json['textSoft'],
        fallback: const Color(0xFFDBCFE8),
      ),
      buttonText: _parseColor(
        json['buttonText'],
        fallback: const Color(0xFF14091D),
      ),
      danger: _parseColor(json['danger'], fallback: const Color(0xFFFF4D6D)),
    );
  }

  VaultThemePalette copyWith({
    String? id,
    String? name,
    String? description,
    Color? background,
    Color? backgroundAlt,
    Color? surface,
    Color? surfaceAlt,
    Color? accent,
    Color? accent2,
    Color? header,
    Color? border,
    Color? text,
    Color? textSoft,
    Color? buttonText,
    Color? danger,
  }) {
    return VaultThemePalette(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      background: background ?? this.background,
      backgroundAlt: backgroundAlt ?? this.backgroundAlt,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      header: header ?? this.header,
      border: border ?? this.border,
      text: text ?? this.text,
      textSoft: textSoft ?? this.textSoft,
      buttonText: buttonText ?? this.buttonText,
      danger: danger ?? this.danger,
    );
  }

  static Color _parseColor(Object? raw, {required Color fallback}) {
    if (raw is! String) return fallback;
    final value = raw.trim();
    if (value.isEmpty) return fallback;
    final normalized = value.startsWith('#') ? value.substring(1) : value;
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) return fallback;
    if (normalized.length <= 6) {
      return Color(0xFF000000 | parsed);
    }
    return Color(parsed);
  }

  static String _colorToHex(Color color) {
    final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${value.substring(value.length - 6).toUpperCase()}';
  }

  static const customId = 'custom';
  static const presets = <VaultThemePalette>[
    VaultThemePalette(
      id: 'obsidian_rose',
      name: 'Obsidian Rose',
      description: 'Current royal night palette',
      background: Color(0xFF0F0014),
      backgroundAlt: Color(0xFF1B1125),
      surface: Color(0xFF19001F),
      surfaceAlt: Color(0xFF24002E),
      accent: Color(0xFFFF2DAA),
      accent2: Color(0xFFB97BFF),
      header: Color(0xFFB97BFF),
      border: Color(0xFF3A0D4B),
      text: Color(0xFFF8F2FF),
      textSoft: Color(0xFFDBCFE8),
      buttonText: Color(0xFF14091D),
      danger: Color(0xFFFF4D6D),
    ),
    VaultThemePalette(
      id: 'amethyst_court',
      name: 'Amethyst Court',
      description: 'Purple focus with cool glass',
      background: Color(0xFF090812),
      backgroundAlt: Color(0xFF18132B),
      surface: Color(0xFF1B1732),
      surfaceAlt: Color(0xFF262040),
      accent: Color(0xFF9C6BFF),
      accent2: Color(0xFFFF72D8),
      header: Color(0xFFDAB6FF),
      border: Color(0xFF3D345D),
      text: Color(0xFFF7F3FF),
      textSoft: Color(0xFFC7BDD9),
      buttonText: Color(0xFF130A1C),
      danger: Color(0xFFFF637D),
    ),
    VaultThemePalette(
      id: 'midnight_ember',
      name: 'Midnight Ember',
      description: 'Indigo with ember highlights',
      background: Color(0xFF080B14),
      backgroundAlt: Color(0xFF151B2B),
      surface: Color(0xFF171D2F),
      surfaceAlt: Color(0xFF242A40),
      accent: Color(0xFFFF7B4A),
      accent2: Color(0xFF9B67FF),
      header: Color(0xFFE9D0FF),
      border: Color(0xFF36405D),
      text: Color(0xFFF7F8FF),
      textSoft: Color(0xFFCAD4E6),
      buttonText: Color(0xFF130A10),
      danger: Color(0xFFFF5B6B),
    ),
    VaultThemePalette(
      id: 'royal_plum',
      name: 'Royal Plum',
      description: 'Warm plum with a velvet core',
      background: Color(0xFF120816),
      backgroundAlt: Color(0xFF241029),
      surface: Color(0xFF200F24),
      surfaceAlt: Color(0xFF311536),
      accent: Color(0xFFE86FFF),
      accent2: Color(0xFFFF8AB5),
      header: Color(0xFFF3D1FF),
      border: Color(0xFF4A2350),
      text: Color(0xFFF9F4FF),
      textSoft: Color(0xFFE6CBEC),
      buttonText: Color(0xFF1A091F),
      danger: Color(0xFFFF5577),
    ),
    VaultThemePalette(
      id: 'aurora_violet',
      name: 'Aurora Violet',
      description: 'Icy glow with violet edge',
      background: Color(0xFF081019),
      backgroundAlt: Color(0xFF132033),
      surface: Color(0xFF17243A),
      surfaceAlt: Color(0xFF223551),
      accent: Color(0xFF59E8FF),
      accent2: Color(0xFFB76DFF),
      header: Color(0xFFB7EBFF),
      border: Color(0xFF33506D),
      text: Color(0xFFF4FBFF),
      textSoft: Color(0xFFD3E4F5),
      buttonText: Color(0xFF07111B),
      danger: Color(0xFFFF6E86),
    ),
    VaultThemePalette(
      id: 'lunar_steel',
      name: 'Lunar Steel',
      description: 'Neutral graphite with pale blue light',
      background: Color(0xFF0D1117),
      backgroundAlt: Color(0xFF151B22),
      surface: Color(0xFF1A2028),
      surfaceAlt: Color(0xFF232B36),
      accent: Color(0xFF6CC7FF),
      accent2: Color(0xFFE8A6FF),
      header: Color(0xFFD8E6F5),
      border: Color(0xFF3A475A),
      text: Color(0xFFF3F7FC),
      textSoft: Color(0xFFB8C7D8),
      buttonText: Color(0xFF081018),
      danger: Color(0xFFFF6E84),
    ),
    VaultThemePalette(
      id: 'crimson_dusk',
      name: 'Crimson Dusk',
      description: 'Red wine and hot magenta',
      background: Color(0xFF120810),
      backgroundAlt: Color(0xFF251019),
      surface: Color(0xFF210F19),
      surfaceAlt: Color(0xFF331223),
      accent: Color(0xFFFF557B),
      accent2: Color(0xFFFFA160),
      header: Color(0xFFFFD4DA),
      border: Color(0xFF4A2230),
      text: Color(0xFFFFF3F6),
      textSoft: Color(0xFFECC8D0),
      buttonText: Color(0xFF1E070D),
      danger: Color(0xFFFF7676),
    ),
    VaultThemePalette(
      id: 'emerald_oath',
      name: 'Emerald Oath',
      description: 'Forest jewel tone with clean mint',
      background: Color(0xFF07120E),
      backgroundAlt: Color(0xFF10201B),
      surface: Color(0xFF13251F),
      surfaceAlt: Color(0xFF1C372E),
      accent: Color(0xFF5DF2B4),
      accent2: Color(0xFF77A8FF),
      header: Color(0xFFD4FFE9),
      border: Color(0xFF315244),
      text: Color(0xFFF3FFF9),
      textSoft: Color(0xFFC8E4D6),
      buttonText: Color(0xFF06110B),
      danger: Color(0xFFFF7089),
    ),
    VaultThemePalette(
      id: 'sapphire_night',
      name: 'Sapphire Night',
      description: 'Deep blue with electric cyan',
      background: Color(0xFF07111C),
      backgroundAlt: Color(0xFF101D31),
      surface: Color(0xFF14233A),
      surfaceAlt: Color(0xFF20324F),
      accent: Color(0xFF52D6FF),
      accent2: Color(0xFF7F8CFF),
      header: Color(0xFFCFE9FF),
      border: Color(0xFF355170),
      text: Color(0xFFF1F8FF),
      textSoft: Color(0xFFC5D5EA),
      buttonText: Color(0xFF07101A),
      danger: Color(0xFFFF7685),
    ),
    VaultThemePalette(
      id: 'sunlit_garnet',
      name: 'Sunlit Garnet',
      description: 'Garnet core with golden trim',
      background: Color(0xFF120B09),
      backgroundAlt: Color(0xFF261613),
      surface: Color(0xFF211411),
      surfaceAlt: Color(0xFF34201B),
      accent: Color(0xFFFFB24A),
      accent2: Color(0xFFFF637E),
      header: Color(0xFFFFE2BC),
      border: Color(0xFF53322A),
      text: Color(0xFFFFF8F4),
      textSoft: Color(0xFFE8D3C8),
      buttonText: Color(0xFF1A0B07),
      danger: Color(0xFFFF7A6A),
    ),
    VaultThemePalette(
      id: 'obsidian_gold',
      name: 'Obsidian Gold',
      description: 'Black stone with gold edges',
      background: Color(0xFF090807),
      backgroundAlt: Color(0xFF181512),
      surface: Color(0xFF1A1714),
      surfaceAlt: Color(0xFF26211C),
      accent: Color(0xFFE7C26A),
      accent2: Color(0xFFB07AFF),
      header: Color(0xFFFFF0BE),
      border: Color(0xFF43392C),
      text: Color(0xFFFEFBF5),
      textSoft: Color(0xFFDCCFBC),
      buttonText: Color(0xFF19120A),
      danger: Color(0xFFFF6D81),
    ),
    VaultThemePalette(
      id: 'neon_orchid',
      name: 'Neon Orchid',
      description: 'Bright orchid with dark nightclub floor',
      background: Color(0xFF0D0712),
      backgroundAlt: Color(0xFF1A1023),
      surface: Color(0xFF241431),
      surfaceAlt: Color(0xFF331B44),
      accent: Color(0xFFFF61E8),
      accent2: Color(0xFF7AE0FF),
      header: Color(0xFFF0C7FF),
      border: Color(0xFF50325E),
      text: Color(0xFFFFF4FF),
      textSoft: Color(0xFFE4CBE9),
      buttonText: Color(0xFF1A0A1C),
      danger: Color(0xFFFF6B94),
    ),
    VaultThemePalette(
      id: 'deep_teal',
      name: 'Deep Teal',
      description: 'Ocean dark with clean cyan',
      background: Color(0xFF071417),
      backgroundAlt: Color(0xFF10282B),
      surface: Color(0xFF163338),
      surfaceAlt: Color(0xFF1F4650),
      accent: Color(0xFF53F0D0),
      accent2: Color(0xFF7D9CFF),
      header: Color(0xFFD0FFF4),
      border: Color(0xFF33565D),
      text: Color(0xFFF2FFFC),
      textSoft: Color(0xFFC9E9E2),
      buttonText: Color(0xFF061313),
      danger: Color(0xFFFF6A88),
    ),
    VaultThemePalette(
      id: 'indigo_crown',
      name: 'Indigo Crown',
      description: 'Deep indigo with bright regal accents',
      background: Color(0xFF0A0D19),
      backgroundAlt: Color(0xFF171C31),
      surface: Color(0xFF1B2140),
      surfaceAlt: Color(0xFF242B54),
      accent: Color(0xFF9170FF),
      accent2: Color(0xFFFF6FB6),
      header: Color(0xFFE7D9FF),
      border: Color(0xFF39406A),
      text: Color(0xFFF7F5FF),
      textSoft: Color(0xFFCFC8E6),
      buttonText: Color(0xFF120B1F),
      danger: Color(0xFFFF667F),
    ),
    VaultThemePalette(
      id: 'rose_quartz',
      name: 'Rose Quartz',
      description: 'Soft rose with a dark shell',
      background: Color(0xFF130C11),
      backgroundAlt: Color(0xFF261521),
      surface: Color(0xFF2B1827),
      surfaceAlt: Color(0xFF392133),
      accent: Color(0xFFFF8DD6),
      accent2: Color(0xFFFFC47A),
      header: Color(0xFFFFE3F5),
      border: Color(0xFF533046),
      text: Color(0xFFFFF7FB),
      textSoft: Color(0xFFE7D1DE),
      buttonText: Color(0xFF1B0C14),
      danger: Color(0xFFFF6481),
    ),
    VaultThemePalette(
      id: 'arctic_ink',
      name: 'Arctic Ink',
      description: 'Cold white-blue on ink black',
      background: Color(0xFF0B0F16),
      backgroundAlt: Color(0xFF141B26),
      surface: Color(0xFF192233),
      surfaceAlt: Color(0xFF24304A),
      accent: Color(0xFF98F0FF),
      accent2: Color(0xFFB09CFF),
      header: Color(0xFFE4FBFF),
      border: Color(0xFF37506C),
      text: Color(0xFFF3FBFF),
      textSoft: Color(0xFFC2D6E4),
      buttonText: Color(0xFF071018),
      danger: Color(0xFFFF6988),
    ),
    VaultThemePalette(
      id: 'forest_rite',
      name: 'Forest Rite',
      description: 'Moss, pine, and quiet glow',
      background: Color(0xFF07110C),
      backgroundAlt: Color(0xFF122119),
      surface: Color(0xFF17271E),
      surfaceAlt: Color(0xFF20392B),
      accent: Color(0xFF82E0A3),
      accent2: Color(0xFF9AE6FF),
      header: Color(0xFFD8FFE4),
      border: Color(0xFF375B47),
      text: Color(0xFFF2FFF6),
      textSoft: Color(0xFFC9E5D2),
      buttonText: Color(0xFF071009),
      danger: Color(0xFFFF7285),
    ),
    VaultThemePalette(
      id: 'ember_moss',
      name: 'Ember Moss',
      description: 'Earthy dark with warm sparks',
      background: Color(0xFF0F0C09),
      backgroundAlt: Color(0xFF1E1811),
      surface: Color(0xFF282019),
      surfaceAlt: Color(0xFF362D22),
      accent: Color(0xFFFFA25C),
      accent2: Color(0xFF94D89A),
      header: Color(0xFFFFE7C6),
      border: Color(0xFF55463A),
      text: Color(0xFFFFF9F2),
      textSoft: Color(0xFFE6D7C7),
      buttonText: Color(0xFF18110A),
      danger: Color(0xFFFF6E78),
    ),
    VaultThemePalette(
      id: 'moonlit_berry',
      name: 'Moonlit Berry',
      description: 'Berry dark with moon glow',
      background: Color(0xFF0F0814),
      backgroundAlt: Color(0xFF201126),
      surface: Color(0xFF2A1430),
      surfaceAlt: Color(0xFF392047),
      accent: Color(0xFFCE7BFF),
      accent2: Color(0xFF78DEFF),
      header: Color(0xFFF2D8FF),
      border: Color(0xFF563060),
      text: Color(0xFFFFF5FF),
      textSoft: Color(0xFFE8D6EE),
      buttonText: Color(0xFF170B1B),
      danger: Color(0xFFFF6788),
    ),
    VaultThemePalette(
      id: 'black_pearl',
      name: 'Black Pearl',
      description: 'Deep neutral with violet highlights',
      background: Color(0xFF08090C),
      backgroundAlt: Color(0xFF11141A),
      surface: Color(0xFF171A20),
      surfaceAlt: Color(0xFF232832),
      accent: Color(0xFFA48CFF),
      accent2: Color(0xFF6FE7FF),
      header: Color(0xFFE2DFFF),
      border: Color(0xFF343C4A),
      text: Color(0xFFF5F7FC),
      textSoft: Color(0xFFBEC7D8),
      buttonText: Color(0xFF080A10),
      danger: Color(0xFFFF697D),
    ),
    VaultThemePalette(
      id: 'velvet_fire',
      name: 'Velvet Fire',
      description: 'Plum velvet with fire accents',
      background: Color(0xFF11090D),
      backgroundAlt: Color(0xFF25101A),
      surface: Color(0xFF2B1220),
      surfaceAlt: Color(0xFF3A1A2D),
      accent: Color(0xFFFF8A61),
      accent2: Color(0xFFF870C4),
      header: Color(0xFFFFE1D7),
      border: Color(0xFF5A3045),
      text: Color(0xFFFFF6F4),
      textSoft: Color(0xFFE7D1CF),
      buttonText: Color(0xFF1C0B10),
      danger: Color(0xFFFF6673),
    ),
    VaultThemePalette(
      id: 'storm_lilac',
      name: 'Storm Lilac',
      description: 'Muted gray lilac with soft lightning',
      background: Color(0xFF101015),
      backgroundAlt: Color(0xFF1A1B23),
      surface: Color(0xFF222430),
      surfaceAlt: Color(0xFF2E3140),
      accent: Color(0xFFB695FF),
      accent2: Color(0xFF8BD5FF),
      header: Color(0xFFEAE4FF),
      border: Color(0xFF444A5A),
      text: Color(0xFFF7F7FF),
      textSoft: Color(0xFFC6C8D8),
      buttonText: Color(0xFF0F1018),
      danger: Color(0xFFFF6F82),
    ),
    VaultThemePalette(
      id: 'vintage_gold',
      name: 'Vintage Gold',
      description: 'Old-world gold on deep ink',
      background: Color(0xFF0E0A08),
      backgroundAlt: Color(0xFF1C1612),
      surface: Color(0xFF26201A),
      surfaceAlt: Color(0xFF342B23),
      accent: Color(0xFFD8AE59),
      accent2: Color(0xFF8BC7FF),
      header: Color(0xFFFFF0D0),
      border: Color(0xFF4C4132),
      text: Color(0xFFFFFBF4),
      textSoft: Color(0xFFE4D8C0),
      buttonText: Color(0xFF19120A),
      danger: Color(0xFFFF6E7D),
    ),
  ];
}

@immutable
class VaultThemeConfig {
  final String selectedId;
  final VaultThemePalette customPalette;

  const VaultThemeConfig({
    required this.selectedId,
    required this.customPalette,
  });

  factory VaultThemeConfig.defaults() {
    return const VaultThemeConfig(
      selectedId: 'obsidian_rose',
      customPalette: VaultThemePalette(
        id: VaultThemePalette.customId,
        name: 'Custom',
        description: 'Your own color set',
        background: Color(0xFF0F0014),
        backgroundAlt: Color(0xFF1B1125),
        surface: Color(0xFF19001F),
        surfaceAlt: Color(0xFF24002E),
        accent: Color(0xFFFF2DAA),
        accent2: Color(0xFFB97BFF),
        header: Color(0xFFB97BFF),
        border: Color(0xFF3A0D4B),
        text: Color(0xFFF8F2FF),
        textSoft: Color(0xFFDBCFE8),
        buttonText: Color(0xFF14091D),
        danger: Color(0xFFFF4D6D),
      ),
    );
  }

  VaultThemePalette get activePalette {
    if (selectedId == VaultThemePalette.customId) return customPalette;
    return VaultThemePalette.presets.firstWhere(
      (preset) => preset.id == selectedId,
      orElse: () => VaultThemePalette.presets.first,
    );
  }

  bool get isCustom => selectedId == VaultThemePalette.customId;

  VaultThemeConfig copyWith({
    String? selectedId,
    VaultThemePalette? customPalette,
  }) {
    return VaultThemeConfig(
      selectedId: selectedId ?? this.selectedId,
      customPalette: customPalette ?? this.customPalette,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'selectedId': selectedId,
      'customPalette': customPalette.toJson(),
    };
  }

  factory VaultThemeConfig.fromJson(Map<String, dynamic> json) {
    final selectedId = (json['selectedId'] as String?)?.trim();
    final customRaw = json['customPalette'];
    final customPalette = customRaw is Map
        ? VaultThemePalette.fromJson(Map<String, dynamic>.from(customRaw))
        : VaultThemeConfig.defaults().customPalette;
    return VaultThemeConfig(
      selectedId: selectedId != null && selectedId.isNotEmpty
          ? selectedId
          : 'obsidian_rose',
      customPalette: customPalette,
    );
  }
}
