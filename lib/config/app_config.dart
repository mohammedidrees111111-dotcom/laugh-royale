import 'dart:io';
import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static const String appName = 'Laugh Royale';
  static const String packageName = 'com.laughroyale.app';
  static const String version = '1.0.0';

  static const String rtDbUrl =
      'https://laugh-royale-default-rtdb.europe-west1.firebasedatabase.app';

  // ── Server URLs (tried in order) ────────────────────────────

  static const String _productionUrl =
      'wss://laugh-royale-server.onrender.com';

  static String? _overrideWsUrl;

  static void setWsServerUrl(String url) {
    _overrideWsUrl = url;
  }

  static void useProductionUrl() {
    _overrideWsUrl = _productionUrl;
  }

  static List<String> get _candidateWsUrls {
    final candidates = <String>[];

    if (_overrideWsUrl != null) {
      candidates.add(_overrideWsUrl!);
    }

    if (kIsWeb) {
      candidates.add('ws://localhost:3000');
    } else if (Platform.isAndroid) {
      candidates.add('ws://10.0.2.2:3000');
      candidates.add('ws://localhost:3000');
    } else if (Platform.isIOS) {
      candidates.add('ws://localhost:3000');
    } else {
      candidates.add('ws://localhost:3000');
    }

    final localIp = _localIp;
    if (localIp != null) {
      final subnet = localIp.substring(0, localIp.lastIndexOf('.'));
      candidates.add('ws://$subnet.1:3000');
    }

    return candidates;
  }

  static String get wsServerUrl => _candidateWsUrls.first;

  static String? _localIp;
  static String? get localIp => _localIp;

  static Future<void> detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.address.startsWith('127.')) {
            _localIp = addr.address;
            return;
          }
        }
      }
    } catch (_) {}
  }

  static bool get _isEmulator {
    try {
      return Platform.environment.containsKey('ANDROID_EMULATOR') ||
          Platform.localHostname.contains('emulator');
    } catch (_) {
      return false;
    }
  }

  static bool get isEmulator => _isEmulator;

  // ── Connection health ───────────────────────────────────────

  static Future<bool> checkServerHealth({String? url}) async {
    final base = url ?? wsServerUrl;
    final healthUrl = base
        .replaceFirst('ws://', 'http://')
        .replaceFirst('wss://', 'https://');

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final req = await client
          .getUrl(Uri.parse('$healthUrl/health'))
          .timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      client.close();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[CONFIG] Health check failed for $healthUrl: $e');
      return false;
    }
  }

  // ── Timeouts ────────────────────────────────────────────────

  static const Duration apiTimeout = Duration(seconds: 15);
  static const Duration cacheDuration = Duration(hours: 1);
  static const Duration wsConnectTimeout = Duration(seconds: 8);
  static const Duration wsRetryDelay = Duration(seconds: 2);
  static const int wsMaxRetries = 5;
  static const Duration healthCheckTimeout = Duration(seconds: 3);

  // ── Limits ──────────────────────────────────────────────────

  static const int maxFeedItems = 50;
  static const int maxImageSizeMb = 10;
}
