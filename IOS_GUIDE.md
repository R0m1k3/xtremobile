# Version iPhone / iPad — build et installation hors App Store

Ce guide explique comment produire XtremFlow pour iOS/iPadOS et l'installer sur
un appareil **sans passer par l'App Store**.

---

## 1. Ce qui a été mis en place

Le dossier `ios/` n'est pas versionné : il est **régénéré au moment du build**
par `scripts/prepare_ios.sh`, ce qui garantit qu'il correspond toujours à la
version de Flutter utilisée. Le script applique ensuite les réglages
indispensables à une app IPTV :

| Réglage | Pourquoi |
|---|---|
| `NSAllowsArbitraryLoads` | Les serveurs Xtream Codes sont presque toujours en `http://`. Sans cette exception, App Transport Security bloque **toutes** les requêtes API et tous les flux. |
| `UIBackgroundModes: audio` | Le son continue quand l'écran est verrouillé. |
| Orientations paysage + 4 sens sur iPad | Lecteur vidéo plein écran, rotation libre sur tablette. |
| `NSLocalNetworkUsageDescription` | Autorisation iOS 14+ si le serveur IPTV est sur le réseau local. |
| Cible iOS 13.0 | Minimum exigé par `media_kit` (libmpv/FFmpeg). |
| Bundle id `com.xtremflow.mobile` | Aligné sur l'`applicationId` Android. |

Le code Dart est déjà entièrement portable (aucun appel spécifique Android), et
`media_kit_libs_video` embarque déjà la variante iOS de libmpv : les codecs
AC3 / EAC3 / DTS restent donc gérés comme sur Android.

## 2. Produire l'IPA

### Option A — GitHub Actions (aucun Mac nécessaire) ✅ recommandé

Le workflow `.github/workflows/build-ios.yml` tourne sur un runner macOS et
publie un **IPA non signé** :

* automatiquement à chaque push sur `main`, joint à la GitHub Release de la
  version (à côté de l'APK) ;
* à la demande via **Actions → Build iOS → Run workflow**, le fichier est alors
  disponible en artifact.

> ⚠️ Les runners macOS comptent **10× plus** de minutes GitHub Actions que les
> runners Linux. C'est pourquoi le workflow ne se déclenche pas sur les pull
> requests.

### Option B — En local, sur un Mac

```bash
flutter pub get
./scripts/prepare_ios.sh
dart run flutter_launcher_icons -f flutter_launcher_icons-ios.yaml
flutter build ios --release --no-codesign

cd build/ios/iphoneos
mkdir -p Payload && cp -R Runner.app Payload/
zip -qry ../../../xtremflow-unsigned.ipa Payload
```

Un IPA n'est rien d'autre qu'une archive zip contenant `Payload/Runner.app`.

## 3. Installer sans l'App Store

C'est ici que se situe la vraie contrainte : elle ne vient pas du code mais
d'Apple. Toute app iOS doit être **signée** par un certificat Apple avant de
pouvoir se lancer. Quatre voies possibles :

| Méthode | Coût | Validité | Matériel requis |
|---|---|---|---|
| **AltStore / SideStore** (Apple ID gratuit) | 0 € | **7 jours**, renouvelés automatiquement en Wi-Fi | Un PC/Mac pour l'installation initiale |
| **Sideloadly** (Apple ID gratuit) | 0 € | 7 jours, renouvellement manuel | Windows ou macOS, câble USB |
| **Compte Apple Developer** | 99 €/an | **1 an** | Idem, mais plus de limites gênantes |
| **TestFlight** | 99 €/an | 90 jours par build | Passe par App Store Connect (revue allégée) |

Limites du compte gratuit : **3 apps sideloadées maximum** et **10 App IDs par
semaine**. Avec un compte payant, la signature tient un an et les limites
disparaissent — c'est la meilleure option si l'app est utilisée au quotidien.

### Marche à suivre avec AltStore (gratuit, la plus courante)

1. Installer **AltServer** sur un PC Windows ou un Mac (altstore.io), plus
   iTunes + iCloud (versions du site Apple, pas du Microsoft Store) sur Windows.
2. Brancher l'iPhone/iPad en USB, faire confiance à l'ordinateur.
3. Dans AltServer : *Install AltStore* → choisir l'appareil → saisir son Apple ID.
4. Sur l'appareil : **Réglages → Général → VPN et gestion de l'appareil** →
   faire confiance au profil développeur.
5. Télécharger `xtremobile-vX.Y.Z-unsigned.ipa` depuis la GitHub Release.
6. Dans AltStore sur l'appareil : **My Apps → + → sélectionner l'IPA**. AltStore
   signe l'app avec l'Apple ID et l'installe.
7. Garder AltServer allumé sur le même Wi-Fi : AltStore renouvelle la signature
   avant l'expiration des 7 jours. **SideStore** fait la même chose sans PC une
   fois configuré.

### Avec Sideloadly

Plus simple mais sans renouvellement automatique : installer Sideloadly, brancher
l'appareil, glisser l'IPA, saisir l'Apple ID, cliquer sur *Start*. À refaire tous
les 7 jours.

### Si l'appareil n'est pas toujours sur le même réseau

C'est la limite d'AltStore : son renouvellement automatique exige qu'AltServer
tourne sur **le même Wi-Fi** que l'appareil. Un iPad souvent hors du réseau
domestique verra l'app expirer au bout de 7 jours, loin de tout ordinateur.

Deux réponses :

* **SideStore** — variante d'AltStore qui renouvelle la signature *depuis
  l'appareil*, sans AltServer ni réseau local. Un ordinateur reste nécessaire
  une seule fois, pour générer le fichier de pairage. Ensuite l'iPad se
  débrouille seul, en 4G comme en Wi-Fi. Gratuit, mais l'installation initiale
  est plus technique.
* **Compte Apple Developer (99 €/an)** — la signature tient **un an** : il n'y a
  plus rien à renouveler, donc plus aucune contrainte de réseau. C'est la
  solution la plus simple pour un appareil nomade.

### Avec un compte Apple Developer (99 €/an)

La signature tient **un an** et l'app cesse d'expirer toutes les semaines. Deux
approches :

* signer l'IPA avec Sideloadly/AltStore en utilisant l'Apple ID du compte payant
  (le plus simple, rien à changer dans le projet) ;
* ou passer à une distribution **Ad Hoc** (jusqu'à 100 appareils enregistrés par
  leur UDID) : il faut alors ajouter un certificat et un profil de provisioning
  dans le workflow et remplacer `--no-codesign` par un `flutter build ipa
  --export-options-plist`.

### Cas particulier de l'Union européenne

Depuis iOS 17.4, l'UE autorise les **magasins alternatifs** (AltStore PAL,
notamment). Y publier l'app exige tout de même un compte développeur payant et
la notarisation Apple : intéressant pour distribuer à d'autres personnes, inutile
pour un usage personnel.

### Ce qui n'est pas possible

Il n'existe **aucun** moyen d'installer une app iOS sans signature Apple sur un
appareil non jailbreaké. Un simple lien de téléchargement, comme pour l'APK
Android, n'existe pas sur iOS.

## 4. Points de vigilance

* **Mises à jour** : pas de mise à jour automatique. Il faut retélécharger l'IPA
  de la nouvelle release et refaire l'installation.
* **Expiration** : une app signée avec un Apple ID gratuit s'ouvre encore après
  7 jours mais refuse de se lancer ; une réinstallation conserve les données.
* **Personnalisation** : pour changer le nom affiché, le bundle id ou la cible
  de déploiement, modifier les variables en tête de `scripts/prepare_ios.sh` —
  ne pas éditer `ios/` à la main, il est régénéré à chaque build.
* **Projet Xcode versionné** : si vous préférez committer le dossier `ios/`
  (pour le retoucher dans Xcode), générez-le une fois sur un Mac puis committez-le.
  `scripts/prepare_ios.sh` détecte sa présence, ne le régénère pas et se contente
  de réappliquer les réglages du tableau §1.
