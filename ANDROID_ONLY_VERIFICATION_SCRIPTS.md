# 🧹 SCRIPTS DE VALIDATION POST-CLEANUP

## 1. Script de Vérification Complète

```bash
#!/bin/bash
# File: verify_android_only.sh
# Purpose: Verify that all iOS and web dependencies are removed

echo "=========================================="
echo "XtremFlow - Android-Only Verification"
echo "=========================================="
echo ""

# Initialize error count
ERRORS=0

# ============================================
# 1. Vérifier que les répertoires iOS/web sont supprimés
# ============================================
echo "✓ Checking for removed directories..."

if [ -d "ios" ]; then
    echo "  ❌ ERROR: ios/ directory still exists"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✅ ios/ removed"
fi

if [ -d "web" ]; then
    echo "  ❌ ERROR: web/ directory still exists"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✅ web/ removed"
fi

# ============================================
# 2. Vérifier les imports web résiduels
# ============================================
echo ""
echo "✓ Checking for residual web imports..."

# Vérifier universal_html
if grep -r "universal_html" lib/ 2>/dev/null | grep -v "^Binary"; then
    echo "  ❌ ERROR: Found universal_html imports in lib/"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✅ No universal_html imports"
fi

# Vérifier dart:html
if grep -r "import 'dart:html'" lib/ 2>/dev/null; then
    echo "  ❌ ERROR: Found dart:html imports in lib/"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✅ No dart:html imports"
fi

# Vérifier les commentaires web suspects
if grep -r "html\.window\|html\.location\|html\.localStorage" lib/ 2>/dev/null; then
    echo "  ❌ ERROR: Found web-specific HTML access in lib/"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✅ No web-specific HTML access"
fi

# ============================================
# 3. Vérifier les shims supprimés
# ============================================
echo ""
echo "✓ Checking for removed shims..."

if [ -d "lib/core/shims" ]; then
    echo "  ❌ ERROR: lib/core/shims/ directory still exists"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✅ lib/core/shims/ removed"
fi

# ============================================
# 4. Vérifier les fichiers spécifiques supprimés
# ============================================
echo ""
echo "✓ Checking for removed files..."

FILES_TO_REMOVE=(
    "lib/features/iptv/screens/player_screen.dart"
    "lib/core/utils/platform_utils_web.dart"
    "lib/core/utils/platform_utils_stub.dart"
)

for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
        echo "  ❌ ERROR: $file still exists"
        ERRORS=$((ERRORS + 1))
    else
        echo "  ✅ $file removed"
    fi
done

# ============================================
# 5. Vérifier pubspec.yaml
# ============================================
echo ""
echo "✓ Checking pubspec.yaml..."

if grep "universal_html:" pubspec.yaml; then
    echo "  ❌ ERROR: universal_html still in pubspec.yaml"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✅ universal_html removed from pubspec.yaml"
fi

if grep "pointer_interceptor:" pubspec.yaml; then
    echo "  ⚠️  WARNING: pointer_interceptor still in pubspec.yaml (optional)"
else
    echo "  ✅ pointer_interceptor removed from pubspec.yaml"
fi

# ============================================
# 6. Vérifier le point d'entrée
# ============================================
echo ""
echo "✓ Checking main.dart..."

if [ -f "lib/main_mobile.dart" ]; then
    echo "  ❌ ERROR: main_mobile.dart still exists (should be renamed to main.dart)"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✅ main_mobile.dart renamed/moved"
fi

if [ -f "lib/main.dart" ]; then
    # Vérifier que c'est la version mobile
    if grep -q "MediaKit.ensureInitialized()" lib/main.dart; then
        echo "  ✅ main.dart is mobile version"
    else
        echo "  ⚠️  WARNING: main.dart might not be the mobile version"
    fi
else
    echo "  ❌ ERROR: lib/main.dart doesn't exist"
    ERRORS=$((ERRORS + 1))
fi

# ============================================
# 7. Vérifier les dépendances Android
# ============================================
echo ""
echo "✓ Checking Android dependencies..."

REQUIRED_DEPS=(
    "flutter_riverpod"
    "hive_flutter"
    "dio"
    "go_router"
    "media_kit"
    "video_player"
)

for dep in "${REQUIRED_DEPS[@]}"; do
    if grep "$dep:" pubspec.yaml > /dev/null; then
        echo "  ✅ $dep present"
    else
        echo "  ❌ ERROR: $dep missing from dependencies"
        ERRORS=$((ERRORS + 1))
    fi
done

# ============================================
# 8. Vérifier les imports critiques
# ============================================
echo ""
echo "✓ Checking critical files exist..."

CRITICAL_FILES=(
    "lib/mobile/features/iptv/screens/native_player_screen.dart"
    "lib/mobile/features/iptv/screens/lite_player_screen.dart"
    "lib/core/api/dns_interceptor.dart"
    "lib/core/database/hive_service.dart"
    "android/app/src/main/AndroidManifest.xml"
)

for file in "${CRITICAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file exists"
    else
        echo "  ❌ ERROR: $file missing"
        ERRORS=$((ERRORS + 1))
    fi
done

# ============================================
# 9. Vérifier le dossier Android
# ============================================
echo ""
echo "✓ Checking Android structure..."

if [ -d "android/app" ]; then
    echo "  ✅ android/app/ exists"
else
    echo "  ❌ ERROR: android/app/ missing"
    ERRORS=$((ERRORS + 1))
fi

# ============================================
# Résumé Final
# ============================================
echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo "✅ All checks passed! Ready to run Flutter"
    echo "=========================================="
    exit 0
else
    echo "❌ Found $ERRORS error(s)"
    echo "=========================================="
    exit 1
fi
```

---

## 2. Utilisation du Script

```bash
# Hacer executable
chmod +x verify_android_only.sh

# Exécuter depuis la racine du projet
./verify_android_only.sh

# Exemple de sortie réussie:
# ✅ All checks passed! Ready to run Flutter
```

---

## 3. Commandes Manuelles de Vérification

### Vérifier les répertoires supprimés:
```bash
ls -la ios/ web/ 2>&1
# Devrait retourner: "No such file or directory" pour les deux
```

### Vérifier les imports web résiduels:
```bash
# Tous ces commands devraient retourner 0 résultats
grep -r "universal_html" lib/
grep -r "import 'dart:html'" lib/
grep -r "html\.window" lib/
grep -r "html\.localStorage" lib/
grep -r "player\.html" lib/
```

### Vérifier pubspec.yaml:
```bash
grep -E "universal_html|pointer_interceptor" pubspec.yaml
# Devrait être vide ou ne retourner aucune ligne
```

### Vérifier les fichiers supprimés:
```bash
ls -la lib/core/shims/
ls -la lib/features/iptv/screens/player_screen.dart
ls -la lib/core/utils/platform_utils_web.dart
# Tous doivent retourner "No such file or directory"
```

### Vérifier le point d'entrée:
```bash
# Doit exister
ls -la lib/main.dart

# Ne doit pas exister
ls -la lib/main_mobile.dart 2>&1 | grep "No such"

# Vérifier que c'est la version mobile
grep -c "MediaKit.ensureInitialized()" lib/main.dart
# Devrait retourner 1
```

---

## 4. One-Liner pour Vérification Rapide

```bash
# Vérifie que tous les répertoires/fichiers problématiques sont supprimés
[ ! -d ios ] && [ ! -d web ] && [ ! -d lib/core/shims ] && \
  [ ! -f lib/features/iptv/screens/player_screen.dart ] && \
  [ ! -f lib/core/utils/platform_utils_web.dart ] && \
  grep -q "^  flutter" pubspec.yaml && \
  echo "✅ Basic cleanup verified" || echo "❌ Cleanup incomplete"
```

---

## 5. Vérification des Dépendances

```bash
# Lister toutes les dépendances flutter
flutter pub deps

# Filtrer pour web-only:
flutter pub deps | grep -i "universal\|pointer\|html"

# Résultat attendu: Aucune ligne
```

---

## 6. Vérification de Configuration

```bash
# Vérifier que pubspec.yaml est válida
flutter pub get --dry-run

# Ou simplement:
flutter pub get

# Devrait afficher:
# Running "flutter pub get" in xtremobile...
# Got dependencies!
```

---

## 7. Checklist Complète Post-Cleanup

```
[ ] Répertoires supprimés:
    [ ] ios/ (vérifier avec: ls -la ios 2>&1)
    [ ] web/ (vérifier avec: ls -la web 2>&1)

[ ] Fichiers Dart supprimés:
    [ ] lib/core/shims/ui_web.dart
    [ ] lib/core/shims/ui_web_real.dart
    [ ] lib/core/shims/ui_web_fake.dart
    [ ] lib/core/utils/platform_utils_web.dart
    [ ] lib/core/utils/platform_utils_stub.dart
    [ ] lib/features/iptv/screens/player_screen.dart
    [ ] lib/main.dart (ancien)
    [ ] lib/main_mobile.dart (renommé en main.dart)

[ ] Configuration modifiée:
    [ ] pubspec.yaml - universal_html supprimé
    [ ] pubspec.yaml - pointer_interceptor supprimé
    [ ] pubspec.yaml - flutter_launcher_icons config changée
    [ ] lib/features/iptv/widgets/settings_tab.dart - imports web supprimés
    [ ] lib/core/database/hive_service.dart - commentaires web nettoyés

[ ] Vérifications:
    [ ] flutter pub get exécuté
    [ ] flutter analyze - 0 erreurs
    [ ] grep -r "universal_html" lib/ → 0 résultats
    [ ] grep -r "dart:html" lib/ → 0 résultats
    [ ] grep -r "html.window" lib/ → 0 résultats
    [ ] ls -la lib/main_mobile.dart → Ne devrait pas exister

[ ] Tests:
    [ ] flutter run -d android sur device/émulateur → Démarre
    [ ] App fonctionne sans erreurs
    [ ] Connexion + Playlist + Vidéo fonctionnent
    [ ] Cache persiste
```

---

## 8. Dépannage des Erreurs Courantes

### Erreur: "universal_html" not found
```
Si flutter pub get échoue après suppression:
1. flutter clean
2. rm -rf pubspec.lock
3. flutter pub get

Si ça persiste:
4. Vérifier que universal_html est BIEN supprimé de pubspec.yaml
5. Regarder si y a des imports cachés: grep -r "universal" lib/
```

### Erreur: "can't find Player Screen"
```
Si compilation échoue à cause du lecteur:
1. Vérifier que lib/mobile/features/iptv/screens/native_player_screen.dart existe
2. Vérifier les routes dans lib/core/router/app_router.dart
3. S'assurer que les routes pointent vers mobile/ et pas features/iptv/
```

### Erreur: "main_mobile.dart not found"
```
Si le point d'entrée ne se trouve pas:
1. Vérifier que main.dart existe: ls -la lib/main.dart
2. Vérifier qu'il contient "MediaKit.ensureInitialized()"
3. Vérifier que l'ancien main.dart est supprimé
```

### Erreur: MediaKit initialization fails
```
Si MediaKit.ensureInitialized() échoue:
1. C'est normal en testing - nécessite un device réel
2. Sur émulateur: utiliser FFmpeg avec software decoding
3. Voir lib/mobile/features/iptv/screens/native_player_screen.dart
```

---

## 9. Rapport Final à Générer

```bash
#!/bin/bash
# Générer un rapport de cleanup

echo "========== XtremFlow Android-Only Cleanup Report ==========" > cleanup_report.txt
echo "Generated: $(date)" >> cleanup_report.txt
echo "" >> cleanup_report.txt

echo "1. DIRECTORIES:" >> cleanup_report.txt
echo "   ios/ exists: $([ -d ios ] && echo NO || echo YES)" >> cleanup_report.txt
echo "   web/ exists: $([ -d web ] && echo NO || echo YES)" >> cleanup_report.txt
echo "   lib/core/shims/ exists: $([ -d lib/core/shims ] && echo NO || echo YES)" >> cleanup_report.txt

echo "" >> cleanup_report.txt
echo "2. FILES:" >> cleanup_report.txt
echo "   player_screen.dart exists: $([ -f lib/features/iptv/screens/player_screen.dart ] && echo NO || echo YES)" >> cleanup_report.txt
echo "   platform_utils_web.dart exists: $([ -f lib/core/utils/platform_utils_web.dart ] && echo NO || echo YES)" >> cleanup_report.txt
echo "   main_mobile.dart exists: $([ -f lib/main_mobile.dart ] && echo NO || echo YES)" >> cleanup_report.txt

echo "" >> cleanup_report.txt
echo "3. PUBSPEC:" >> cleanup_report.txt
echo "   universal_html removed: $(grep -q universal_html pubspec.yaml && echo NO || echo YES)" >> cleanup_report.txt
echo "   pointer_interceptor removed: $(grep -q pointer_interceptor pubspec.yaml && echo NO || echo YES)" >> cleanup_report.txt

cat cleanup_report.txt
```

---

## 10. Avant/Après Comparaison

```bash
# AVANT cleanup:
du -sh ios web lib/
# Exemple: 512M ios, 5M web, 45M lib/

# APRÈS cleanup:
du -sh lib/
# Devrait être: ~42-43M lib/ (réduction de ~5M web)

# Git status:
git status --short
# Devrait montrer des suppressions (D) pour ios/, web/
# Et modifications (M) pour pubspec.yaml et fichiers Dart editées
```

