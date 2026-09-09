#!/usr/bin/env bash
#
# Prépare le dossier ios/ pour un build iPhone / iPad.
#
# Le dépôt ne versionne pas le projet Xcode : il est régénéré par
# `flutter create` au moment du build (macOS uniquement), puis adapté aux
# besoins de l'app IPTV (flux HTTP en clair, audio en arrière-plan, iPad).
# Si un dossier ios/ est déjà présent dans le dépôt, il est conservé tel quel
# et seuls les réglages ci-dessous lui sont réappliqués — le script est
# idempotent et peut être relancé sans risque.
#
# Usage : ./scripts/prepare_ios.sh
set -euo pipefail

BUNDLE_ID="com.xtremflow.mobile"   # identique à l'applicationId Android
DISPLAY_NAME="XtremFlow"
DEPLOYMENT_TARGET="13.0"           # minimum exigé par media_kit sur iOS

cd "$(dirname "$0")/.."

if [ "$(uname -s)" != "Darwin" ]; then
  echo "::error::Un build iOS ne peut être préparé que sur macOS (Xcode requis)."
  exit 1
fi

PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
PLIST="ios/Runner/Info.plist"
PODFILE="ios/Podfile"
PLISTBUDDY=/usr/libexec/PlistBuddy

if [ ! -d "ios/Runner.xcodeproj" ]; then
  echo "==> Aucun dossier ios/ : génération du projet Xcode"
  # Garde-fou : `flutter create` ne doit recréer que la plateforme iOS. Si une
  # version de l'outil venait à réécrire le point d'entrée de l'app, on le
  # restaure — un main.dart écrasé produirait un IPA contenant le compteur
  # d'exemple de Flutter, sans que le build échoue.
  MAIN_BACKUP="$(mktemp)"
  cp lib/main.dart "$MAIN_BACKUP"
  flutter create --platforms=ios --org com.xtremflow --project-name xtremobile .
  if ! cmp -s lib/main.dart "$MAIN_BACKUP"; then
    echo "==> lib/main.dart réécrit par flutter create : restauration"
    cp "$MAIN_BACKUP" lib/main.dart
  fi
  rm -f "$MAIN_BACKUP"
  # `flutter create --org com.xtremflow` écrit com.xtremflow.xtremobile ; on
  # aligne sur l'applicationId Android (la cible RunnerTests suit le suffixe).
  sed -i '' "s/com\.xtremflow\.xtremobile/${BUNDLE_ID}/g" "$PBXPROJ"
else
  echo "==> Dossier ios/ déjà présent : génération ignorée"
fi

echo "==> Cible de déploiement : iOS ${DEPLOYMENT_TARGET}"
perl -pi -e "s/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = ${DEPLOYMENT_TARGET};/g" "$PBXPROJ"
perl -pi -e "s/^#?\s*platform :ios.*/platform :ios, '${DEPLOYMENT_TARGET}'/" "$PODFILE"

# Les pods (dont libmpv de media_kit) doivent viser la même version qu'ici,
# sinon CocoaPods refuse la résolution. Ajouté une seule fois.
if ! grep -q "IPHONEOS_DEPLOYMENT_TARGET" "$PODFILE"; then
  perl -0pi -e "s/(flutter_additional_ios_build_settings\(target\))/\$1\n    target.build_configurations.each do |config|\n      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '${DEPLOYMENT_TARGET}'\n    end/" "$PODFILE"
fi

echo "==> Info.plist"

plist_set() { # clé, type, valeur
  $PLISTBUDDY -c "Set :$1 $3" "$PLIST" 2>/dev/null || $PLISTBUDDY -c "Add :$1 $2 $3" "$PLIST"
}
plist_reset() { # supprime une clé composite avant de la reconstruire
  $PLISTBUDDY -c "Delete :$1" "$PLIST" 2>/dev/null || true
}

plist_set CFBundleDisplayName string "$DISPLAY_NAME"
plist_set CFBundleName string "$DISPLAY_NAME"

# Les serveurs Xtream Codes sont très souvent en http:// simple : sans cette
# exception, App Transport Security bloque toutes les requêtes et tous les
# flux vidéo, sans message d'erreur exploitable côté Dart.
plist_reset NSAppTransportSecurity
$PLISTBUDDY -c "Add :NSAppTransportSecurity dict" "$PLIST"
$PLISTBUDDY -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" "$PLIST"

# Lecture audio quand l'écran est verrouillé / l'app en arrière-plan.
plist_reset UIBackgroundModes
$PLISTBUDDY -c "Add :UIBackgroundModes array" "$PLIST"
$PLISTBUDDY -c "Add :UIBackgroundModes:0 string audio" "$PLIST"

# Un serveur Xtream hébergé sur le réseau local déclenche la demande
# d'autorisation « réseau local » d'iOS 14+ ; sans description, elle est refusée.
plist_set NSLocalNetworkUsageDescription string "Nécessaire pour joindre un serveur IPTV hébergé sur votre réseau local."

# Orientations : paysage indispensable pour le lecteur, les quatre sens sur iPad.
plist_reset UISupportedInterfaceOrientations
$PLISTBUDDY -c "Add :UISupportedInterfaceOrientations array" "$PLIST"
i=0
for o in UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight; do
  $PLISTBUDDY -c "Add :UISupportedInterfaceOrientations:$i string $o" "$PLIST"
  i=$((i + 1))
done

plist_reset "UISupportedInterfaceOrientations~ipad"
$PLISTBUDDY -c "Add :UISupportedInterfaceOrientations~ipad array" "$PLIST"
i=0
for o in UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown \
         UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight; do
  $PLISTBUDDY -c "Add :UISupportedInterfaceOrientations~ipad:$i string $o" "$PLIST"
  i=$((i + 1))
done

echo "==> Projet iOS prêt (bundle id : ${BUNDLE_ID})"
