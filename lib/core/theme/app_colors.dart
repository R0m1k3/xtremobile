import 'package:flutter/material.dart';

/// XtremFlow — "Apple Glass Gray" Design System
///
/// Palette : graphite neutre + blanc cassé + bleu système Apple.
/// Inspiration : verre dépoli iOS/visionOS — des gris francs, jamais un noir
/// pur, pour une interface nettement moins sombre que l'ancien thème.
///
/// Règle de perf : AUCUNE couleur de surface n'est translucide. La profondeur
/// vient des ombres et du contraste, pas du flou — pas de `BackdropFilter`,
/// coûteux à chaque frame sur les Android d'entrée de gamme. L'effet "glass"
/// est simulé par des gris élevés + liserés blancs à faible opacité.
class AppColors {
  AppColors._();

  // ============ BASE LEVEL 0 ============
  /// Graphite profond — le niveau le plus bas, jamais un noir pur.
  static const Color baseLevel0 = Color(0xFF1B1B1F);

  // ============ BACKGROUNDS ============
  static const Color background = Color(0xFF26262C);
  static const Color onBackground = Color(0xFFF5F5F7);

  static const Color surface = Color(0xFF26262C);
  static const Color surfaceDim = Color(0xFF1F1F24);
  static const Color surfaceBright = Color(0xFF54545E);

  // Surface Containers (hiérarchie Material 3, toutes opaques)
  static const Color surfaceContainerLowest = Color(0xFF1B1B1F);
  static const Color surfaceContainerLow = Color(0xFF2C2C33);
  static const Color surfaceContainer = Color(0xFF32323A);
  static const Color surfaceContainerHigh = Color(0xFF3B3B44);
  static const Color surfaceContainerHighest = Color(0xFF45454F);
  static const Color surfaceVariant = Color(0xFF32323A);

  // ============ SURFACE / ON SURFACE ============
  static const Color onSurface = Color(0xFFF5F5F7); // blanc Apple
  static const Color onSurfaceVariant = Color(0xFFC7C7CE); // gris clair

  // ============ PRIMARY (Bleu système Apple) ============
  static const Color primary = Color(0xFF8AB9FF); // texte & icônes sur sombre
  static const Color onPrimary = Color(0xFF00295C);
  static const Color primaryContainer = Color(0xFF0A84FF); // remplissage bleu
  static const Color onPrimaryContainer = Color(0xFFEAF2FF);
  static const Color inversePrimary = Color(0xFF0066CC);

  /// Bleu profond — réservé aux **remplissages portant du texte**.
  /// `primaryContainer` (#0A84FF) est trop lumineux : du blanc dessus plafonne
  /// sous le seuil AA de 4,5:1. Cette variante passe le seuil tout en restant
  /// la même couleur perçue.
  static const Color primaryFill = Color(0xFF0A6FDC);

  /// Encre froide — remplace le noir pur pour du texte/des icônes posés sur un
  /// remplissage clair (blanc cassé, bleu clair). Garde le contraste sans le
  /// décalage d'un noir pur.
  static const Color onPrimaryFixed = Color(0xFF002451);
  static const Color primaryFixed = Color(0xFFD6E5FF);
  static const Color primaryFixedDim = Color(0xFF8AB9FF);
  static const Color onPrimaryFixedVariant = Color(0xFF0A5BB5);

  // ============ SECONDARY (Argent / gris clair) ============
  static const Color secondary = Color(0xFFD1D1D6);
  static const Color onSecondary = Color(0xFF303036);
  static const Color secondaryContainer = Color(0xFF44444D);
  static const Color onSecondaryContainer = Color(0xFFE8E8ED);

  // ============ TERTIARY (Cyan glacé) ============
  static const Color tertiary = Color(0xFF7DD3F2);
  static const Color onTertiary = Color(0xFF003544);
  static const Color tertiaryContainer = Color(0xFF1C4D60);
  static const Color onTertiaryContainer = Color(0xFFC8ECFA);

  // ============ ERROR ============
  static const Color error = Color(0xFFFFB4AB);
  static const Color onError = Color(0xFF690005);
  static const Color errorContainer = Color(0xFF93000A);
  static const Color onErrorContainer = Color(0xFFFFDAD6);

  // ============ OUTLINE ============
  static const Color outline = Color(0xFF8E8E93);
  static const Color outlineVariant = Color(0xFF48484E);

  // ============ INVERSE SURFACE ============
  static const Color inverseSurface = Color(0xFFF2F2F7);
  static const Color inverseOnSurface = Color(0xFF2C2C31);
  static const Color surfaceTint = Color(0xFF8AB9FF);

  // ============ TEXT / CONTENT ============
  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFFC7C7CE);
  static const Color textTertiary = Color(0xFF98989F);

  // ============ BLANC À OPACITÉ ============
  // Blanc Apple (#F5F5F7) décliné en opacités pour rester cohérent partout.
  static const Color onSurface06 = Color(0x0FF5F5F7);
  static const Color onSurface12 = Color(0x1FF5F5F7);
  static const Color onSurface24 = Color(0x3DF5F5F7);
  static const Color onSurface38 = Color(0x61F5F5F7);
  static const Color onSurface54 = Color(0x8AF5F5F7);
  static const Color onSurface70 = Color(0xB3F5F5F7);

  // ============ STATUS ============
  static const Color success = Color(0xFF32D74B); // vert système
  static const Color warning = Color(0xFFFFD60A); // jaune système
  static const Color info = Color(0xFF64D2FF); // cyan système

  // ============ CATÉGORIES ============
  static const Color live = Color(0xFFFF453A); // rouge système
  static const Color movies = Color(0xFF0A84FF); // bleu système
  static const Color series = Color(0xFFBF5AF2); // violet système

  // ============ RATING / PREMIUM ============
  static const Color ratingGold = Color(0xFFFFD60A);
  static const Color premiumGold = Color(0xFFE0B84C);

  // ============ SHIMMER (placeholders de chargement) ============
  static const Color shimmer = Color(0xFF32323A);
  static const Color shimmerHighlight = Color(0xFF45454F);

  // ============ BORDERS / FOCUS ============
  static const Color border = outlineVariant;
  static const Color focusColor = primaryContainer;
  static const Color focusBorder = primaryContainer;
  static const Color borderFocused = primaryContainer;

  /// Liseré blanc 10 % — définit l'arête d'une surface "verre" sans la faire
  /// flotter.
  static const Color glassBorderColor = Color(0x1AFFFFFF);

  // ============ SURFACES "GLASS" — OPAQUES ============
  static const Color glassLevel1Bg = Color(0xFF2C2C33);
  static const Color glassLevel1Border = Color(0x1AFFFFFF); // blanc 10 %
  static const Color glassLevel2Bg = Color(0xFF32323A);
  static const Color glassLevel2Border = Color(0x26FFFFFF); // blanc 15 %
  static const Color glassLevel2InnerGlow = Color(0x3D0A84FF); // bleu 24 %

  static const Color glassBackground = glassLevel2Bg;
  static const Color glassBorder = glassLevel2Border;

  // ============ GRADIENTS ============
  /// Bleu système : clair vers profond.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF4DA2FF), Color(0xFF0A6FDC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Fond "verre dépoli" : gris clair en haut, graphite en bas.
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF303038), Color(0xFF1F1F24)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Halo doux depuis le centre de l'écran.
  static const RadialGradient projectorGradient = RadialGradient(
    center: Alignment.center,
    radius: 1.5,
    colors: [Color(0xFF303038), Color(0xFF1F1F24)],
    stops: [0.0, 1.0],
  );

  /// Carte : arête éclairée en haut, matière grise en bas.
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF45454F), Color(0xFF2C2C33)],
    stops: [0.0, 1.0],
  );

  /// Reflet posé sur le haut d'une carte — l'effet "verre".
  static const LinearGradient cardHighlight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x29FFFFFF), Color(0x00FFFFFF)],
    stops: [0.0, 0.5],
  );

  /// Voile d'affiche : lecture du texte par-dessus une jaquette.
  static const LinearGradient posterScrim = LinearGradient(
    colors: [Color(0x001F1F24), Color(0xCC1F1F24), Color(0xFF1F1F24)],
    stops: [0.0, 0.55, 1.0],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Voile latéral pour les héros pleine largeur.
  static const LinearGradient heroScrim = LinearGradient(
    colors: [Color(0xF21F1F24), Color(0x991F1F24), Color(0x001F1F24)],
    stops: [0.0, 0.45, 1.0],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ============ GLOW / OMBRES ============
  static Color glowPrimary(double opacity) =>
      const Color(0xFF0A84FF).withValues(alpha: opacity);
  static Color glowPrimaryDim(double opacity) =>
      const Color(0xFF8AB9FF).withValues(alpha: opacity);

  /// Ombre portée douce — moins dense qu'avant : le fond est plus clair.
  static List<BoxShadow> lift({double intensity = 1.0}) => [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.40 * intensity),
          blurRadius: 28 * intensity,
          spreadRadius: -8,
          offset: Offset(0, 12 * intensity),
        ),
      ];

  /// Halo bleu pour l'élément focalisé (navigation TV / télécommande).
  /// Le nom historique `emberFocus` est conservé pour les sites d'appel.
  static List<BoxShadow> emberFocus({double intensity = 1.0}) => [
        BoxShadow(
          color: const Color(0xFF0A84FF).withValues(alpha: 0.45 * intensity),
          blurRadius: 32 * intensity,
          spreadRadius: -4,
        ),
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.45),
          blurRadius: 24,
          spreadRadius: -10,
          offset: const Offset(0, 14),
        ),
      ];

  // ============ ALIAS DE COMPATIBILITÉ ============
  // Conservés pour ne pas casser les sites d'appel.
  static const Color backgroundSecondary = surfaceContainerLow;
  static const Color surfaceElevated = surfaceContainerHigh;
  static const Color accent = secondary;

  /// Accent bleu Apple portant du texte blanc (contraste AA).
  static const Color appleBlue = primaryFill;

  static const RadialGradient appleTvGradient = projectorGradient;
  static const LinearGradient glossyCardGradient = cardGradient;
  static const LinearGradient glossyHighlight = cardHighlight;
  static const LinearGradient cardGlossyGradient = cardGradient;
  static const LinearGradient cardGlossyHighlight = cardHighlight;

  // ============ COLOR SCHEMES ============
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
        surfaceTint: surfaceTint,
        outline: outline,
        outlineVariant: outlineVariant,
        inverseSurface: inverseSurface,
        inversePrimary: inversePrimary,
        brightness: Brightness.dark,
      );

  /// Thème clair : gris système iOS, même famille neutre.
  static ColorScheme get lightColorScheme => const ColorScheme.light(
        primary: Color(0xFF0066CC),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFD6E5FF),
        onPrimaryContainer: Color(0xFF002451),
        secondary: Color(0xFF54545E),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFE3E3E8),
        onSecondaryContainer: Color(0xFF1B1B1F),
        tertiary: Color(0xFF00658E),
        onTertiary: Colors.white,
        error: Color(0xFFB3261E),
        onError: Colors.white,
        errorContainer: Color(0xFFFFDAD4),
        onErrorContainer: Color(0xFF410E05),
        surface: Color(0xFFF2F2F7),
        onSurface: Color(0xFF1C1C1E),
        onSurfaceVariant: Color(0xFF48484E),
        outline: Color(0xFF8E8E93),
        outlineVariant: Color(0xFFD1D1D6),
        brightness: Brightness.light,
      );
}
