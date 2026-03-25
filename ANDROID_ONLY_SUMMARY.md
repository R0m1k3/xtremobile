# ⚡ RÉSUMÉ EXÉCUTIF - Suppression iOS & Web

## 🎯 À Faire IMMÉDIATEMENT

### 1️⃣ Supprimer les Répertoires (Obligatoire)
```bash
# iOS - La plus grande suppression
rm -rf ios/                    # ~500MB

# Web
rm -rf web/                    # ~2MB
```

### 2️⃣ Supprimer les Fichiers Dart (Obligatoire)
```bash
# Shims web
rm lib/core/shims/ui_web.dart
rm lib/core/shims/ui_web_real.dart
rm lib/core/shims/ui_web_fake.dart

# Platform utils web
rm lib/core/utils/platform_utils_web.dart
rm lib/core/utils/platform_utils_stub.dart

# Écrans web-only
rm lib/features/iptv/screens/player_screen.dart
```

### 3️⃣ Éditer pubspec.yaml (Obligatoire)
```yaml
# ❌ Supprimer ces 2 lignes (chercher et supprimer):
  universal_html: ^2.3.0
  pointer_interceptor: ^0.10.1

# ⚠️ MODIFIER flutter_launcher_icons config:
# AVANT:
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "web/icons/Icon-512.png"
  adaptive_icon_foreground: "web/icons/Icon-512.png"

# APRÈS:
flutter_launcher_icons:
  android: true
  image_path: "assets/images/icon.png"
  adaptive_icon_foreground: "assets/images/icon_fg.png"
```

```bash
flutter pub get
flutter clean
```

### 4️⃣ Renommer le Point d'Entrée
```bash
# Remplacer main.dart par la version mobile
rm lib/main.dart
mv lib/main_mobile.dart lib/main.dart
```

### 5️⃣ Nettoyer les Imports Web
#### Fichier: `lib/features/iptv/widgets/settings_tab.dart`
```dart
# ❌ SUPPRIMER cette ligne (ligne 5):
import 'package:universal_html/html.dart' as html;

# ❌ SUPPRIMER la méthode _clearBrowserStorage() complètement
# ou la remplacer avec:
void _clearBrowserStorage() {
  ref.read(settingsProvider.notifier).clearCache();
}
```

#### Fichier: `lib/core/database/hive_service.dart`
```dart
# ❌ SUPPRIMER tous les commentaires mentionnant "Web"
# Chercher et supprimer:
- "Initialize Hive for Web"
- "uses IndexedDB"
- "On Web, IndexedDB"
- "For web: use session-based key"
```

---

## 🔍 Fichiers à VÉRIFIER (Ne pas toucher - Bien)

- ✅ `/lib/mobile/` - Entièrement Android, garder
- ✅ `/lib/core/api/` - Compatible Android, garder
- ✅ `/android/` - Configuration Android, garder
- ✅ `pubspec.yaml` - Reste OK après suppression 2 dépendances

---

## ⚠️ ATTENTION - Édits Critiques

### `lib/core/router/app_router.dart` - VÉRIFICATION REQUISE

Après les suppressions, vérifier que le fichier n'a PLUS de références à:
```dart
// À NE PAS AVOIR:
'lib/features/iptv/screens/player_screen.dart'
'lib/features/auth/screens/login_screen.dart'  (si web-only)
'lib/features/iptv/screens/playlist_selection_screen.dart'  (si web-only)
```

**Remplacer par:**
```dart
'lib/mobile/features/iptv/screens/native_player_screen.dart'
'lib/mobile/features/auth/screens/mobile_login_screen.dart'
'lib/mobile/features/iptv/screens/mobile_playlist_selection_screen.dart'
```

---

## 📊 Impacts

| Aspect | Avant | Après | Gain |
|--------|-------|-------|------|
| **Dépendances** | universal_html, pointer_interceptor | — | Réduction |
| **Taille disque** | Ios + web configs | Android only | ~500MB |
| **Complexité build** | Multi-plateforme | Mono-plateforme | Simplifié |
| **Dossiers sources** | ios/, web/, lib/features/, lib/mobile/ | lib/mobile/, lib/core/, lib/features/admin/ | Clarifié |

---

## ✅ Validation Finale

Après tout cleanup:
```bash
flutter clean
flutter pub get
flutter run -d android          # Sur device Android
```

**À Tester:**
- [ ] App démarre
- [ ] Login fonctionne
- [ ] Playlist se charge
- [ ] Vidéo joue (native player)
- [ ] Paramètres fonctionnent
- [ ] Cache se vide au démarrage

---

## 💡 Notes Importantes

1. **Ne pas toucher `media_kit`** - Fonctionne sur Android (et iOS/web, mais on les supprime)
2. **Ne pas toucher `video_player`** - Fallback Android natif
3. **`wakelock_plus`** - Garde l'écran allumé, important pour IPTV
4. **`shared_preferences`** - Stock les préférences, fonctionne sur Android
5. **`hive`** - Base de données locale, compatible Android

---

## 🚀 Ordre d'Exécution Recommandé

1. ✅ Supprimer les répertoires ios/ et web/
2. ✅ Supprimer pubspec.yaml dépendances (2 lignes)
3. ✅ `flutter pub get`
4. ✅ Supprimer fichiers Dart (shims, utils web)
5. ✅ Nettoyer imports web (settings_tab, hive_service)
6. ✅ Renommer main.dart
7. ✅ Vérifier router
8. ✅ `flutter clean`
9. ✅ `flutter run -d android`
10. ✅ Tests

**Temps total:** 30-45 minutes
