import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase_options.dart';
import 'error_handler.dart';

class FirebaseService {
  FirebaseService._();

  static FirebaseApp? _app;
  static bool _initialized = false;
  static bool _available = false;

  static bool get isInitialized => _initialized;
  static bool get isAvailable => _available;
  static FirebaseApp? get app => _app;
  static String? _firebaseError;

  static String? get firebaseError => _firebaseError;

  static Future<bool> safeInitialize() async {
    if (_initialized) return _available;

    try {
      _app = await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 10));
      _available = true;
      _firebaseError = null;
      debugPrint('FIREBASE CONNECTED - REAL MULTIPLAYER ACTIVE');
    } catch (e, stack) {
      ErrorHandler.logError('Firebase init failed', e, stack);
      _available = false;
      _firebaseError = e.toString();
      debugPrint('FIREBASE FAILED: $e');
    }

    _initialized = true;
    return _available;
  }

  static FirebaseFirestore? get firestore {
    if (!_available) return null;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }
}
