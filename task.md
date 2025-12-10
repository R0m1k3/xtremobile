# Task: UI Improvements & Cache EPG Implementation

## Demandes utilisateur

1. Enlever les informations "LITE PLAYER:" à côté des titres de chaînes
2. Enlever les flèches de navigation sur le flux TV (live)
3. Settings : améliorer la visibilité de la sélection (entourage visible)
4. Live TV : remplacer les contours blancs par une ombre blanche voyante
5. Favoris : long press 3 sec sur OK pour ajouter/retirer (télécommande)
6. Films/Séries : réduire le carrousel, déplacer la barre de recherche en dessous
7. Traduire les barres de recherche en français
8. Cache EPG 24h pour Films et Séries (éviter rechargement au lancement)
9. Bouton dans Settings pour forcer la mise à jour du cache
10. Navigation top bar style Apple TV moderne (fond blanc au focus)

## Progression

### Phase 1 : Player UI

- [x] 1.1 Retirer "LITE PLAYER:" du titre dans `lite_player_screen.dart`
- [x] 1.2 Enlever les flèches haut/bas (navigation channels) dans `lite_player_screen.dart`

### Phase 2 : Settings Tab Focus

- [x] 2.1 Améliorer la visibilité de la sélection dans `mobile_settings_tab.dart` (bordure visible)
- [x] 2.2 Ajouter bouton "Actualiser le cache" dans les Settings

### Phase 3 : Live TV Focus Style

- [x] 3.1 Modifier `tv_focusable.dart` pour utiliser une ombre blanche au lieu d'un contour

### Phase 4 : Favoris Long Press (3 secondes)

- [x] 4.1 Implémenter le long press 3 sec sur les chaînes pour toggle favoris

### Phase 5 : Movies/Series UI

- [x] 5.1 Réduire la hauteur du carrousel dans `mobile_movies_tab.dart`
- [x] 5.2 Réduire la hauteur du carrousel dans `mobile_series_tab.dart`
- [x] 5.3 Déplacer la barre de recherche sous le carrousel (movies)
- [x] 5.4 Déplacer la barre de recherche sous le carrousel (series)
- [x] 5.5 Traduire les placeholders de recherche en français

### Phase 6 : Cache EPG 24h

- [x] 6.1 Augmenter maxStale à 24h dans XtreamServiceMobile
- [x] 6.2 Ajouter méthode forceRefreshCache()
- [x] 6.3 Ajouter bouton refresh cache dans Settings

### Phase 7 : Navigation Apple TV Style

- [x] 7.1 Modifier top bar avec style Apple TV moderne (fond blanc au focus)

## Notes techniques

- Cache Dio HTTP configuré avec maxStale: 24h
- Cache en mémoire (`_cachedMoviesRaw`, `_cachedSeriesRaw`) vidé au redémarrage
- Le cache HTTP Hive persiste entre les sessions
- Bouton "Actualiser le cache" nettoie le cache Hive
