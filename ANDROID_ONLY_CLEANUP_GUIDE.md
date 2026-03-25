# 🔍 Guide Complet: Conversion XtremFlow pour Android Uniquement

## Vue d'ensemble
Ce guide détaille TOUTES les dépendances, configurations, et fichiers de code spécifiques à iOS et Web qui doivent être supprimés ou modifiés pour maintenir SEULEMENT la plateforme Android.

---

## 📊 ANALYSE COMPLÈTE DES DÉPENDANCES

### 1. Dépendances dans pubspec.yaml - DÉTAIL EXHAUSTIF

#### **A. Dépendances Multi-plateforme (GARDER)**
```yaml
# ✅ GARDER - Fonctionnent sur Android
flutter_riverpod: ^2.6.1          # State Management
riverpod_annotation: ^2.6.1       # Code generation
hive: ^2.2.3                      # Local Database
hive_flutter: ^1.1.0              # Flutter Hive integration
dio: ^5.7.0                       # HTTP client
dio_cache_interceptor: ^3.5.1     # HTTP caching
dio_cache_interceptor_hive_store: ^3.2.2  # Cache storage
http: ^1.2.2                      # HTTP client
go_router: ^13.2.5                # Navigation
google_fonts: ^6.2.1              # Typography
cached_network_image: ^3.3.1      # Image caching
crypto: ^3.0.3                    # Encryption
uuid: ^4.4.0                      # UUID generation
intl: ^0.19.0                     # Internationalization
equatable: ^2.0.5                 # Value equality
shared_preferences: ^2.3.2        # Local storage
path_provider: ^2.1.5             # File system paths
```

#### **B. Dépendances Spécifiques au Web (À SUPPRIMER)**
```yaml
# ❌ SUPPRIMER
universal_html: ^2.3.0            # Web HTML compatibility layer
pointer_interceptor: ^0.10.1      # Web pointer handling (optional)
```

**Pourquoi?** 
- `universal_html` est utilisé UNIQUEMENT pour accéder au DOM web
- `pointer_interceptor` est principalement pour web/desktop

#### **C. Dépendances Audio/Vidéo**
```yaml
# ✅ GARDER - Media Kit (disponible sur Android via NDK)
media_kit: ^1.1.11
media_kit_video: ^1.2.5
media_kit_libs_video: ^1.0.5
```

**Note:** `media_kit` fonctionne sur Android, iOS et Web. Les libs vidéo sont compilées natif pour Android.

```yaml
# ✅ GARDER - Video Player (fallback Android native)
video_player: ^2.10.1
```

#### **D. Dépendances Système**
```yaml
# ✅ GARDER - Utiles pour Android
wakelock_plus: ^1.2.8             # Keep screen on during playback
```

#### **E. Dev Dependencies (À ADAPTER)**
```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.3  # ❌ REMPLACER LA CONFIG (voir ci-dessous)
```

---

### 2. Configuration Flutter dans pubspec.yaml

#### **Configuration d'Icônes (À MODIFIER)**
```yaml
# ❌ AVANT (supporte iOS)
flutter_launcher_icons:
  android: true
  ios: false                        # Déjà désactivé ✓
  image_path: "web/icons/Icon-512.png"
  adaptive_icon_background: "#1a1a2e"
  adaptive_icon_foreground: "web/icons/Icon-512.png"
```

```yaml
# ✅ APRÈS (Android uniquement)
flutter_launcher_icons:
  android: true
  image_path: "assets/images/icon.png"  # Utiliser images locales
  adaptive_icon_background: "#1a1a2e"
  adaptive_icon_foreground: "assets/images/icon_foreground.png"
```

#### **Assets à GARDER**
```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/
```

---

## 🗂️ FICHIERS ET DOSSIERS À SUPPRIMER

### 1. **Dossier iOS Complet** ❌
```
/ios/
├── Flutter/                    # ❌ Supprimer
├── Runner/                     # ❌ Supprimer
├── Runner.xcodeproj/          # ❌ Supprimer
├── Runner.xcworkspace/        # ❌ Supprimer
└── RunnerTests/               # ❌ Supprimer
```

**Taille approximative:** ~500MB build artifacts + source

### 2. **Dossier Web Complet** ❌
```
/web/
├── index.html                 # ❌ Supprimer
├── player.html                # ❌ Supprimer
├── manifest.json              # ❌ Supprimer
├── favicon.png                # ❌ Supprimer
└── icons/                     # ❌ Supprimer
    ├── Icon-192.png
    ├── Icon-512.png
    └── ...
```

### 3. **Fichiers de Configuration Web**
```
❌ Supprimer dans la racine:
- web/                         # Dossier entier
```

---

## 📝 FICHIERS DART À MODIFIER

### 1. **Fichiers à Supprimer Complètement**

#### `/lib/core/shims/` - Abstractions Web
```
❌ Supprimer entièrement:
/lib/core/shims/
├── ui_web.dart               # Export conditionnel pour web
├── ui_web_real.dart          # impl web (dart:ui_web)
└── ui_web_fake.dart          # impl fake
```

**Raison:** Ces shims n'ont de sens que pour web

#### `/lib/core/utils/platform_utils_web.dart`
```dart
// ❌ À SUPPRIMER
import 'dart:html' as html;

bool isHttps() {
  return html.window.location.protocol == 'https:';
}

String getWindowOrigin() {
  return html.window.location.origin;
}
```

#### `/lib/core/utils/platform_utils_stub.dart`
```
❌ Supprimer (classe stub pour web)
```

---

### 2. **Fichiers à Modifier - Supprimer imports Web**

#### **A. `/lib/features/iptv/screens/player_screen.dart`**

```dart
// ❌ À SUPPRIMER - Lignes 3-4
import 'package:universal_html/html.dart' as html;
import '../../../core/shims/ui_web.dart' as ui_web;

// ❌ À SUPPRIMER - Ligne 18 (import util)
import '../../../core/utils/platform_utils_web.dart';

// ❌ À SUPPRIMER - Méthode (ligne ~50)
void _setupMessageListener() {
  // Listen for postMessage from player.html iframe
  _messageSubscription = html.window.onMessage.listen((event) {
    try {
      final data = event.data;
      if (data is Map) {
        // ... tout le code ici
      }
    }
  });
}

// ❌ À SUPPRIMER - Code web (ligne ~458)
ui_web.platformViewRegistry.registerViewFactory(
  _viewId,
  (int viewId) => IframeElement()..src = 'player.html?vid=$_viewId',
);
```

**Action:** Supprimer cette classe COMPLÈTEMENT et utiliser `native_player_screen.dart` uniquement
- Elle est pour web seulement
- Android utilise `lib/mobile/features/iptv/screens/native_player_screen.dart`

---

#### **B. `/lib/features/iptv/widgets/settings_tab.dart`**

```dart
// ❌ À SUPPRIMER - Ligne 5
import 'package:universal_html/html.dart' as html; // For reloading

// ❌ À SUPPRIMER - Méthode (chercher "html.location.reload")
void _clearBrowserStorage() {
  // Clear Browser Local Storage (SharedPreferences backend for Web)
  html.window.localStorage.clear();
  html.location.reload();
}
```

**Alternative Android:**
```dart
// ✅ REMPLACER par:
void _clearBrowserStorage() {
  // Clear local storage (SharedPreferences)
  ref.read(settingsProvider.notifier).clearCache();
  // Pas de reload sur Android
}
```

---

#### **C. `/lib/core/database/hive_service.dart`**

```dart
// ❌ À MODIFIER - Supprimer les commentaires et logique web
/// Initialize Hive for Web with encryption
// Remplacer par:
/// Initialize Hive with encryption

// ❌ À SUPPRIMER - Bloc de commentaires:
// Initialize Hive for Web (uses IndexedDB)
// Note: On Web, IndexedDB is already isolated by origin,

// ❌ À SUPPRIMER - Logique web:
// Open boxes WITHOUT encryption on Web
// For web: use session-based key (regenerated each session)
```

**Raison:** Les commentaires spécifiques au web ne s'appliquent pas

---

### 3. **Fichiers à GARDER (mais vérifier)** ✅

#### `/lib/core/api/dns_interceptor.dart`
```dart
import 'dart:io';  // ✅ OK pour Android
// Tout le code est compatible Android
```

#### `/lib/core/api/dns_resolver.dart`
```dart
import 'dart:io';  // ✅ OK pour Android
import 'package:http/http.dart' as http;  // ✅ OK
// Tout le code est compatible Android
```

---

### 4. **Fichiers de Points d'Entrée (main.dart)**

#### **Option A: Garder `main_mobile.dart` comme point d'entrée unique**
```dart
// ✅ GARDER - c'est la version Android optimisée
/lib/main_mobile.dart

// ❌ SUPPRIMER - version web/générique
/lib/main.dart
```

**Raison:** `main_mobile.dart` est spécifiquement optimisé pour Android:
- Initialise `MediaKit` (obligatoire pour vidéo)
- Efface le cache au démarrage
- Utilise `MobilePlaylistScreen` directement
- Pas de routeur web

**Étapes:**
1. Renommer `main_mobile.dart` → `main.dart`
2. Supprimer l'ancien `main.dart`
3. Vérifier les imports dans le nouveau `main.dart`

---

### 5. **Architecture Générale des Dossiers**

#### **À GARDER** ✅
```
/lib/
├── main.dart                          # Anciennement main_mobile.dart
├── mobile/                            # ✅ Dossier entier pour Android
│   ├── features/
│   │   └── iptv/
│   │       ├── screens/
│   │       │   ├── native_player_screen.dart       # ✅ PRINCIPAL
│   │       │   ├── lite_player_screen.dart         # ✅ FALLBACK
│   │       │   ├── mobile_dashboard_screen.dart
│   │       │   ├── mobile_playlist_selection_screen.dart
│   │       │   └── mobile_series_detail_screen.dart
│   │       └── widgets/
│   │           ├── mobile_live_tv_tab.dart
│   │           ├── mobile_movies_tab.dart
│   │           └── ...
│   ├── providers/
│   │   ├── mobile_xtream_providers.dart
│   │   └── mobile_settings_providers.dart
│   ├── theme/
│   │   └── mobile_theme.dart
│   └── widgets/
│       └── tv_focusable.dart
├── core/                              # ✅ Partagé (nettoyer les refs web)
│   ├── api/
│   │   ├── dns_interceptor.dart
│   │   ├── dns_resolver.dart
│   │   ├── api_client.dart
│   │   └── ...
│   ├── database/
│   ├── models/
│   ├── providers/
│   ├── router/
│   ├── services/
│   ├── theme/
│   ├── utils/
│   ├── widgets/
│   └── (ex. shims/removed)
└── features/ → ❌ ANALYSER (voir ci-dessous)
```

#### **À ANALYSER** 📋 `/lib/features/`
```
/lib/features/
├── auth/                              # ?
├── iptv/                              # ? (PROBLÈME)
│   ├── screens/
│   │   └── player_screen.dart        # ❌ WEB-ONLY, SUPPRIMER
│   ├── widgets/
│   │   └── settings_tab.dart         # ⚠️  À NETTOYER (web imports)
│   └── ...
└── admin/ (si nécessaire)
```

**PROBLÈME CRITIQUE:** `/lib/features/` contient du code WEB
- `player_screen.dart` - Utilise `universal_html`, iframes, `player.html`
- `settings_tab.dart` - Accès au localStorage via `html.window`

**Solution:** 
- Supprimer ou remplacer ces fichiers par les équivalents mobiles
- Ou rediriger vers `mobile/features/` équivalent

---

## 🎯 MODIFICATIONS CRITIQUES PAR FICHIER

### 1. **pubspec.yaml - À MODIFIER**

```yaml
# AVANT
dependencies:
  universal_html: ^2.3.0          # ❌ SUPPRIMER
  pointer_interceptor: ^0.10.1    # ❌ SUPPRIMER (optional)
  # ... reste OK

flutter_launcher_icons:
  android: true
  ios: false
  image_path: "web/icons/Icon-512.png"    # ⚠️ CHANGER
  adaptive_icon_foreground: "web/icons/Icon-512.png"  # ⚠️ CHANGER
```

```yaml
# APRÈS
dependencies:
  # ✅ Supprimer universal_html
  # ✅ Supprimer pointer_interceptor
  # Reste identique

flutter_launcher_icons:
  android: true
  image_path: "assets/images/icon.png"
  adaptive_icon_foreground: "assets/images/icon_fg.png"
```

---

### 2. **android/app/build.gradle.kts - À VÉRIFIER** ✅

```kotlin
// ✅ GARDER TOUS CES PARAMÈTRES
android {
    namespace = "com.xtremflow.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.xtremflow.mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
```

**Aucune modification nécessaire**

---

### 3. **android/app/src/main/AndroidManifest.xml - À VÉRIFIER** ✅

```xml
<!-- ✅ GARDER - Permissions essentielles -->
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>

<!-- ✅ GARDER - Configuration Activity -->
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTop"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
    android:hardwareAccelerated="true"
    android:windowSoftInputMode="adjustResize">
```

**Aucune modification nécessaire**

---

## ⚠️ PROBLÈMES ET SOLUTIONS IDENTIFIÉS

### Problème 1: Architecture Duale (Web + Mobile)
**État actuel:**
- `/lib/main.dart` - Version web/générique
- `/lib/main_mobile.dart` - Version Android optimisée
- `/lib/features/iptv/screens/player_screen.dart` - CODE WEB
- `/lib/mobile/features/iptv/screens/native_player_screen.dart` - CODE ANDROID

**Solution:**
```
1. Supprimer /lib/main.dart
2. Renommer main_mobile.dart → main.dart
3. Supprimer /lib/features/iptv/screens/player_screen.dart
4. Vérifier que toutes les routes pointent vers mobile/
5. Supprimer /lib/features/iptv/widgets/settings_tab.dart (web)
```

---

### Problème 2: Dépendances Web Hardcoded
**Fichiers affectés:**
1. `player_screen.dart` → `import 'package:universal_html/html.dart' as html`
2. `settings_tab.dart` → `import 'package:universal_html/html.dart' as html`
3. `hive_service.dart` → Commentaires web spécifiques

**Solution:** Supprimer tous les imports et code web

---

### Problème 3: Shims de Plateforme
**Fichiers:** 
- `/lib/core/shims/ui_web.dart`
- `/lib/core/shims/ui_web_real.dart`
- `/lib/core/shims/ui_web_fake.dart`

**Problème:** Ces shims sont **spécifiquement pour web**

**Solution:** Supprimer complètement
- Aucune autre partie du code ne les utilise (sauf player_screen.dart qui sera supprimé)

---

### Problème 4: Points d'Entrée de Routeur
**Vérifié:**
```dart
// /lib/core/router/app_router.dart
// ✅ Utilise routes mobiles ET web

// Solution:
// - Garder SEULEMENT les routes mobiles
// - Supprimer les imports et références à features/iptv/screens/
```

---

## 🔄 PLAN D'EXÉCUTION DÉTAILLÉ

### **PHASE 1: Suppression de Fichiers (Bas Risque)**
```
1. Supprimer /ios/                              [~500MB]
2. Supprimer /web/                              [~2MB]
3. Supprimer /lib/core/shims/                   [3 fichiers]
4. Supprimer /lib/core/utils/platform_utils_web.dart
5. Supprimer /lib/core/utils/platform_utils_stub.dart
6. Supprimer /lib/features/iptv/screens/player_screen.dart
7. Supprimer ou remplacer /lib/features/iptv/ au complet
```

### **PHASE 2: Modification pubspec.yaml (Bas Risque)**
```
1. Supprimer universal_html: ^2.3.0
2. Supprimer pointer_interceptor: ^0.10.1 (optional)
3. Mettre à jour flutter_launcher_icons config
4. flutter pub get
```

### **PHASE 3: Refactoring du Dart (Moyen Risque)**
```
1. Supprimer imports web de:
   - /lib/features/iptv/widgets/settings_tab.dart
   - /lib/features/iptv/screens/* (si non supprimé)

2. Nettoyer /lib/core/database/hive_service.dart:
   - Commentaires web spécifiques
   - Logique conditionnelle web

3. Renommer main_mobile.dart → main.dart

4. Vérifier /lib/core/router/app_router.dart:
   - Routes uniquement mobiles
   - Pas de références à features/iptv/screens/player_screen
```

### **PHASE 4: Test et Validation (Haut Risque)**
```
1. flutter clean
2. flutter pub get
3. flutter run -d android
4. Tester IPTV playback sur device Android
5. Vérifier persistence données
```

---

## 📋 CHECKLIST COMPLÈTE

### Fichiers iOS à Supprimer (Obligatoire)
- [ ] `/ios/` (répertoire entier)

### Fichiers Web à Supprimer (Obligatoire)
- [ ] `/web/` (répertoire entier)

### Fichiers Dart à Supprimer (Obligatoire)
- [ ] `/lib/core/shims/ui_web.dart`
- [ ] `/lib/core/shims/ui_web_real.dart`
- [ ] `/lib/core/shims/ui_web_fake.dart`
- [ ] `/lib/core/utils/platform_utils_web.dart`
- [ ] `/lib/core/utils/platform_utils_stub.dart`
- [ ] `/lib/features/iptv/screens/player_screen.dart`

### Fichiers Dart à Modifier (Obligatoire)
- [ ] `/lib/features/iptv/widgets/settings_tab.dart` - Supprimer imports web
- [ ] `/lib/core/database/hive_service.dart` - Nettoyer commentaires
- [ ] `/lib/main_mobile.dart` - Renommer en main.dart et supprimer l'ancien
- [ ] `/lib/core/router/app_router.dart` - Vérifier routes

### Modifications Configuration (Obligatoire)
- [ ] `pubspec.yaml`:
  - [ ] Supprimer `universal_html`
  - [ ] Supprimer `pointer_interceptor`
  - [ ] Mettre à jour `flutter_launcher_icons` config
- [ ] `flutter pub get`
- [ ] `flutter clean`

### Fichiers à Vérifier (Validation)
- [ ] Android Manifest - Aucun changement requis
- [ ] Android build.gradle - Aucun changement requis
- [ ] `/lib/core/api/` - Contient code compatible
- [ ] `/lib/mobile/` - Dossier entier OK

---

## 💾 DÉPENDANCES FINALES (Android Only)

### Production
```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # State Management
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1
  
  # Database
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  
  # HTTP
  dio: ^5.7.0
  dio_cache_interceptor: ^3.5.1
  dio_cache_interceptor_hive_store: ^3.2.2
  http: ^1.2.2
  
  # Routing
  go_router: ^13.2.5
  
  # Video (FFmpeg-based)
  media_kit: ^1.1.11
  media_kit_video: ^1.2.5
  media_kit_libs_video: ^1.0.5
  
  # UI
  google_fonts: ^6.2.1
  cached_network_image: ^3.3.1
  
  # Security
  crypto: ^3.0.3
  uuid: ^4.4.0
  
  # Utilities
  intl: ^0.19.0
  equatable: ^2.0.5
  shared_preferences: ^2.3.2
  path_provider: ^2.1.5
  video_player: ^2.10.1
  wakelock_plus: ^1.2.8
```

### Dev Dependencies
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.2
  flutter_launcher_icons: ^0.14.3
  
  # Code Generation
  build_runner: ^2.4.13
  riverpod_generator: ^2.4.0
  hive_generator: ^2.0.1
```

**Total à supprimer:** 2 dépendances (`universal_html`, `pointer_interceptor`)

---

## 🎉 RÉSUMÉ FINAL

| Catégorie | Élément | Action | Taille | Priorité |
|-----------|---------|--------|--------|----------|
| **Dossiers Entiers** | `/ios/` | Supprimer | ~500MB | 🔴 CRITIQUE |
| **Dossiers Entiers** | `/web/` | Supprimer | ~2MB | 🔴 CRITIQUE |
| **Shims** | `ui_web*` | Supprimer | 3 fichiers | 🔴 CRITIQUE |
| **Code** | `player_screen.dart` | Supprimer | ~500 lignes | 🔴 CRITIQUE |
| **Code** | `settings_tab.dart` (web) | Nettoyer imports | ~850 lignes | 🟡 IMPORTANT |
| **Code** | `main.dart` | Supprimer (non-mobile) | ~30 lignes | 🔴 CRITIQUE |
| **Config** | `pubspec.yaml` | 2 dépendances | ~2 lignes | 🔴 CRITIQUE |
| **Config** | `flutter_launcher_icons` | Adapter | ~3 lignes | 🟡 IMPORTANT |

**Temps estimé:** 30-45 minutes (test inclus)
**Risque:** Bas-Moyen (dépendances déjà séparables)
**Économies:** ~500MB disque, dépendances de build réduites

---

## 📚 Fichiers Clés à Référencer Après Cleanup

✅ **Nouveau point d'entrée:**
- `/lib/main.dart` (anciennement main_mobile.dart)

✅ **UI Mobile (garder):**
- `/lib/mobile/features/iptv/screens/native_player_screen.dart`
- `/lib/mobile/features/iptv/screens/lite_player_screen.dart`

✅ **Core partagé (nettoyer):**
- `/lib/core/api/` (compatible)
- `/lib/core/database/hive_service.dart` (nettoyer commentaires)
- `/lib/core/router/app_router.dart` (vérifier routes)

❌ **À COMPLÈTEMENT OUBLIER:**
- Tout sous `/ios/`
- Tout sous `/web/`
- Tout au-dessus concernant `universal_html`, `dart:html`, ou player.html
