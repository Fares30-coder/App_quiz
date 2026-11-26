import 'package:material_ui/material_ui.dart';

/// Thème unique de Quizzéo, tiré de `design/charte.md` (§ 2, 3, 6, 7 bis, 8).

abstract final class AppFonts {
  /// Titres, scores, chiffres, logo (700, 800).
  static const titre = 'BricolageGrotesque';

  /// Texte, boutons, réponses (400, 700).
  static const texte = 'AtkinsonHyperlegible';
}

/// Grille de 4 dp. Marges d'écran : 20 dp.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const screen = 20.0;
}

abstract final class AppRadius {
  static const small = 12.0; // pastilles, petites cartes
  static const medium = 16.0; // boutons, cartes de réponse
  static const large = 24.0; // carte défi, feuilles du bas
  static const pill = 999.0;
}

/// Couleurs hors ColorScheme : succès, timer, catégories, texte corail.
@immutable
class QuizColors extends ThemeExtension<QuizColors> {
  const QuizColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.timerWarning,
    required this.primaryText,
    required this.categoryTint,
    required this.categoryIcon,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  /// Ambre : anneau du timer entre 10 et 6 s.
  final Color timerWarning;

  /// Corail foncé : liens et texte corail sur fond clair.
  final Color primaryText;

  /// Clés : identifiants de catégorie (`histoire`, `geo`…) + `mix`.
  final Map<String, Color> categoryTint;
  final Map<String, Color> categoryIcon;

  static const light = QuizColors(
    success: Color(0xFF17784A),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDDF3E6),
    onSuccessContainer: Color(0xFF0F5C37),
    timerWarning: Color(0xFF9A6500),
    primaryText: Color(0xFFB8301A),
    categoryTint: {
      'histoire': Color(0xFFFBE3D3),
      'geo': Color(0xFFD8EEF0),
      'sciences': Color(0xFFE3E4FB),
      'arts': Color(0xFFFBE0EC),
      'sport': Color(0xFFE1F2D5),
      'actu': Color(0xFFFFF0C7),
      'divers': Color(0xFFECE7DF),
      'mix': Color(0xFFFFE1D8),
    },
    categoryIcon: {
      'histoire': Color(0xFFA3401A),
      'geo': Color(0xFF0E6E72),
      'sciences': Color(0xFF3E4BB8),
      'arts': Color(0xFFB02A6B),
      'sport': Color(0xFF2F7A1F),
      'actu': Color(0xFF8A5A00),
      'divers': Color(0xFF6B5B45),
      'mix': Color(0xFFB8301A),
    },
  );

  static const dark = QuizColors(
    success: Color(0xFF5BD69A),
    onSuccess: Color(0xFF12132A),
    successContainer: Color(0xFF0F3A2A),
    onSuccessContainer: Color(0xFF5BD69A),
    timerWarning: Color(0xFFFFC23D),
    primaryText: Color(0xFFFF7A5C),
    categoryTint: {
      'histoire': Color(0xFF1E2042),
      'geo': Color(0xFF1E2042),
      'sciences': Color(0xFF1E2042),
      'arts': Color(0xFF1E2042),
      'sport': Color(0xFF1E2042),
      'actu': Color(0xFF1E2042),
      'divers': Color(0xFF1E2042),
      'mix': Color(0xFF1E2042),
    },
    categoryIcon: {
      'histoire': Color(0xFFFF9A6B),
      'geo': Color(0xFF4FC7C9),
      'sciences': Color(0xFF9AA4FF),
      'arts': Color(0xFFFF8AC0),
      'sport': Color(0xFF8FD66B),
      'actu': Color(0xFFFFC23D),
      'divers': Color(0xFFD2C2A8),
      'mix': Color(0xFFFF7A5C),
    },
  );

  @override
  QuizColors copyWith() => this;

  @override
  QuizColors lerp(QuizColors? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// Couleurs d'engagement (charte § 7 bis) : flamme, gel, XP, combo, rapidité.
@immutable
class EngagementColors extends ThemeExtension<EngagementColors> {
  const EngagementColors({
    required this.flammeExt,
    required this.flammeInt,
    required this.gel,
    required this.gelContainer,
    required this.onGelContainer,
    required this.gelBorder,
    required this.xp,
    required this.onXp,
    required this.xpContainer,
    required this.onXpContainer,
    required this.xpGain,
    required this.comboBg,
    required this.comboText,
    required this.comboIcon,
    required this.comboBorder,
    required this.rapide,
  });

  final Color flammeExt;
  final Color flammeInt;
  final Color gel;
  final Color gelContainer;
  final Color onGelContainer;

  /// Bordure des éléments « gel » (sombre seulement).
  final Color? gelBorder;
  final Color xp;
  final Color onXp;
  final Color xpContainer;
  final Color onXpContainer;
  final Color xpGain;
  final Color comboBg;
  final Color comboText;
  final Color comboIcon;

  /// Bordure de la pilule combo (sombre seulement).
  final Color? comboBorder;
  final Color rapide;

  static const light = EngagementColors(
    flammeExt: Color(0xFFD63A1F),
    flammeInt: Color(0xFFFFC23D),
    gel: Color(0xFF1F5E8C),
    gelContainer: Color(0xFFDDEBF6),
    onGelContainer: Color(0xFF1A1B3A),
    gelBorder: null,
    xp: Color(0xFF0E6E72),
    onXp: Color(0xFFFFFFFF),
    xpContainer: Color(0xFFD8EEF0),
    onXpContainer: Color(0xFF0A3F42),
    xpGain: Color(0xFFFFC23D),
    comboBg: Color(0xFF1A1B3A),
    comboText: Color(0xFFFFF7EE),
    comboIcon: Color(0xFFFFC23D),
    comboBorder: null,
    rapide: Color(0xFF9A6500),
  );

  static const dark = EngagementColors(
    flammeExt: Color(0xFFFF7A5C),
    flammeInt: Color(0xFFFFC23D),
    gel: Color(0xFF8CC8F0),
    gelContainer: Color(0xFF1E2042),
    onGelContainer: Color(0xFFF5F1EA),
    gelBorder: Color(0xFF8CC8F0),
    xp: Color(0xFF4FC7C9),
    onXp: Color(0xFF12132A),
    xpContainer: Color(0xFF133F45),
    onXpContainer: Color(0xFFF5F1EA),
    xpGain: Color(0xFFFFC23D),
    comboBg: Color(0xFF2A2C55),
    comboText: Color(0xFFF5F1EA),
    comboIcon: Color(0xFFFFC23D),
    comboBorder: Color(0xFFFFC23D),
    rapide: Color(0xFFFFC23D),
  );

  @override
  EngagementColors copyWith() => this;

  @override
  EngagementColors lerp(EngagementColors? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

extension ThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  QuizColors get quizColors => Theme.of(this).extension<QuizColors>()!;
  EngagementColors get engagement =>
      Theme.of(this).extension<EngagementColors>()!;

  /// « Réduire les animations » activé dans le système.
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);
}

abstract final class AppTheme {
  static const lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFD63A1F),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFE1D8),
    onPrimaryContainer: Color(0xFF5A1406),
    secondary: Color(0xFF0E6E72),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFD8EEF0),
    onSecondaryContainer: Color(0xFF0A3F42),
    tertiary: Color(0xFFFFC23D),
    onTertiary: Color(0xFF1A1B3A),
    error: Color(0xFFC42B3A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFCE3E5),
    onErrorContainer: Color(0xFF9E1C2A),
    surface: Color(0xFFFFF7EE),
    onSurface: Color(0xFF1A1B3A),
    onSurfaceVariant: Color(0xFF4A4C6B),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFF6EEE3),
    outline: Color(0xFF8A8CA6),
    outlineVariant: Color(0xFFE6DED2),
  );

  static const darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFF7A5C),
    onPrimary: Color(0xFF12132A),
    primaryContainer: Color(0xFF5A1E12),
    onPrimaryContainer: Color(0xFFFFD9CF),
    secondary: Color(0xFF4FC7C9),
    onSecondary: Color(0xFF12132A),
    secondaryContainer: Color(0xFF133F45),
    onSecondaryContainer: Color(0xFFF5F1EA),
    tertiary: Color(0xFFFFC23D),
    onTertiary: Color(0xFF12132A),
    error: Color(0xFFFF8A95),
    onError: Color(0xFF12132A),
    errorContainer: Color(0xFF45161F),
    onErrorContainer: Color(0xFFFFD9DC),
    surface: Color(0xFF12132A),
    onSurface: Color(0xFFF5F1EA),
    onSurfaceVariant: Color(0xFFB4B6D0),
    surfaceContainerLowest: Color(0xFF1E2042),
    surfaceContainer: Color(0xFF2A2C55),
    outline: Color(0xFF6E7096),
    outlineVariant: Color(0xFF34365E),
  );

  static ThemeData get light =>
      _build(lightScheme, QuizColors.light, EngagementColors.light);
  static ThemeData get dark =>
      _build(darkScheme, QuizColors.dark, EngagementColors.dark);

  static TextTheme _textTheme(ColorScheme c) {
    TextStyle titre(double size, FontWeight w) => TextStyle(
          fontFamily: AppFonts.titre,
          fontSize: size,
          fontWeight: w,
          height: 1.25,
          color: c.onSurface,
        );
    TextStyle texte(double size, FontWeight w, {Color? color}) => TextStyle(
          fontFamily: AppFonts.texte,
          fontSize: size,
          fontWeight: w,
          height: 1.45,
          color: color ?? c.onSurface,
        );
    return TextTheme(
      displayLarge: titre(72, FontWeight.w800).copyWith(
        height: 1,
        letterSpacing: -2,
      ),
      displaySmall: titre(36, FontWeight.w800),
      headlineMedium: titre(28, FontWeight.w800), // titre d'écran
      headlineSmall: titre(24, FontWeight.w700), // question
      titleLarge: titre(20, FontWeight.w700), // titre de carte
      titleMedium: texte(17, FontWeight.w700),
      titleSmall: texte(16, FontWeight.w700),
      bodyLarge: texte(16, FontWeight.w400),
      bodyMedium: texte(14, FontWeight.w400, color: c.onSurfaceVariant),
      bodySmall: texte(13, FontWeight.w400, color: c.onSurfaceVariant),
      labelLarge: texte(17, FontWeight.w700),
      labelMedium: texte(15, FontWeight.w700),
      labelSmall: texte(13, FontWeight.w700),
    );
  }

  static ThemeData _build(
    ColorScheme c,
    QuizColors quiz,
    EngagementColors engagement,
  ) {
    final text = _textTheme(c);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: c,
      fontFamily: AppFonts.texte,
      textTheme: text,
      scaffoldBackgroundColor: c.surface,
      extensions: [quiz, engagement],
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: buttonShape,
          side: BorderSide(color: c.outline, width: 2),
          foregroundColor: c.onSurface,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: buttonShape,
          foregroundColor: quiz.primaryText,
          textStyle: text.labelLarge,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: c.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          side: BorderSide(color: c.outlineVariant, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: c.surfaceContainerLowest,
        indicatorColor: c.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(height: 1),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.outlineVariant, thickness: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceContainerLowest,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.large),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.onSurface,
        contentTextStyle: text.bodyLarge?.copyWith(color: c.surface),
      ),
    );
  }
}
