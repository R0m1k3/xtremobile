# Task: Alignement sur xtremflow — EPG XMLTV, thème, stabilité des flux

## 1. EPG — repli XMLTV quand le fournisseur ne répond pas

- [x] Nouveau `lib/features/iptv/services/xmltv_service.dart` : téléchargement,
      gunzip transparent, parse **en flux** (`toXmlEvents`), index réduit à une
      fenêtre `-3 h / +18 h`, cache disque JSON (TTL 6 h)
- [x] Chaîne de repli dans `XtreamServiceMobile` :
      `get_short_epg` → `{dns}/xmltv.php` du fournisseur → URL personnalisée →
      source communautaire (`epgshare01` FR1)
- [x] Correspondance par `epg_channel_id`, puis par nom normalisé (accents,
      suffixes `HD/FHD/4K`, préfixes `FR:` / `|FR|`)
- [x] Index `streamId → Channel` alimenté par `getLiveChannels` : aucun site
      d'appel de `getShortEPG` n'a changé
- [x] Sémaphore EPG (3 requêtes max), comme xtremflow — une grille de 30 tuiles
      ne noie plus le panel et ne vide plus l'EPG de tout l'écran
- [x] Réglages : « EPG communautaire » (on/off) + « URL XMLTV personnalisée »

## 2. Thème — port de la charte « Warm Cinema » de xtremflow

- [x] `app_colors.dart` : palette ember/charbon/crème, alias de compatibilité
      conservés pour les 21 symboles Apple TV déjà utilisés
- [x] `app_theme.dart` : typo **Fraunces** (display) + **Karla** (UI), tokens
      spacing/radius/durations/curves alignés sur xtremflow
- [x] `mobile_theme.dart` : dérive désormais de `AppTheme` (échelle typo mobile)
      au lieu de dupliquer 390 lignes
- [x] `app_decorations.dart` : hexs Apple codés en dur remplacés par la palette
- [x] **Passe 2 (v1.6.1)** — le thème ne suffisait pas : du bleu restait codé en
      dur dans 19 fichiers d'écran/widget, hors palette. Balayage complet :
      - `0xFF0A84FF` (bleu Apple) dans la **pilule de navigation sélectionnée**
        (`mobile_scaffold`), les icônes de catégorie et le bouton « ajouter »
      - `0xFF4FC3F7` / `0xFF1565C0` (bleus) dans les overlays du lecteur
      - `Colors.blueAccent` / `Colors.blue` dans les boîtes de dialogue
      - gris Apple `1C1C1E` / `2C2C2E` / `3A3A3C` / `8E8E93` → charbons chauds
      - `Colors.white*` (128 occurrences) → paliers crème `onSurfaceNN`
      - `Colors.red/green/amber/yellow/grey*` → `error` / `success` /
        `ratingGold` / `outlineVariant`
      - noir pur sur remplissage clair → encre chaude `onPrimaryFixed`
      - halo de focus blanc → halo ember
      - Conservés en noir vrai : fonds de surface vidéo et voiles (`scrims`)
      - Vérification : plus **aucune** couleur Material/Apple codée en dur hors
        de `lib/core/theme/`

## 3. Lecture — arrêt en arrière-plan et tenue dans la durée

- [x] `AppLifecycleState.inactive` retiré du déclencheur d'arrêt : il se
      déclenchait au moindre volet de notifications
- [x] `_releasePlayback()` sur `paused` / `hidden` / `detached` — arrêt du flux,
      libération du décodeur, annulation des timers, wakelock coupé
      (les deux moteurs : `native_player_screen` et `lite_player_screen`)
- [x] Verrou `_isReleased` : watchdog et reconnexions ne peuvent plus relancer
      un flux depuis l'arrière-plan
- [x] Abonnements aux `Stream` du player stockés et annulés au `dispose`
- [x] `demuxer-max-back-bytes` plafonné à 8 Mo (défaut mpv : 50 Mio) — évite la
      dérive mémoire qui finissait en kill Android après plusieurs heures
- [x] `setState` de position limité aux moments où les contrôles sont visibles ;
      horloge ne reconstruit qu'au changement de minute
- [x] FocusNodes du lecteur Lite libérés au `dispose`

## 4. Vitesse de chargement

- [x] `prewarmHost()` : pré-résolution DNS + socket TCP/TLS ouvert puis fermé
      avant l'ouverture du flux (aucune requête HTTP, donc aucun slot de
      connexion consommé chez le fournisseur), plafonné à 1,5 s

> Non retenu par l'utilisateur : décodage matériel VOD, réduction du probe,
> audio multicanal natif. Le profil de décodage reste inchangé.

## Vérifications

- [x] `flutter analyze` : 0 erreur / 0 warning sur les fichiers touchés
      (3 warnings de code mort restants, déjà présents dans HEAD)
- [x] `flutter test` : 19/19 (18 unitaires + 1 sur un vrai dump)
- [x] Vrai dump `epg_ripper_FR1.xml.gz` (5,4 Mo gz / 46 Mo XML / 69 802
      programmes) : 517 chaînes indexées en 1,1 s, 5/5 correspondances
- [x] `flutter build apk --release` → `app-release.apk` (94,3 Mo)

Non corrigé (pré-existant, hors périmètre) : erreurs d'analyse dans
`lib/core/utils/memory_profiler.dart` et `hive_encryption_benchmark.dart`
(orphelins, hors graphe d'import) et `test/widget_test.dart`.
