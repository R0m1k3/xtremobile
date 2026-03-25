import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Benchmark for Hive encryption performance impact
class HiveEncryptionBenchmark {
  static final _results = <String, EncryptionBenchmarkResult>[];

  /// Run encryption overhead benchmark
  static Future<void> runBenchmark({
    int writeCount = 1000,
    int readCount = 1000,
    String valueSize = 'medium', // small, medium, large
  }) async {
    if (kDebugMode) {
      print('\n' + ('=' * 60));
      print('🔐 HIVE ENCRYPTION BENCHMARK');
      print('=' * 60);
      print('Write Operations: $writeCount');
      print('Read Operations: $readCount');
      print('Value Size: $valueSize');
      print('=' * 60 + '\n');
    }

    // Generate test data
    final testValue = _generateTestValue(valueSize);

    try {
      // Scenario 1: Unencrypted writes & reads
      await _benchmarkUnencrypted(writeCount, readCount, testValue);

      // Scenario 2: Encrypted writes & reads
      await _benchmarkEncrypted(writeCount, readCount, testValue);

      // Print comparison
      _printComparison();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Benchmark error: $e');
      }
    }
  }

  static Future<void> _benchmarkUnencrypted(
      int writes, int reads, String testValue) async {
    const boxName = 'benchmark_unencrypted';
    try {
      // Clean up if exists
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).deleteFromDisk();
      }

      final box = await Hive.openBox<String>(boxName);

      // Write benchmark
      final writeStop = Stopwatch()..start();
      for (int i = 0; i < writes; i++) {
        await box.put('key_$i', testValue);
      }
      writeStop.stop();

      // Read benchmark
      final readStop = Stopwatch()..start();
      for (int i = 0; i < reads; i++) {
        await box.get('key_${i % writes}');
      }
      readStop.stop();

      // Delete benchmark
      final deleteStop = Stopwatch()..start();
      await box.deleteFromDisk();
      deleteStop.stop();

      final result = EncryptionBenchmarkResult(
        name: 'Unencrypted (Hive)',
        writeTimeMs: writeStop.elapsedMilliseconds,
        readTimeMs: readStop.elapsedMilliseconds,
        deleteTimeMs: deleteStop.elapsedMilliseconds,
        operationCount: writes,
      );

      _results.add(result);

      if (kDebugMode) {
        print('\n📝 UNENCRYPTED RESULTS:');
        result.print();
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Unencrypted benchmark failed: $e');
      }
    }
  }

  static Future<void> _benchmarkEncrypted(
      int writes, int reads, String testValue) async {
    const boxName = 'benchmark_encrypted';
    try {
      // Clean up if exists
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).deleteFromDisk();
      }

      final encryptionKey = Hive.generateSecureKey();

      final box = await Hive.openBox<String>(
        boxName,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );

      // Write benchmark
      final writeStop = Stopwatch()..start();
      for (int i = 0; i < writes; i++) {
        await box.put('key_$i', testValue);
      }
      writeStop.stop();

      // Read benchmark
      final readStop = Stopwatch()..start();
      for (int i = 0; i < reads; i++) {
        await box.get('key_${i % writes}');
      }
      readStop.stop();

      // Delete benchmark
      final deleteStop = Stopwatch()..start();
      await box.deleteFromDisk();
      deleteStop.stop();

      final result = EncryptionBenchmarkResult(
        name: 'Encrypted (AES-256)',
        writeTimeMs: writeStop.elapsedMilliseconds,
        readTimeMs: readStop.elapsedMilliseconds,
        deleteTimeMs: deleteStop.elapsedMilliseconds,
        operationCount: writes,
      );

      _results.add(result);

      if (kDebugMode) {
        print('\n🔐 ENCRYPTED RESULTS:');
        result.print();
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Encrypted benchmark failed: $e');
      }
    }
  }

  static void _printComparison() {
    if (_results.length >= 2) {
      final unenc = _results[0];
      final enc = _results[1];

      final writeOverhead = ((enc.writeTimeMs / unenc.writeTimeMs - 1) * 100);
      final readOverhead = ((enc.readTimeMs / unenc.readTimeMs - 1) * 100);

      if (kDebugMode) {
        print('\n' + ('=' * 60));
        print('📊 PERFORMANCE COMPARISON');
        print('=' * 60);
        print('\nWrite Performance:');
        print(
            '  Unencrypted: ${unenc.writeTimeMs}ms (${(unenc.writeTimeMs / unenc.operationCount).toStringAsFixed(2)}µs/op)');
        print(
            '  Encrypted:   ${enc.writeTimeMs}ms (${(enc.writeTimeMs / enc.operationCount).toStringAsFixed(2)}µs/op)');
        print('  Overhead:    ${writeOverhead.toStringAsFixed(1)}%');

        print('\nRead Performance:');
        print(
            '  Unencrypted: ${unenc.readTimeMs}ms (${(unenc.readTimeMs / unenc.operationCount).toStringAsFixed(2)}µs/op)');
        print(
            '  Encrypted:   ${enc.readTimeMs}ms (${(enc.readTimeMs / enc.operationCount).toStringAsFixed(2)}µs/op)');
        print('  Overhead:    ${readOverhead.toStringAsFixed(1)}%');

        // Status
        const acceptableThreshold = 25.0;
        final writeStatus = writeOverhead > acceptableThreshold ? '⚠️' : '✅';
        final readStatus = readOverhead > acceptableThreshold ? '⚠️' : '✅';

        print('\nStatus:');
        print('  $writeStatus Write overhead: ${writeOverhead.toStringAsFixed(1)}% (target: <$acceptableThreshold%)');
        print('  $readStatus Read overhead: ${readOverhead.toStringAsFixed(1)}% (target: <$acceptableThreshold%)');
        print('=' * 60 + '\n');
      }
    }
  }

  static String _generateTestValue(String size) {
    final base = 'test_value_' * 10;
    switch (size) {
      case 'small':
        return base;
      case 'large':
        return base * 100;
      default:
        return base * 10;
    }
  }

  static List<Map<String, dynamic>> toJson() {
    return _results.map((r) => r.toJson()).toList();
  }

  static void reset() {
    _results.clear();
  }
}

/// Result of a single benchmark run
class EncryptionBenchmarkResult {
  final String name;
  final int writeTimeMs;
  final int readTimeMs;
  final int deleteTimeMs;
  final int operationCount;

  EncryptionBenchmarkResult({
    required this.name,
    required this.writeTimeMs,
    required this.readTimeMs,
    required this.deleteTimeMs,
    required this.operationCount,
  });

  double get writePerOpUs => (writeTimeMs * 1000.0) / operationCount;
  double get readPerOpUs => (readTimeMs * 1000.0) / operationCount;

  void print() {
    print('  Name: $name');
    print('  Write: ${writeTimeMs}ms (${writePerOpUs.toStringAsFixed(2)}µs/op)');
    print('  Read: ${readTimeMs}ms (${readPerOpUs.toStringAsFixed(2)}µs/op)');
    print('  Delete: ${deleteTimeMs}ms');
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'writeTimeMs': writeTimeMs,
      'readTimeMs': readTimeMs,
      'deleteTimeMs': deleteTimeMs,
      'operationCount': operationCount,
      'writePerOpUs': writePerOpUs,
      'readPerOpUs': readPerOpUs,
    };
  }
}
