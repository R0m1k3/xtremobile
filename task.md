# Task: Corrections Fire Stick & UI - TERMINÉ

## Bugs corrigés

### Session 1 (07h45)

1. ✅ **Mise en veille pendant lecture** - Ajout de `wakelock_plus` dans les deux players
2. ✅ **Settings surbrillance invisible** - Toutes les box utilisent TVFocusable avec bordure blanche
3. ✅ **Player Lite bouton pause** - Descendu et rendu semi-transparent

### Session 2 (18h15)

4. ✅ **Retour depuis player TV** - Le bouton retour ramène maintenant à la liste des chaînes (pas aux catégories)

## Fichiers modifiés

- `pubspec.yaml` - Ajout de `wakelock_plus`
- `native_player_screen.dart` - WakeLock activé/désactivé
- `lite_player_screen.dart` - WakeLock + nouveau design boutons + seek réduit
- `mobile_settings_tab.dart` - TVFocusable sur toutes les options
- `mobile_live_tv_tab.dart` - Correction navigation retour depuis player

## APK généré

`build\app\outputs\flutter-apk\app-release.apk` (92.3MB)
