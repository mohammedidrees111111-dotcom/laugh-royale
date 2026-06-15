import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

enum WsMatchStatus {
  connected,
  searching,
  matched,
  connectionFailed,
  serverError,
  cancelled,
}

class WsGameService {
  WsGameService._();

  // ── State ──────────────────────────────────────────────────
  static WebSocket? _ws;
  static bool _connected = false;
  static String? _roomCode;
  static String? _playerId;
  static String? _playerRole;
  static String? _opponentId;
  static String? _opponentName;
  static bool _inQueue = false;
  static bool _cancelled = false;
  static Timer? _pingTimer;
  static String? _lastConnectedUrl;
  static Timer? _reconnectTimer;
  static int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  static bool get isConnected => _connected;
  static String? get roomCode => _roomCode;
  static String? get opponentId => _opponentId;
  static String? get opponentName => _opponentName;
  static bool get inQueue => _inQueue;

  static final _controller = StreamController<Map<String, dynamic>>.broadcast();
  static final _statusController = StreamController<WsMatchStatus>.broadcast();

  static Stream<Map<String, dynamic>> get messages => _controller.stream;
  static Stream<WsMatchStatus> get statusStream => _statusController.stream;

  // ── Connection Health Check ─────────────────────────────────

  static Future<bool> checkServerHealth({String? url}) async {
    final u = url ?? AppConfig.wsServerUrl;
    debugPrint('[WS] Checking server health at $u');
    final ok = await AppConfig.checkServerHealth(url: u);
    debugPrint('[WS] Health check → ${ok ? "OK" : "FAIL"}');
    return ok;
  }

  static Future<bool> tryConnect({String? url, List<String>? urls, int retries = 0}) async {
    final maxRetries = retries > 0 ? retries : AppConfig.wsMaxRetries;
    final candidates = urls ?? (url != null ? [url] : AppConfig.candidateWsUrls);

    for (final candidate in candidates) {
      debugPrint('[WS] === Trying $candidate ===');

      final isProduction = candidate.contains('onrender.com');

      if (isProduction) {
        debugPrint('[WS] Warming up Render server (health check)...');
        for (int warmup = 0; warmup < 12; warmup++) {
          final alive = await AppConfig.checkServerHealth(url: candidate);
          if (alive) {
            debugPrint('[WS] Render server is awake (warmup ${warmup + 1})');
            break;
          }
          if (warmup < 11) {
            debugPrint('[WS] Render cold start, waiting 5s...');
            await Future.delayed(const Duration(seconds: 5));
          }
        }
      }

      int attemptsLeft = maxRetries;
      while (attemptsLeft > 0) {
        final attempt = maxRetries - attemptsLeft + 1;
        try {
          _disposeSocket();
          _ws = await WebSocket.connect(candidate)
              .timeout(AppConfig.wsConnectTimeout);

          debugPrint('[WS] ✅ Connected to $candidate');
          _connected = true;
          _lastConnectedUrl = candidate;

          _ws!.listen(
            _onMessage,
            onDone: () {
              debugPrint('[WS] Connection closed');
              _connected = false;
              _inQueue = false;
              _onDisconnected();
            },
            onError: (e) {
              debugPrint('[WS] Connection error: $e');
              _connected = false;
              _inQueue = false;
              _onDisconnected();
            },
          );

          _startPing();
          return true;
        } on SocketException catch (e) {
          debugPrint('[WS] ❌ $candidate refused connection: $e');
          attemptsLeft = 0;
        } on TimeoutException {
          debugPrint('[WS] ⏳ $candidate timed out (attempt $attempt)');
          attemptsLeft--;
          if (attemptsLeft > 0) {
            debugPrint('[WS] Retrying in ${AppConfig.wsRetryDelay.inSeconds}s...');
            await Future.delayed(AppConfig.wsRetryDelay);
          }
        } on WebSocketException catch (e) {
          debugPrint('[WS] WebSocket error $candidate: $e');
          attemptsLeft--;
          if (attemptsLeft > 0) {
            await Future.delayed(AppConfig.wsRetryDelay);
          }
        } catch (e) {
          debugPrint('[WS] Unexpected error $candidate: $e');
          attemptsLeft--;
          if (attemptsLeft > 0) {
            await Future.delayed(AppConfig.wsRetryDelay);
          }
        }
      }

      debugPrint('[WS] Failed to connect to $candidate');
    }

    debugPrint('[WS] ❌ All URLs exhausted — server unreachable');
    _connected = false;
    _statusController.add(WsMatchStatus.connectionFailed);
    return false;
  }

  // ── Ping / keep-alive ───────────────────────────────────────

  static void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_ws != null && _ws!.readyState == WebSocket.open) {
        try { _ws!.add(jsonEncode({'type': 'ping'})); } catch (_) {}
      }
    });
  }

  // ── Auto-reconnect ──────────────────────────────────────────

  static void _onDisconnected() {
    if (_cancelled) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[WS] Max reconnect attempts reached');
      _statusController.add(WsMatchStatus.connectionFailed);
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    debugPrint('[WS] Scheduling reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts in ${delay.inSeconds}s');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => _attemptReconnect());
  }

  static Future<void> _attemptReconnect() async {
    if (_cancelled) return;

    final url = _lastConnectedUrl ?? AppConfig.wsServerUrl;
    debugPrint('[WS] Reconnecting to $url...');

    try {
      _disposeSocket();
      _ws = await WebSocket.connect(url).timeout(const Duration(seconds: 10));

      debugPrint('[WS] Reconnected!');
      _connected = true;
      _reconnectAttempts = 0;

      _ws!.listen(
        _onMessage,
        onDone: () {
          debugPrint('[WS] Reconnected socket closed');
          _connected = false;
          _onDisconnected();
        },
        onError: (e) {
          debugPrint('[WS] Reconnected socket error: $e');
          _connected = false;
          _onDisconnected();
        },
      );

      _startPing();

      if (_roomCode != null && _playerId != null) {
        debugPrint('[WS] Reconnecting to room $_roomCode as $_playerId');
        _send({
          'type': 'reconnect',
          'playerId': _playerId,
          'roomCode': _roomCode,
        });
      } else if (_inQueue && _playerId != null) {
        debugPrint('[WS] Rejoining matchmaking queue');
        _send({
          'type': 'matchmaking_join',
          'id': _playerId,
          'name': _opponentName ?? 'Player',
        });
      }
    } catch (e) {
      debugPrint('[WS] Reconnect failed: $e');
      _onDisconnected();
    }
  }

  // ── Matchmaking Queue ───────────────────────────────────────

  static Future<Map<String, dynamic>?> joinMatchmakingQueue({
    required String playerId,
    required String playerName,
    String? serverUrl,
  }) async {
    _dispose();
    _cancelled = false;
    _playerId = playerId;

    debugPrint('[WS] === joinMatchmakingQueue START ===');
    debugPrint('[WS] Player: $playerName ($playerId)');
    debugPrint('[WS] Server URL: ${serverUrl ?? AppConfig.wsServerUrl}');

    final connected = await tryConnect(urls: AppConfig.candidateWsUrls);
    if (!connected) {
      debugPrint('[WS] Cannot connect to server — matchmaking aborted');
      return null;
    }

    debugPrint('[WS] Connected. Sending matchmaking_join...');

    final rng = Random();
    await Future.delayed(Duration(milliseconds: rng.nextInt(200)));

    _send({
      'type': 'matchmaking_join',
      'id': playerId,
      'name': playerName,
    });

    final completer = Completer<Map<String, dynamic>?>();

    StreamSubscription? sub;
    sub = _controller.stream.listen((msg) {
      if (_cancelled && !completer.isCompleted) {
        completer.complete(null);
        return;
      }

      final type = msg['type'] as String?;

      if (type == 'queue_joined') {
        _inQueue = true;
        _statusController.add(WsMatchStatus.searching);
        debugPrint('[WS] Queue joined (size: ${msg['queueSize']})');
        return;
      }

      if (type == 'matched') {
        final roomId = msg['roomId'] as String?;
        final oppId = msg['opponentId'] as String?;
        final oppName = msg['opponentName'] as String?;
        final role = msg['role'] as String?;

        if (roomId == null || oppId == null) {
          debugPrint('[WS] Received matched but missing roomId/opponentId');
          return;
        }

        _roomCode = roomId;
        _opponentId = oppId;
        _opponentName = oppName ?? 'Player';
        _playerRole = role;
        _inQueue = false;

        debugPrint('[WS] === MATCHED ===');
        debugPrint('[WS] Room: $roomId');
        debugPrint('[WS] Opponent: $oppName ($oppId)');
        debugPrint('[WS] Role: $role');
        debugPrint('[WS] =================');

        _statusController.add(WsMatchStatus.matched);

        if (!completer.isCompleted) {
          completer.complete({
            'roomId': roomId,
            'opponentId': oppId,
            'opponentName': oppName,
            'role': role,
          });
        }
        return;
      }

      if (type == 'error') {
        debugPrint('[WS] Server error: ${msg['message']}');
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        return;
      }

      if (type == 'opponent_left') {
        debugPrint('[WS] Opponent left the room');
        _controller.add({'type': 'event', 'event': 'you_won'});
      }
    });

    final result = await completer.future;
    sub?.cancel();

    if (result == null) {
      debugPrint('[WS] joinMatchmakingQueue → NO MATCH');
    } else {
      debugPrint('[WS] joinMatchmakingQueue → MATCHED (room: ${result['roomId']})');
    }

    return result;
  }

  static void leaveMatchmakingQueue() {
    _cancelled = true;
    _inQueue = false;
    _send({'type': 'matchmaking_leave'});
    debugPrint('[WS] Left matchmaking queue');
  }

  // ── Room hosting / joining (manual code sharing) ───────────

  static Future<Map<String, dynamic>?> hostRoom({
    String? serverUrl,
    required String playerId,
  }) async {
    _dispose();
    final connected = await tryConnect(url: serverUrl);
    if (!connected) return null;

    _send({'type': 'host', 'id': playerId});
    debugPrint('[WS] Sent host request');

    final completer = Completer<Map<String, dynamic>?>();

    StreamSubscription? sub;
    sub = _controller.stream.listen((msg) {
      if (msg['type'] == 'room_created') {
        final code = msg['code'] as String?;
        if (code != null) {
          _roomCode = code;
          _playerRole = 'host';
          debugPrint('[WS] Room created: $code');
          if (!completer.isCompleted) {
            completer.complete({'code': code, 'status': 'waiting'});
          }
        }
      }
      if (msg['type'] == 'player_joined') {
        _opponentId = msg['id'] as String?;
        _opponentName = msg['name'] as String?;
        debugPrint('[WS] Player joined: $_opponentName');
      }
    });

    final result = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('[WS] hostRoom timed out');
        return null;
      },
    );

    sub?.cancel();
    return result;
  }

  static Future<bool> joinRoom({
    String? serverUrl,
    required String code,
    required String playerId,
    required String playerName,
  }) async {
    _dispose();
    final connected = await tryConnect(url: serverUrl);
    if (!connected) return false;

    _send({
      'type': 'join',
      'code': code,
      'id': playerId,
      'name': playerName,
    });
    debugPrint('[WS] Sent join request for room $code');

    final completer = Completer<bool>();

    StreamSubscription? sub;
    sub = _controller.stream.listen((msg) {
      if (msg['type'] == 'joined') {
        _roomCode = code;
        _playerRole = 'guest';
        _opponentId = msg['id'] as String?;
        _opponentName = msg['name'] as String?;
        debugPrint('[WS] Joined room $code');
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      }
      if (msg['type'] == 'error') {
        debugPrint('[WS] Join error: ${msg['message']}');
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      }
    });

    try {
      return await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[WS] joinRoom timed out');
          return false;
        },
      );
    } finally {
      sub?.cancel();
    }
  }

  // ── Message handling ────────────────────────────────────────

  static void _onMessage(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      debugPrint('[WS] ← $type');

      if (type == 'reconnected') {
        _roomCode = msg['roomId'] as String?;
        _playerRole = msg['role'] as String?;
        _opponentId = msg['opponentId'] as String?;
        _opponentName = msg['opponentName'] as String?;
        _connected = true;
        _inQueue = false;
        _reconnectAttempts = 0;
        debugPrint('[WS] Session recovered: room $_roomCode, role $_playerRole');
      }

      if (type == 'opponent_disconnected') {
        debugPrint('[WS] Opponent disconnected — waiting for reconnect');
      }

      _controller.add(msg);
    } catch (e) {
      debugPrint('[WS] Failed to parse message: $e');
    }
  }

  // ── Sending ─────────────────────────────────────────────────

  static void _send(Map<String, dynamic> msg) {
    if (_ws == null || _ws!.readyState != WebSocket.open) {
      debugPrint('[WS] Cannot send — socket not open (msg: ${msg['type']})');
      return;
    }
    try {
      _ws!.add(jsonEncode(msg));
      debugPrint('[WS] → ${msg['type']}');
    } catch (e) {
      debugPrint('[WS] Send error: $e');
    }
  }

  static void startGame() {
    _send({'type': 'start'});
    debugPrint('[WS] Game start signal sent');
  }

  static void sendSmile(double value) {
    _send({'type': 'smile', 'value': value});
  }

  static void sendFace(String base64) {
    _send({'type': 'face', 'data': base64});
  }

  static void sendGameEvent(String event) {
    _send({'type': 'event', 'event': event});
  }

  // ── Cleanup ─────────────────────────────────────────────────

  static void dispose() {
    _dispose();
  }

  static void _dispose() {
    leaveMatchmakingQueue();
    _cancelled = true;
    _connected = false;
    _inQueue = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _lastConnectedUrl = null;
    _playerRole = null;
    _opponentId = null;
    _opponentName = null;
    _disposeSocket();
    _roomCode = null;
    _playerId = null;
    debugPrint('[WS] Disposed');
  }

  static void _disposeSocket() {
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    _connected = false;
  }
}
