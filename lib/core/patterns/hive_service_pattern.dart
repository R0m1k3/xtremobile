import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';

/// Base pattern for Hive-based services
/// Provides a template for implementing persistent storage with Hive
abstract class HiveServiceBase<T> {
  late Box<T> box;
  final String boxName;
  final bool encrypted;
  List<int>? encryptionKey;

  HiveServiceBase({
    required this.boxName,
    this.encrypted = false,
    this.encryptionKey,
  });

  /// Initialize the Hive box
  Future<void> init() async {
    try {
      if (Hive.isBoxOpen(boxName)) {
        box = Hive.box<T>(boxName);
      } else {
        if (encrypted && encryptionKey != null) {
          box = await Hive.openBox<T>(
            boxName,
            encryptionCipher: HiveAesCipher(encryptionKey!),
          );
        } else {
          box = await Hive.openBox<T>(boxName);
        }
      }
      if (kDebugMode) {
        print('✅ Hive box initialized: $boxName');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to init Hive box $boxName: $e');
      }
      rethrow;
    }
  }

  /// Get a value from the box
  Future<T?> get(String key) async {
    try {
      return box.get(key);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting $key from $boxName: $e');
      }
      return null;
    }
  }

  /// Put a value in the box
  Future<void> put(String key, T value) async {
    try {
      await box.put(key, value);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error putting $key to $boxName: $e');
      }
      rethrow;
    }
  }

  /// Delete a value from the box
  Future<void> delete(String key) async {
    try {
      await box.delete(key);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error deleting $key from $boxName: $e');
      }
      rethrow;
    }
  }

  /// Clear all values from the box
  Future<void> clear() async {
    try {
      await box.clear();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error clearing $boxName: $e');
      }
      rethrow;
    }
  }

  /// Get all values from the box
  List<T> getAll() {
    try {
      return box.values.toList();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting all from $boxName: $e');
      }
      return [];
    }
  }

  /// Close the box
  Future<void> close() async {
    try {
      await box.close();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error closing $boxName: $e');
      }
    }
  }
}
