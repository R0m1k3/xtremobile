# 📝 LISTE DÉTAILLÉE DES CHANGEMENTS AVEC RÉFÉRENCES

## 1. DOSSIERS À SUPPRIMER COMPLÈTEMENT

```
❌ /ios/
   └─ ~500MB de contenu iOS-spécifique
   ├──Runner/                  (Source iOS)
   ├── Runner.xcodeproj/       (Configuration Xcode)
   ├── Runner.xcworkspace/     (Workspace Xcode)
   ├── Flutter/                (Configuration Flutter iOS)
   └── RunnerTests/            (Tests iOS)

❌ /web/
   └─ ~2MB de contenu web-spécifique
   ├── index.html              (Page web principale)
   ├── player.html             (Lecteur vidéo web avec HLS.js/mpegts.js)
   ├── manifest.json           (Web app manifest)
   ├── favicon.png
   └── icons/                  (Icons web)
```

---

## 2. FICHIERS DART À SUPPRIMER COMPLÈTEMENT

### 2.1 Directory: `/lib/core/shims/` (3 fichiers)
```
❌ /lib/core/shims/ui_web.dart
   └─ Conteneur conditionnel: 
      export 'ui_web_fake.dart' if (dart.library.html) 'ui_web_real.dart';

❌ /lib/core/shims/ui_web_real.dart
   └─ Export dart:ui_web (web platform uniquement)
   └─ ~5 lignes

❌ /lib/core/shims/ui_web_fake.dart
   └─ Mock class PlatformViewRegistry pour non-web
   └─ ~12 lignes
```

### 2.2 Platform Utilities
```
❌ /lib/core/utils/platform_utils_web.dart
   └─ Contient: isHttps(), getWindowOrigin() utilisant dart:html
   └─ ~15 lignes

❌ /lib/core/utils/platform_utils_stub.dart
   └─ Stub pour web platform
   └─ ~15 lignes
```

### 2.3 Écrans Web-Only
```
❌ /lib/features/iptv/screens/player_screen.dart
   └─ Lecteur vidéo WEB UNIQUEMENT
   └─ Imports web:
      - 'package:universal_html/html.dart' (ligne 3)
      - '../../../core/shims/ui_web.dart' (ligne 4)
      - 'dart:ui_web' (indirecte)
   └─ Utilise 'player.html' iframe
   └─ ~500+ lignes
```

---

## 3. ÉDITIONS SPÉCIFIQUES (Fichiers à modifier)

### 3.1 `/lib/features/iptv/widgets/settings_tab.dart`

**SUPPRESSION (chercher et supprimer):**
```dart
# Ligne ~5
import 'package:universal_html/html.dart' as html; // For reloading

# Méthode complète (chercher "_clearBrowserStorage" ou "html.location.reload")
# Supprimer le bloc complet:
void _clearBrowserStorage() {
  try {
    // Clear Browser Local Storage (SharedPreferences backend for Web)
    html.window.localStorage.clear();
    html.location.reload();
  } catch (e) {
    debugPrint('Failed to clear storage: $e');
  }
}
```

**REMPLACER PAR:**
```dart
void _clearBrowserStorage() {
  // Clear shared preferences (Android local storage equivalent)
  ref.read(settingsProvider.notifier).clearSettings();
  // Note: App ne recharge pas, utilisateur peut continuer
}
```

---

### 3.2 `/lib/core/database/hive_service.dart`

**SUPPRESSION (commentaires uniquement):**
```dart
# Ligne ~15 - changer:
/// Initialize Hive for Web with encryption
# À:
/// Initialize Hive with encryption

# Lignes ~19-20 - supprimer les commentaires:
// Initialize Hive for Web (uses IndexedDB)
// Web - specific, indexed DB comment

# Lignes ~31-45 - supprimer les commentaires web:
// Open boxes WITHOUT encryption on Web
// Note: On Web, IndexedDB is already isolated by origin,
// so additional encryption isn't critical but still good practice

// For web: use session-based key (regenerated each session)
// On natives: use properly managed encryption key
```

**GARDER:**
```dart
  /// Initialize Hive with encryption
  static Future<void> init() async {
    if (_initialized) return;
    
    // Initialize Hive
    await Hive.initFlutter();
    
    // Register adapters...
    // Open boxes...
```

---

### 3.3 `/lib/core/api/api_client.dart`

**VÉRIFICATION (chercher ligne ~30):**
```dart
# Ces lignes peuvent avoir des refs web:
// For now, returning empty string implies relative path (works for web).
```

**REMPLACER PAR:**
```dart
// Using relative path for API base URL
```

---

### 3.4 `/lib/core/router/app_router.dart`

**VÉRIFICATION NÉCESSAIRE - Ne pas supposer, chercher:**
```dart
# Chercher ces imports - S'ILS EXISTENT, SUPPRIMER:
import '../../features/auth/screens/login_screen.dart';
import '../../features/iptv/screens/playlist_selection_screen.dart';
import '../../features/iptv/screens/dashboard_screen.dart';

# Remplacer par:
import '../../mobile/features/auth/screens/mobile_login_screen.dart';
import '../../mobile/features/iptv/screens/mobile_playlist_selection_screen.dart';
import '../../mobile/features/iptv/screens/mobile_dashboard_screen.dart';
```

---

### 3.5 `/lib/main.dart` et `/lib/main_mobile.dart`

**ACTION:**
1. Supprimer complètement: `/lib/main.dart`
2. Renommer: `/lib/main_mobile.dart` → `/lib/main.dart`

**Vérifier le nouveau main.dart:**
```dart
# GARDER - Ceci est correct pour Android:
import 'package:media_kit/media_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await HiveService.init();
  // ...
  runApp(const ProviderScope(child: MobileApp()));
}

class MobileApp extends ConsumerWidget {
  // ...
  home: const MobilePlaylistScreen(),  # ✅ Direct au playlist, pas auth
}
```

---

### 3.6 `pubspec.yaml`

**SUPPRESSION (2 dépendances):**
```yaml
# Chercher et supprimer ces DEUX lignes:
  universal_html: ^2.3.0
  pointer_interceptor: ^0.10.1
```

**MODIFICATION (flutter_launcher_icons section):**
```yaml
# ❌ AVANT:
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "web/icons/Icon-512.png"
  adaptive_icon_background: "#1a1a2e"
  adaptive_icon_foreground: "web/icons/Icon-512.png"

# ✅ APRÈS:
flutter_launcher_icons:
  android: true
  image_path: "assets/images/icon.png"
  adaptive_icon_background: "#1a1a2e"
  adaptive_icon_foreground: "assets/images/icon_fg.png"
```

**IMPORTANT:** Assurez-vous que `assets/images/icon.png` et `assets/images/icon_fg.png` existent!

---

## 4. FICHIERS À VÉRIFIER (Mais probablement OK)

### 4.1 `/lib/core/api/dns_interceptor.dart`
```dart
# ✅ GARDER - Imports sont OK pour Android:
import 'dart:io';
import 'package:dio/dio.dart';

# Tout le code dédié Android (socket DNS fallback)
```

### 4.2 `/lib/core/api/dns_resolver.dart`
```dart
# ✅ GARDER - Imports sont OK pour Android:
import 'dart:io';
import 'dart:convert';

# Tout le code dédié Android (HttpClient pour DoH)
```

### 4.3 `/lib/mobile/features/iptv/widgets/mobile_live_tv_tab.dart`
```dart
# ✅ GARDER - Imports:
import 'dart:io';
import '../screens/native_player_screen.dart';

# Code Android-spécifique pour TV remote focus
```

### 4.4 `/lib/mobile/features/iptv/screens/native_player_screen.dart`
```dart
# ✅ GARDER ENTIÈREMENT:
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

# Lecteur vidéo Android natif avec FFmpeg
# ~500+ lignes, code critique
```

### 4.5 `/android/app/src/main/AndroidManifest.xml`
```xml
# ✅ GARDER ENTIÈREMENT - Aucun changement requis:
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>

<application android:usesCleartextTraffic="true">
  <!-- IPTV often uses non-HTTPS streams -->
```

### 4.6 `/android/app/build.gradle.kts`
```kotlin
# ✅ GARDER ENTIÈREMENT - Aucun changement requis:
android {
    namespace = "com.xtremflow.mobile"
    compileSdk = flutter.compileSdkVersion
    
    defaultConfig {
        applicationId = "com.xtremflow.mobile"
        // ...
    }
}
```

---

## 5. VÉRIFICATION POST-SUPPRESSION

Après avoir supprimé ios/, web/ et fichiers, chercher ces patterns:

```bash
# Chercher les imports web résiduels:
grep -r "universal_html" lib/              # Devrait être 0 ligne
grep -r "dart:html" lib/                   # Devrait être 0 ligne
grep -r "platform_utils_web" lib/          # Devrait être 0 ligne
grep -r "ui_web" lib/                      # Devrait être 0 ligne
grep -r "player\.html" lib/                # Devrait être 0 ligne
grep -r "localStorage" lib/                # Devrait être 0 ligne
grep -r "html\.window" lib/                # Devrait être 0 ligne
grep -r "html\.location" lib/              # Devrait être 0 ligne
```

**Résultat attendu:** Aucune ligne retournée

---

## 6. IMPORTS QUI NE SONT PAS À SUPPRIMER

```dart
# ✅ GARDER - Ceux-ci sont OK:
import 'dart:io';                          # Package système, Android OK
import 'dart:async';                       # Package système, OK partout
import 'dart:convert';                     # Package système, OK partout
import 'dart:ui' as ui;                    # Flutter core, OK Android
import 'dart:math';                        # Package système, OK
```

```dart
# ❌ SUPPRIMER - Seulement ceux-ci:
import 'dart:html';                        # Web uniquement
import 'package:universal_html/html.dart'; # Web compatibility
```

---

## 7. STRUCTURE FINALE DE RÉPERTOIRES

### Avant
```
xtremobile/
├── ios/                    (SUPPRIMÉ)
├── android/               (GARDÉ)
├── web/                   (SUPPRIMÉ)
├── lib/
│   ├── main.dart         (SUPPRIMÉ)
│   ├── main_mobile.dart  (RENOMMÉ → main.dart)
│   ├── mobile/           (GARDÉ)
│   ├── features/         (PARTIELLEMENT - garder admin/, nettoyer iptv/)
│   ├── core/
│   │   ├── shims/        (SUPPRIMÉ)
│   │   └── utils/        (Supprimer platform_utils_web*)
│   └── ...
└── pubspec.yaml          (MODIFIÉ - 2 dépendances supprimées)
```

### Après
```
xtremobile/
├── android/               (GARDÉ - SEULE PLATEFORME)
├── lib/
│   ├── main.dart         (Anciennement main_mobile.dart)
│   ├── mobile/           (Architecture principale)
│   ├── core/             (Utilitaires partagés)
│   ├── features/         (admin/, auth/, iptv/ au complet)
│   └── ...
└── pubspec.yaml          (Nettoyé)
```

---

## 8. VALIDATION FINALE

### Avant `flutter run`:
```bash
# 1. Nettoyage
flutter clean

# 2. Reinstall des dépendances
flutter pub get

# 3. Check des imports générés
flutter pub get
flutter pub run build_runner build  # Si nécessaire

# 4. Analyse statique
flutter analyze
```

### Pendant `flutter run`:
```bash
# 5. Lancer sur device/émulateur Android
flutter run -d android

# Ou si plusieurs devices:
flutter devices
flutter run -d <device-id>
```

### Tests Fonctionnels:
```
[ ] App démarre sans erreurs
[ ] Écran de login visible
[ ] Connexion fonctionne
[ ] Playlist se charge
[ ] Vidéo joue via native_player_screen
[ ] Contrôles de vidéo fonctionnent
[ ] Cache persiste entre redémarrages
[ ] Paramètres sauvegardent
```

---

## 9. FICHIERS À SAUVEGARDER AVANT SUPPRESSION

Si vous voulez garder un backup:
```bash
# Sauvegarde du code iOS pour référence future
mkdir backup_ios
cp -r ios backup_ios/ios_$(date +%Y%m%d_%H%M%S)

# Sauvegarde du code web
mkdir backup_web
cp -r web backup_web/web_$(date +%Y%m%d_%H%M%S)

# Sauvegarde de player_screen.dart
cp lib/features/iptv/screens/player_screen.dart backup_web/player_screen_$(date +%Y%m%d_%H%M%S).dart
```

---

## 10. ROLLBACK EN CAS DE PROBLÈME

Si quelque chose se casse après suppression:
```bash
# 1. Restaurer pubspec.yaml depuis git (si dans version control)
git checkout pubspec.yaml

# 2. Ou restaurer manuellement les 2 dépendances:
flutter pub add universal_html
flutter pub add pointer_interceptor

# 3. Restaurer le build:
flutter clean
flutter pub get
flutter run
```

---

## ✅ RÉCAPITULATIF COMPLET

| Phase | Action | Durée | Risque |
|-------|--------|-------|--------|
| 1 | `rm -rf ios/` `rm -rf web/` | 30s | Aucun - irreversibl mais intentionnel |
| 2 | Supprimer fichiers Dart shims | 1min | Aucun - pas utilisés |
| 3 | `pubspec.yaml` edits | 2min | Bas - 2 lignes simples |
| 4 | Main.dart rename | 30s | Aucun - simple rename |
| 5 | Nettoyer imports web | 5min | Moyen - modification code |
| 6 | Vérifier router | 2min | Haut - logique critique |
| 7 | `flutter clean` + `pub get` | 3min | Aucun - opération safe |
| 8 | Test sur device | 5-10min | Haut - validation runtime |

**Total:** 20-30 minutes

