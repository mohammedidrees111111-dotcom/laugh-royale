import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ErrorHandler {
  ErrorHandler._();

  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      logError('FlutterError', details.exception, details.stack);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      logError('PlatformDispatcher Error', error, stack);
      return true;
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      return const SizedBox.shrink();
    };
  }

  static void logError(String source, Object? error, StackTrace? stack) {
    final ts = DateTime.now().toIso8601String();
    debugPrint('[$ts] ERROR [$source]: $error');

    if (stack != null) {
      debugPrint('Stack trace: $stack');
    }
  }

  static void logZoneError(Object error, StackTrace stack) {
    logError('Zone Error', error, stack);
  }

  static Future<bool> isConnected() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  static Future<bool> hasRealInternet({Uri? testUrl}) async {
    final hasInterface = await isConnected();
    if (!hasInterface) {
      debugPrint('NET: No network interface');
      return false;
    }

    final url = testUrl ?? Uri.parse('https://www.google.com/generate_204');
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final req = await client.openUrl('GET', url).timeout(const Duration(seconds: 3));
      req.headers.set('Cache-Control', 'no-cache');
      final res = await req.close().timeout(const Duration(seconds: 3));
      debugPrint('NET: Reachability test → ${res.statusCode}');
      return true;
    } on SocketException {
      debugPrint('NET: Reachability test → SocketException (offline)');
      return false;
    } on TimeoutException {
      debugPrint('NET: Reachability test → timeout');
      return false;
    } catch (e) {
      debugPrint('NET: Reachability test error: $e');
      return false;
    } finally {
      client?.close();
    }
  }

  static Future<T?> safeAsync<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e, stack) {
      logError('safeAsync', e, stack);
      return null;
    }
  }

  static T? safeSync<T>(T Function() fn) {
    try {
      return fn();
    } catch (e, stack) {
      logError('safeSync', e, stack);
      return null;
    }
  }
}
