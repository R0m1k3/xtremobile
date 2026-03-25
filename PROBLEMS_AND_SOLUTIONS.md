# 🐛 LISTE DES PROBLÈMES DÉTECTÉS ET SOLUTIONS

## BACKEND (Dart Server)

### 🔴 CRITIQUE

#### 1. **Password Hashing Basique (SHA-256 simple)**
**Fichier**: `bin/utils/password_hasher.dart`
**Problème**: 
```dart
static String hash(String password) {
  final bytes = utf8.encode(password);
  return sha256.convert(bytes).toString();
}
```
- ❌ Pas de salt aléatoire
- ❌ Facile à cracker (lookup tables)
- ❌ Non conforme OWASP

**Solution**: Remplacer par bcrypt (cf. IMPLEMENTATION_GUIDE.md Section 3.2)

---

#### 2. **Pas de Logging Structuré**
**Fichier**: Partout où il y a `print()`
**Problème**:
- ❌ Impossible de persister les logs
- ❌ Pas de nivaux de sévérité
- ❌ Pas de traçage end-to-end
- ❌ Impossible de debugger en production

**Solution**: Implémenter LoggingService (cf. IMPLEMENTATION_GUIDE.md Section 1.2)

---

#### 3. **Gestion d'Erreurs Incohérente**
**Fichier**: `bin/api/*.dart`
**Problème**:
```dart
// Incohérent:
return Response(401, body: jsonEncode({'success': false, 'error': 'Invalid credentials'}));
return Response.internalServerError(body: ...);
throw Exception(e); // Crash
```

**Solution**: Exceptions unifiées (cf. IMPLEMENTATION_GUIDE.md Section 2)

---

#### 4. **Tokens sans Expiration**
**Fichier**: `bin/models/session.dart`
**Problème**:
- ❌ Sessions vivre éternellement
- ❌ Pas de refresh token
- ❌ Impossible de révoquer à distance

**Solution**: JWT + refresh tokens (cf. IMPLEMENTATION_GUIDE.md Section 3.3)

---

#### 5. **SQL Injection Peu Probable mais Risquée**
**Fichier**: `bin/database/database.dart`
**Problème**:
```dart
_db.select('SELECT * FROM users WHERE username = ?', [username]); // OK
_db.execute('''CREATE TABLE IF NOT EXISTS users (...)'''); // Hardcoded OK
```
- ⚠️ Utilise les paramètres (bon!)
- ❌ Mais pas de validation input

**Solution**: Ajouter validation Schema dans chaque handler

---

### 🟠 IMPORTANT

#### 6. **Pas de Backup Automatique**
**Fichier**: Manquant
**Problème**: 
- ❌ Si DB corrompue, données perdues
- ❌ Pas de disaster recovery

**Solution**: BackupService (cf. IMPLEMENTATION_GUIDE.md Section 4.2)

---

#### 7. **Pas de Migrations Database**
**Fichier**: `bin/database/database.dart`
**Problème**:
- ❌ Impossible d'updater schema en production
- ❌ Versionning unclear
- ❌ Risque de corruption

**Solution**: Migration system (cf. IMPLEMENTATION_GUIDE.md Section 4.1)

---

#### 8. **Rate Limiting Limité**
**Fichier**: `bin/middleware/security_middleware.dart`
**Problème**:
```dart
Middleware rateLimitMiddleware({int requestsPerMinute = 200}) {
  // Par IP, OK
  // Mais:
  // - Pas spécifique par endpoint
  // - Pas de persistent storage (reset au redémarrage)
  // - Pas de 2FA rate limiting dur
}
```

**Solution**: 
- Rate limiting par endpoint: `/api/auth/login` (5/5min)
- Lockout temporaire: après 5 tentatives
- Persistent storage (Redis ou DB)

---

#### 9. **Secrets en Clair**
**Fichier**: `.env` (n'existe pas)
**Problème**:
- ❌ JWT_SECRET hardcoded
- ❌ Database path hardcoded
- ❌ Credentials Xtream côté client

**Solution**:
```bash
# .env.example (ne pas commit .env)
JWT_SECRET=your-secret-here
DATABASE_PATH=/app/data/xtremflow.db
NODE_ENV=production
```

---

#### 10. **FFmpeg Process Management**
**Fichier**: `bin/server.dart` (fonction `_createStreamHandler`)
**Problème**:
```dart
// Bon:
controller.onCancel = () {
  print('Client disconnected for $streamId. Killing FFmpeg...');
  process.kill();
};

// Mais:
// - Pas de timeout FFmpeg (si hang)
// - Pas de memory limit
// - Pas de détection process crash
```

**Solution**:
```dart
// Timeout pour procédure longue
final timeout = Future.delayed(const Duration(seconds: 120), () {
  if (process.isRunning) {
    process.kill();
    logger.logError('FFmpeg timeout for $streamId', null, null);
  }
});
```

---

### 🟡 AMÉLIORATION

#### 11. **Pas de Tests Unitaires Backend**
**Fichier**: `test/` (vide ou minimal)
**Problème**: 
- ❌ Risque de régression
- ❌ Impossible de refactorer confiantément

**Solution**: 
```dart
// test/unit/auth_test.dart
void main() {
  group('API Auth', () {
    test('login success', () { ... });
    test('login invalid credentials', () { ... });
    test('token refresh', () { ... });
  });
}
```

---

#### 12. **Pas de Documentation API**
**Fichier**: Manquant (ni OpenAPI, ni Postman)
**Problème**: 
- ❌ Frontend et backend se désynchronisent
- ❌ Onboarding difficile

**Solution**: Générer OpenAPI depuis code avec `shelf_openapi`

---

## FRONTEND (Flutter)

### 🔴 CRITIQUE

#### 13. **Pas de Gestion d'Erreurs Centralisée**
**Fichier**: `lib/core/api/api_client.dart`
**Problème**:
```dart
Future<Response> get(String path) async {
  return _dio.get(path); // Exception directe au caller
}
// Chaque écran doit gérer les erreurs
```

**Solution**:
```dart
Future<T> get<T>(String path, T Function(Map) parser) async {
  try {
    final response = await _dio.get(path);
    return parser(jsonDecode(response.data));
  } on DioException catch (e) {
    throw NetworkException(
      message: e.message ?? 'Network error',
      code: 'NETWORK_ERROR',
    );
  }
}
```

---

#### 14. **TODO non résolus**
**Fichier**: `lib/core/api/api_client.dart`
**Problème**:
```dart
String _getBaseUrl() {
  // TODO: Configure base URL for mobile
  return '';
}
```

**Solution**: 
```dart
String _getBaseUrl() {
  const isProd = String.fromEnvironment('ENV') == 'production';
  return isProd
      ? 'https://api.example.com'
      : 'http://localhost:8089';
}
```

---

#### 15. **Pas d'Encryption Données Locales**
**Fichier**: `lib/core/database/hive_service.dart`
**Problème**:
- ❌ Hive stocke auth_token en clair
- ❌ Credentials playlist en clair

**Solution**:
```dart
// Ajouter chiffrement Hive
await Hive.openBox(
  'secure_box',
  encryptionCipher: HiveAesCipher(secretKey),
);
```

---

#### 16. **Riverpod Providers Pas Optimisés**
**Fichier**: `lib/features/iptv/providers/`
**Problème**:
- ❌ Pas de `family` modifiers pour paramètres
- ❌ Pas de `select` pour optimiser re-renders

**Solution**:
```dart
final playlistProvider = FutureProvider.family<Playlist, String>(
  (ref, playlistId) {
    final api = ref.watch(apiClientProvider);
    return api.getPlaylist(playlistId);
  },
);

// Utilisation
final playlist = ref.watch(playlistProvider(selectedId));
```

---

### 🟠 IMPORTANT

#### 17. **Gestion Cache Implicite**
**Fichier**: `lib/core/api/api_client.dart`
**Problème**:
- ❌ Caching via Dio couche basse
- ❌ Pas de contrôle granulaire (TTL par endpoint)
- ❌ UI ne sait pas quand les données sont en cache

**Solution**:
```dart
final cachedPlaylistsProvider = FutureProvider<List<Playlist>>(
  (ref) async {
    final api = ref.watch(apiClientProvider);
    // Cache 5 min automatiquement via Riverpod
    final ref.keepAlive(); // Garder en memory
    return api.getPlaylists();
  },
).withCache(const Duration(minutes: 5));
```

---

#### 18. **Pas de Gestion Hors-Ligne**
**Fichier**: N/A
**Problème**:
- ❌ Si serveur down, app crash
- ❌ Pas de cached data fallback

**Solution**: 
```dart
FutureProvider avec fallback:
- Récupérer depuis API
- Si fail, chercher dans cache local Hive
```

---

#### 19. **Navigation Manuelle (go_router pas optimisé)**
**Fichier**: `lib/core/router/app_router.dart`
**Problème**:
```dart
if (MediaQuery.of(context).size.width < 768) {
  return MobileLoginScreen();
}
return LoginScreen();
// Duplication pour chaque route
```

**Solution**:
```dart
// Créer builder factory:
Widget _buildPageForForm(
  BuildContext ctx,
  Widget mobileScreen,
  Widget desktopScreen,
) {
  return MediaQuery.of(ctx).size.width < 768 ? mobileScreen : desktopScreen;
}
```

---

#### 20. **Manque Tests UI**
**Fichier**: `test/widget_test.dart`
**Problème**:
- ❌ Seul 1 test existant
- ❌ Pas de couverture features

**Solution**:
```dart
// test/widget/login_screen_test.dart
void main() {
  testWidgets('Login screen displays username field', (WidgetTester tester) {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(TextField), findsWidgets);
  });
}
```

---

## DEVOPS & DEPLOYMENT

### 🟡 AMÉLIORATION

#### 21. **Docker Image Pas Optimisée**
**Fichier**: `Dockerfile`
**Problème**:
- ❌ Pas de multi-stage build
- ❌ Couches non optimisées
- ❌ Taille image potentiellement large

**Solution**:
```dockerfile
# Stage 1: Build
FROM google/dart:latest AS builder
WORKDIR /app
COPY . .
RUN dart pub get && dart compile exe server.dart -o server

# Stage 2: Runtime
FROM debian:bookworm-slim
COPY --from=builder /app/server /app/server
CMD ["./server"]
```

---

#### 22. **Pas de Healthcheck**
**Fichier**: `docker-compose.yml`
**Problème**:
- ❌ Docker ne sait pas si app est healthy
- ❌ Redémarrage automatique pas fiable

**Solution**:
```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8089/api/health || exit 1
```

---

#### 23. **Pas de CI/CD Pipeline**
**Fichier**: `.github/workflows/` (N/A)
**Problème**:
- ❌ Tests manuels
- ❌ Déploiement manuel risqué
- ❌ Pas de vérification qualité

**Solution**: Créer GitHub Actions (test, lint, build, deploy)

---

## SÉCURITÉ GÉNÉRALE

### 🔴 CRITIQUE

#### 24. **CORS Permissif**
**Fichier**: `bin/server.dart`
**Problème**:
```dart
Middleware _corsMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      final response = await handler(request);
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*', // ❌ DANGEREUX!
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE',
      });
    };
  };
}
```

**Solution**:
```dart
'Access-Control-Allow-Origin': 'https://example.com',
// Ou lire depuis config:
final origin = request.headers['origin'];
if (_allowedOrigins.contains(origin)) {
  // Add header
}
```

---

#### 25. **Pas de CSRF Protection**
**Fichier**: N/A
**Problème**:
- ❌ Requête forgée possible depuis autre site
- ❌ Utilisateur clique lien malveillant → action without consent

**Solution**: Token CSRF unique par session

---

#### 26. **Pas de Validation Input Stricte**
**Fichier**: `bin/api/*.dart`
**Problème**:
```dart
final username = payload['username'] as String?; // Pas de validation!
// Accepte "", " ", très long, etc.
```

**Solution**:
```dart
class ValidationException extends AppException { ... }

if (username == null || username.isEmpty || username.length > 50) {
  throw ValidationException(
    message: 'Username must be 1-50 characters',
  );
}
```

---

## 📊 RÉSUMÉ PROBLÈMES PAR SÉVÉRITÉ

| Sévérité | Count | Examples |
|----------|-------|----------|
| 🔴 Critique | 11 | Password hashing, logging, errors, tokens, CORS |
| 🟠 Important | 9 | Backup, migrations, rate limiting, encryption |
| 🟡 Amélioration | 6 | Tests, docs, Docker, CI/CD |
| **Total** | **26** | |

---

## 📈 IMPACT ESTIMATION

| Problème | Impact | Fix Time | Business Value |
|----------|--------|----------|-----------------|
| 1. Password | 🔴 Critique | 0.5j | 🟢 Très haut |
| 2. Logging | 🔴 Critique | 1j | 🟢 Très haut |
| 3. Errors | 🔴 Critique | 1j | 🟢 Très haut |
| 4. Tokens | 🔴 Critique | 2j | 🟢 Très haut |
| 6. Backup | 🟠 Important | 1j | 🟡 Haut |

---

## ✅ QUICK WINS (Fix en < 1 jour)

1. Ajouter logger package
2. Remplacer print() critiques par logging
3. Ajouter CORS origin check
4. Ajouter validation input basique
5. Ajouter .env secrets

---

*Document généré: 25 Mars 2026*
*Dernière maj: Jour 1*
