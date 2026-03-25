# 🔧 GUIDE D'IMPLÉMENTATION TECHNIQUE

## 1️⃣ LOGGING PROFESSIONNEL (Jour 1-2)

### 1.1 Ajouter dépendances
```yaml
# pubspec.yaml (bin/)
dependencies:
  logger: ^2.2.0
  path: ^1.9.0
```

### 1.2 Créer LoggingService (Backend)

**Fichier**: `bin/services/logging_service.dart`
```dart
import 'dart:io';
import 'package:logger/logger.dart';

class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;

  late final logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.dateAndTime,
    ),
  );

  LoggingService._internal() {
    _initializeFileHandler();
  }

  void _initializeFileHandler() {
    final logsDir = Directory('/app/logs');
    if (!logsDir.existsSync()) {
      logsDir.createSync(recursive: true);
    }
  }

  void logRequest(String method, String path, int statusCode, int durationMs) {
    final emoji = statusCode < 400 ? '✅' : '❌';
    logger.i('$emoji $method $path → $statusCode (${durationMs}ms)');
  }

  void logError(String message, Object error, StackTrace stackTrace) {
    logger.e(message, error: error, stackTrace: stackTrace);
  }

  void logWarning(String message) => logger.w(message);
  void logInfo(String message) => logger.i(message);
  void logDebug(String message) => logger.d(message);
}
```

### 1.3 Middleware Logging (Backend)

**Fichier**: `bin/middleware/logging_middleware.dart`
```dart
import 'package:shelf/shelf.dart';
import '../services/logging_service.dart';
import 'dart:async';

Middleware loggingMiddleware() {
  final logger = LoggingService();

  return (Handler handler) {
    return (Request request) async {
      final stopwatch = Stopwatch()..start();

      try {
        final response = await handler(request);

        logger.logRequest(
          request.method,
          request.url.path,
          response.statusCode,
          stopwatch.elapsedMilliseconds,
        );

        return response;
      } catch (e, st) {
        stopwatch.stop();
        logger.logError(
          'Error handling ${request.method} ${request.url.path}',
          e,
          st,
        );
        rethrow;
      }
    };
  };
}
```

---

## 2️⃣ SYSTÈME D'ERREURS UNIFIÉ (Jour 2)

### 2.1 Exceptions Personnalisées

**Fichier**: `bin/utils/app_exceptions.dart`
```dart
abstract class AppException implements Exception {
  final String message;
  final String code;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? context;
  final int httpCode;

  AppException({
    required this.message,
    required this.code,
    this.stackTrace,
    this.context,
    this.httpCode = 500,
  });

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    'context': context,
  };

  @override
  String toString() => '$code: $message';
}

class AuthException extends AppException {
  AuthException({
    required String message,
    String code = 'AUTH_ERROR',
    Map<String, dynamic>? context,
  }) : super(
    message: message,
    code: code,
    context: context,
    httpCode: 401,
  );
}

class ValidationException extends AppException {
  ValidationException({
    required String message,
    String code = 'VALIDATION_ERROR',
    Map<String, dynamic>? context,
  }) : super(
    message: message,
    code: code,
    context: context,
    httpCode: 400,
  );
}

class DatabaseException extends AppException {
  DatabaseException({
    required String message,
    String code = 'DATABASE_ERROR',
    Map<String, dynamic>? context,
  }) : super(
    message: message,
    code: code,
    context: context,
    httpCode: 500,
  );
}

class StreamingException extends AppException {
  StreamingException({
    required String message,
    String code = 'STREAMING_ERROR',
    Map<String, dynamic>? context,
  }) : super(
    message: message,
    code: code,
    context: context,
    httpCode: 500,
  );
}
```

### 2.2 Error Handler Middleware

**Fichier**: `bin/middleware/error_handler.dart`
```dart
import 'package:shelf/shelf.dart';
import 'dart:convert';
import '../utils/app_exceptions.dart';
import '../services/logging_service.dart';

Middleware errorHandlerMiddleware() {
  final logger = LoggingService();

  return (Handler handler) {
    return (Request request) async {
      try {
        return await handler(request);
      } on AppException catch (e, st) {
        logger.logError(
          'AppException in ${request.method} ${request.url}',
          e,
          st,
        );

        return Response(
          e.httpCode,
          body: jsonEncode({
            'success': false,
            'error': e.toJson(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e, st) {
        logger.logError(
          'Unexpected error in ${request.method} ${request.url}',
          e,
          st,
        );

        return Response(
          500,
          body: jsonEncode({
            'success': false,
            'error': {
              'code': 'INTERNAL_SERVER_ERROR',
              'message': 'Une erreur interne s\'est produite',
            },
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    };
  };
}
```

---

## 3️⃣ AUTHENTIFICATION SÉCURISÉE (Jour 2-4)

### 3.1 Ajouter Dépendances
```yaml
# bin/pubspec.yaml
dependencies:
  bcrypt: ^1.1.0
  dart_jsonwebtoken: ^2.11.0
  totp: ^3.0.0
```

### 3.2 Password Hasher avec Bcrypt

**Fichier**: `bin/utils/password_hasher.dart` (REMPLACER)
```dart
import 'package:bcrypt/bcrypt.dart';

class PasswordHasher {
  static String hash(String password) {
    // Generate salt and hash in one step
    return BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 12));
  }

  static bool verify(String password, String hash) {
    try {
      return BCrypt.checkpw(password, hash);
    } catch (e) {
      return false;
    }
  }

  /// Verify and potentially upgrade hash if using older algorithm
  static Map<String, dynamic> verifyAndUpgrade(
    String password,
    String hash,
  ) {
    final isValid = verify(password, hash);
    final needsUpgrade = false; // No upgrade needed with bcrypt

    return {
      'valid': isValid,
      'needs_upgrade': needsUpgrade,
      'new_hash': isValid ? hash : null,
    };
  }
}
```

### 3.3 JWT Token Service

**Fichier**: `bin/services/jwt_service.dart` (NEW)
```dart
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../models/user.dart';

class JwtService {
  static final JwtService _instance = JwtService._internal();
  factory JwtService() => _instance;

  late final String _secret;
  final Duration accessTokenDuration = const Duration(minutes: 15);
  final Duration refreshTokenDuration = const Duration(days: 7);

  JwtService._internal() {
    _secret = const String.fromEnvironment(
      'JWT_SECRET',
      defaultValue: 'your-secret-key-change-in-production',
    );
  }

  /// Generate access token (15 min)
  String generateAccessToken(User user) {
    final payload = {
      'id': user.id,
      'username': user.username,
      'is_admin': user.isAdmin,
      'type': 'access',
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp': DateTime.now()
          .add(accessTokenDuration)
          .millisecondsSinceEpoch ~/
          1000,
    };

    return JWT(payload).sign(SecretKey(_secret));
  }

  /// Generate refresh token (7 days)
  String generateRefreshToken(User user) {
    final payload = {
      'id': user.id,
      'type': 'refresh',
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp': DateTime.now()
          .add(refreshTokenDuration)
          .millisecondsSinceEpoch ~/
          1000,
    };

    return JWT(payload).sign(SecretKey(_secret));
  }

  /// Verify and decode token
  dynamic verifyToken(String token) {
    try {
      return JWT.verify(token, SecretKey(_secret));
    } on JWTExpiredException catch (e) {
      throw Exception('Token expired: ${e.message}');
    } on JWTException catch (e) {
      throw Exception('Invalid token: ${e.message}');
    }
  }

  /// Check if token is expired
  bool isTokenExpired(String token) {
    try {
      final decoded = JWT.decode(token);
      final exp = decoded.payload['exp'] as int?;
      if (exp == null) return true;

      final expirationTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return expirationTime.isBefore(DateTime.now());
    } catch (e) {
      return true;
    }
  }
}
```

### 3.4 Mettre à jour Auth Handler

**Modifié**: `bin/api/auth_handler.dart`

```dart
// REMPLACER la méthode _login complètement par:

Future<Response> _login(Request request) async {
  try {
    final payload = jsonDecode(await request.readAsString())
        as Map<String, dynamic>;
    final username = payload['username'] as String?;
    final password = payload['password'] as String?;

    if (username == null || password == null) {
      throw ValidationException(
        message: 'Username and password required',
      );
    }

    // Verify credentials avec bcrypt
    final user = db.verifyCredentials(username, password);
    if (user == null) {
      throw AuthException(
        message: 'Invalid credentials',
        code: 'INVALID_CREDENTIALS',
      );
    }

    // Generate tokens
    final jwtService = JwtService();
    final accessToken = jwtService.generateAccessToken(user);
    final refreshToken = jwtService.generateRefreshToken(user);

    // Create session
    final session = db.createSession(user.id, accessToken, refreshToken);

    return Response.ok(
      jsonEncode({
        'success': true,
        'user': user.toJson(),
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_in': 900, // 15 min
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } on AppException catch (e) {
    return Response(
      e.httpCode,
      body: jsonEncode({'success': false, 'error': e.toJson()}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    LoggingService().logError('Login error', e, StackTrace.current);
    return Response.internalServerError(
      body: jsonEncode({
        'success': false,
        'error': {'code': 'INTERNAL_ERROR', 'message': e.toString()}
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
```

---

## 4️⃣ DATABASE RELIABILITY (Jour 4-5)

### 4.1 Migrations System

**Fichier**: `bin/database/migrations.dart` (NEW)
```dart
final List<Migration> migrations = [
  Migration(
    version: 1,
    name: 'Initial schema',
    up: '''
      -- Users
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        is_admin INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      );

      -- Playlists
      CREATE TABLE IF NOT EXISTS playlists (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        server_url TEXT NOT NULL,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        dns TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      -- Sessions
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        access_token TEXT UNIQUE NOT NULL,
        refresh_token TEXT UNIQUE NOT NULL,
        expires_at TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      -- Indexes
      CREATE INDEX idx_sessions_token ON sessions(access_token);
      CREATE INDEX idx_sessions_expires ON sessions(expires_at);
      CREATE INDEX idx_playlists_user ON playlists(user_id);
    ''',
  ),
  Migration(
    version: 2,
    name: 'Add 2FA support',
    up: '''
      ALTER TABLE users ADD COLUMN totp_secret TEXT;
      ALTER TABLE users ADD COLUMN totp_enabled INTEGER DEFAULT 0;
    ''',
  ),
];

class Migration {
  final int version;
  final String name;
  final String up;
  final String? down;

  Migration({
    required this.version,
    required this.name,
    required this.up,
    this.down,
  });
}

class MigrationRunner {
  late Database _db;

  Future<void> init(Database db) async {
    _db = db;
    await _runMigrations();
  }

  Future<void> _runMigrations() async {
    // Get current schema version
    int currentVersion = 0;
    try {
      final result = _db.select('PRAGMA user_version');
      currentVersion = (result.first['user_version'] as int?) ?? 0;
    } catch (e) {
      // Table doesn't exist
      currentVersion = 0;
    }

    for (final migration in migrations) {
      if (migration.version > currentVersion) {
        print('Running migration v${migration.version}: ${migration.name}');
        _db.execute(migration.up);
        _db.execute('PRAGMA user_version = ${migration.version}');
      }
    }
  }
}
```

### 4.2 Backup Service

**Fichier**: `bin/services/backup_service.dart`
```dart
import 'dart:io';

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;

  BackupService._internal();

  Future<String> createBackup() async {
    final backupDir = Directory('/app/backups');
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupPath = '${backupDir.path}/xtremflow_$timestamp.db';

    try {
      final sourceDb = File('/app/data/xtremflow.db');
      await sourceDb.copy(backupPath);

      print('Backup created: $backupPath');
      return backupPath;
    } catch (e) {
      throw Exception('Backup failed: $e');
    }
  }

  Future<void> cleanOldBackups({int maxAge = 30}) async {
    final backupDir = Directory('/app/backups');
    if (!backupDir.existsSync()) return;

    final cutoff = DateTime.now().subtract(Duration(days: maxAge));

    await for (final file in backupDir.list()) {
      if (file is File && file.path.endsWith('.db')) {
        final stat = await file.stat();
        if (stat.modified.isBefore(cutoff)) {
          await file.delete();
          print('Deleted old backup: ${file.path}');
        }
      }
    }
  }
}
```

---

## 5️⃣ INTÉGRER DANS SERVER.DART

**Modifié**: `bin/server.dart` (top)

```dart
import 'services/logging_service.dart';
import 'middleware/error_handler.dart';
import 'middleware/logging_middleware.dart';
import 'services/jwt_service.dart';
import 'services/backup_service.dart';
import 'database/migrations.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8089')
    ..addOption('path', defaultsTo: '/app/web');

  final result = parser.parse(args);
  final port = int.parse(result['port']);
  final webPath = result['path'];

  final logger = LoggingService();
  logger.logInfo('Starting XtremFlow IPTV Server...');

  // Initialize database with migrations
  final db = AppDatabase();
  await db.init();
  final migrationRunner = MigrationRunner();
  await migrationRunner.init(db._db); // Access internal db
  await db.seedAdmin();

  // Backup daily
  final backupService = BackupService();
  Timer.periodic(const Duration(hours: 24), (_) async {
    await backupService.createBackup();
    await backupService.cleanOldBackups();
  });

  logger.logInfo('Database initialized');

  // ... rest of server setup (line 157+)

  // REMPLACER la Pipeline:
  final pipeline = const Pipeline()
      .addMiddleware(logRequests())  // Keep shelf's logRequests
      .addMiddleware(loggingMiddleware())  // Our custom logging
      .addMiddleware(errorHandlerMiddleware())  // Error handling
      .addMiddleware(securityHeadersMiddleware())
      .addMiddleware(honeypotMiddleware())
      .addMiddleware(rateLimitMiddleware())
      .addMiddleware(_corsMiddleware())
      .addHandler(handler);

  final server = await shelf_io.serve(
    pipeline,
    InternetAddress.anyIPv4,
    port,
  );

  logger.logInfo('Server started on port ${server.port}');
}
```

---

## 📋 CHECKLIST D'IMPLÉMENTATION

- [ ] Jour 1: Logger + LoggingService
- [ ] Jour 1: AppException hierarchy
- [ ] Jour 1: ErrorHandler middleware
- [ ] Jour 2: Bcrypt password hasher
- [ ] Jour 3: JWT service + token generation
- [ ] Jour 3: Auth handler update
- [ ] Jour 4: Migrations system
- [ ] Jour 5: Backup service
- [ ] Jour 5: Testing complet
- [ ] Integration dans server.dart
- [ ] Tests fonctionnels validant tout

---

## 🧪 TESTS À AJOUTER

```dart
// test/unit/auth_test.dart
void main() {
  test('Password hashing with bcrypt', () {
    final password = 'test123';
    final hash = PasswordHasher.hash(password);
    expect(PasswordHasher.verify(password, hash), isTrue);
    expect(PasswordHasher.verify('wrong', hash), isFalse);
  });

  test('JWT token generation and verification', () {
    final user = User(id: 'test', username: 'john', passwordHash: 'xxx');
    final jwt = JwtService();
    final token = jwt.generateAccessToken(user);
    final decoded = jwt.verifyToken(token);
    expect(decoded.payload['username'], 'john');
  });

  test('Token expiration check', () {
    final jwt = JwtService();
    // Create expired token
    expect(jwt.isTokenExpired('expired_token'), isTrue);
  });
}
```

---

*Ce guide fournit le code exact à implémenter pour la semaine 1*
