import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import 'firebase_service.dart';

enum MatchStatus { searching, matched, noInternet, serverError, cancelled }
enum _Backend { unknown, rtdb, firestore }

class FbOnlineService {
  FbOnlineService._();

  static const String _baseUrl = AppConfig.rtDbUrl;

  static _Backend _backend = _Backend.unknown;
  static Timer? _pollTimer;
  static String? _roomCode;
  static String? _playerId;
  static String? _role;
  static String? _opponentName;
  static bool _connected = false;
  static bool _started = false;
  static bool _reportedLoser = false;
  static bool _cancelled = false;

  static StreamSubscription? _firestoreQueueSub;
  static StreamSubscription? _firestoreRoomSub;

  static bool get isConnected => _connected;
  static String? get roomCode => _roomCode;
  static String? get opponentName => _opponentName;

  static final _controller = StreamController<Map<String, dynamic>>.broadcast();
  static final _statusController = StreamController<MatchStatus>.broadcast();
  static Stream<Map<String, dynamic>> get messages => _controller.stream;
  static Stream<MatchStatus> get statusStream => _statusController.stream;

  static FirebaseFirestore? get _db => FirebaseService.firestore;

  static Future<void> _detectBackend() async {
    if (_backend != _Backend.unknown) return;

    final online = await checkConnectivity();
    if (!online) {
      _backend = _Backend.rtdb;
      return;
    }

    try {
      final ok = await _rtdbGet(Uri.parse('$_baseUrl/.json?shallow=true'));
      if (ok != null) {
        _backend = _Backend.rtdb;
        debugPrint('MATCH: Backend → RTDB (reachable)');
        return;
      }
    } catch (_) {}

    if (_db != null) {
      _backend = _Backend.firestore;
      debugPrint('MATCH: Backend → Firestore (RTDB unreachable, Firestore available)');
      return;
    }

    _backend = _Backend.rtdb;
    debugPrint('MATCH: Backend → RTDB (default, may fail)');
  }

  static Future<String> createRoom({required String playerId, required String playerName}) async {
    _playerId = playerId;
    _role = 'host';
    _roomCode = _genCode();
    final body = jsonEncode({
      'hostId': playerId, 'hostName': playerName,
      'guestId': null, 'guestName': null,
      'hostSmile': 0.0, 'guestSmile': 0.0,
      'hostFace': '', 'guestFace': '',
      'status': 'waiting', 'started': false,
    });
    final res = await _httpPut(Uri.parse('$_baseUrl/rooms/$_roomCode.json'), body);
    if (res != null) { _connected = true; _startRtdbPolling(); }
    return _roomCode ?? '';
  }

  static Future<bool> joinRoom({required String code, required String playerId, required String playerName}) async {
    _dispose();
    _playerId = playerId;
    _role = 'guest';
    _roomCode = code;
    final url = Uri.parse('$_baseUrl/rooms/$code.json');
    final data = await _httpGet(url);
    if (data == null || data['status'] != 'waiting' || data['guestId'] != null) return false;
    final body = jsonEncode({...data, 'guestId': playerId, 'guestName': playerName, 'status': 'joined'});
    final res = await _httpPut(url, body);
    if (res != null) { _connected = true; _startRtdbPolling(); return true; }
    return false;
  }

  static Future<bool> checkConnectivity() async {
    try {
      final hasInterface = (await Connectivity().checkConnectivity()).any((r) => r != ConnectivityResult.none);
      if (!hasInterface) {
        debugPrint('MATCH: No network interface detected');
        return false;
      }
      final hasInternet = await _realInternetCheck();
      debugPrint('MATCH: Real internet check → $hasInternet');
      return hasInternet;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _realInternetCheck() async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final req = await client.openUrl('GET', Uri.parse('$_baseUrl/.json?shallow=true'))
          .timeout(const Duration(seconds: 3));
      req.headers.set('Cache-Control', 'no-cache');
      final res = await req.close().timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } on SocketException {
      debugPrint('MATCH: Real internet check → SocketException (no connectivity)');
      return false;
    } on TimeoutException {
      debugPrint('MATCH: Real internet check → timeout');
      return false;
    } catch (e) {
      debugPrint('MATCH: Real internet check error: $e');
      return false;
    } finally {
      client?.close();
    }
  }

  static Future<MatchStatus> joinQueue({required String playerId, required String playerName}) async {
    _dispose();
    _cancelled = false;
    _playerId = playerId;
    debugPrint('MATCH: $playerName joining queue (ID: $playerId)');

    final online = await checkConnectivity();
    if (!online) {
      debugPrint('MATCH: No internet — real reachability test failed');
      _statusController.add(MatchStatus.noInternet);
      return MatchStatus.noInternet;
    }

    await _detectBackend();

    if (_backend == _Backend.firestore) {
      debugPrint('MATCH: Using Firestore backend for queue');
      return await _firestoreJoinQueue(playerId: playerId, playerName: playerName);
    }

    debugPrint('MATCH: Using RTDB backend for queue');

    final queueUrl = Uri.parse('$_baseUrl/queue/$playerId.json');
    final entry = jsonEncode({'id': playerId, 'name': playerName, 'ts': DateTime.now().millisecondsSinceEpoch});

    int putRetries = 0;
    dynamic ok;
    while (putRetries < 3 && !_cancelled) {
      try {
        ok = await _httpPut(queueUrl, entry);
      } catch (e) {
        debugPrint('MATCH: PUT attempt $putRetries threw: $e');
      }
      if (ok != null) break;
      putRetries++;
      debugPrint('MATCH: PUT retry $putRetries/3');
      if (putRetries >= 3) break;
      await Future.delayed(Duration(seconds: 1 + putRetries));
    }

    if (ok == null) {
      debugPrint('MATCH: RTDB queue join failed, falling back to Firestore');
      _backend = _Backend.firestore;
      return await _firestoreJoinQueue(playerId: playerId, playerName: playerName);
    }

    debugPrint('MATCH: RTDB queue entry written');
    _statusController.add(MatchStatus.searching);

    int consecutiveFails = 0;
    const int maxConsecutiveFails = 12;

    while (!_cancelled) {
      await Future.delayed(const Duration(milliseconds: 500));

      Map<String, dynamic>? queueData;
      try {
        queueData = await _httpGet(Uri.parse('$_baseUrl/queue.json'));
      } catch (e) {
        queueData = null;
      }

      if (queueData == null) {
        consecutiveFails++;
        debugPrint('MATCH: GET queue failed ($consecutiveFails/$maxConsecutiveFails)');
        if (consecutiveFails >= maxConsecutiveFails) {
          debugPrint('MATCH: Too many consecutive failures');
          _statusController.add(MatchStatus.serverError);
          break;
        }
        continue;
      }
      consecutiveFails = 0;

      if (queueData is! Map || queueData.isEmpty) continue;

      final myEntry = queueData[playerId];
      if (myEntry is Map && myEntry.containsKey('matchedRoom')) {
        final matchedCode = myEntry['matchedRoom'] as String;
        final hostName = myEntry['hostName'] as String? ?? 'Player';
        debugPrint('MATCH: $playerName was matched by $hostName! Room: $matchedCode');
        await _httpDelete(Uri.parse('$_baseUrl/queue/$playerId.json'));
        _roomCode = matchedCode;
        _role = 'guest';
        _opponentName = hostName;
        _connected = true;
        _startRtdbPolling();
        _statusController.add(MatchStatus.matched);
        return MatchStatus.matched;
      }

      final entries = queueData.entries.where((e) => e.key != playerId).toList();
      if (entries.isEmpty) continue;

      final other = entries.first;
      final p2Id = other.key as String;
      final p2Name = (other.value is Map) ? (((other.value as Map)['name'] as String?) ?? 'Player') : 'Player';

      debugPrint('MATCH: Found opponent $p2Name ($p2Id), creating RTDB room');

      final code = _genCode();
      final roomBody = jsonEncode({
        'hostId': playerId, 'hostName': playerName,
        'guestId': p2Id, 'guestName': p2Name,
        'hostSmile': 0.0, 'guestSmile': 0.0,
        'hostFace': '', 'guestFace': '',
        'status': 'joined', 'started': false,
      });

      final roomRes = await _httpPut(Uri.parse('$_baseUrl/rooms/$code.json'), roomBody);
      if (roomRes == null) {
        debugPrint('MATCH: Failed to create room, retrying');
        continue;
      }

      await _httpPut(Uri.parse('$_baseUrl/queue/$p2Id.json'), jsonEncode({
        'id': p2Id, 'name': p2Name,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'matchedRoom': code,
        'hostName': playerName,
      }));
      await _httpDelete(Uri.parse('$_baseUrl/queue/$playerId.json'));

      _roomCode = code;
      _role = 'host';
      _opponentName = p2Name;
      _connected = true;
      _startRtdbPolling();
      debugPrint('MATCH: $playerName matched with $p2Name! Room: $code');
      _statusController.add(MatchStatus.matched);
      return MatchStatus.matched;
    }

    await _httpDelete(Uri.parse('$_baseUrl/queue/$playerId.json'));
    if (_cancelled) {
      debugPrint('MATCH: Search cancelled by user');
      _statusController.add(MatchStatus.cancelled);
    }
    return _cancelled ? MatchStatus.cancelled : MatchStatus.serverError;
  }

  static Future<MatchStatus> _firestoreJoinQueue({required String playerId, required String playerName}) async {
    if (_db == null) {
      debugPrint('MATCH: Firestore not available');
      _statusController.add(MatchStatus.serverError);
      return MatchStatus.serverError;
    }

    try {
      await _db!.collection('matchmaking_queue').doc(playerId).set({
        'id': playerId,
        'name': playerName,
        'ts': FieldValue.serverTimestamp(),
        'status': 'waiting',
      });
      debugPrint('MATCH: Firestore queue entry created');
    } catch (e) {
      debugPrint('MATCH: Firestore queue write failed: $e');
      _statusController.add(MatchStatus.serverError);
      return MatchStatus.serverError;
    }

    _statusController.add(MatchStatus.searching);

    final completer = Completer<MatchStatus>();
    bool _alreadyMatched = false;

    _firestoreQueueSub = _db!.collection('matchmaking_queue')
        .where('status', isEqualTo: 'waiting')
        .snapshots()
        .listen((snapshot) async {
      if (_cancelled || _alreadyMatched) {
        if (!completer.isCompleted) completer.complete(MatchStatus.cancelled);
        return;
      }

      final myDoc = snapshot.docs.where((d) => d.id == playerId).firstOrNull;
      if (myDoc != null) {
        final myData = myDoc.data();
        if (myData['status'] == 'matched' && myData.containsKey('matchedRoom')) {
          _alreadyMatched = true;
          final matchedCode = myData['matchedRoom'] as String;
          final hostName = (myData['hostName'] as String?) ?? 'Player';
          debugPrint('MATCH: $playerName matched via Firestore by $hostName! Room: $matchedCode');
          await _db!.collection('matchmaking_queue').doc(playerId).delete();
          _roomCode = matchedCode;
          _role = 'guest';
          _opponentName = hostName;
          _connected = true;
          _startFirestorePolling();
          if (!completer.isCompleted) {
            _statusController.add(MatchStatus.matched);
            completer.complete(MatchStatus.matched);
          }
          return;
        }
      }

      final others = snapshot.docs.where((d) => d.id != playerId).toList();
      if (others.isEmpty) return;

      final other = others.first;
      final p2Id = other.id;
      final p2Data = other.data();

      if (p2Data['status'] == 'matched') return;

      final p2Name = (p2Data['name'] as String?) ?? 'Player';

      debugPrint('MATCH: Firestore found opponent $p2Name ($p2Id), creating room');

      _alreadyMatched = true;

      final code = _genCode();
      final roomRef = _db!.collection('matchmaking_rooms').doc(code);

      try {
        await roomRef.set({
          'hostId': playerId,
          'hostName': playerName,
          'guestId': p2Id,
          'guestName': p2Name,
          'hostSmile': 0.0,
          'guestSmile': 0.0,
          'hostFace': '',
          'guestFace': '',
          'status': 'joined',
          'started': false,
          'loser': null,
          'event': null,
          'eventBy': null,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await _db!.collection('matchmaking_queue').doc(p2Id).update({
          'status': 'matched',
          'matchedRoom': code,
          'hostName': playerName,
        });
        await _db!.collection('matchmaking_queue').doc(playerId).delete();

        _roomCode = code;
        _role = 'host';
        _opponentName = p2Name;
        _connected = true;
        _startFirestorePolling();
        debugPrint('MATCH: Firestore room $code created, $playerName vs $p2Name');
        if (!completer.isCompleted) {
          _statusController.add(MatchStatus.matched);
          completer.complete(MatchStatus.matched);
        }
      } catch (e) {
        debugPrint('MATCH: Firestore room creation failed: $e');
        _alreadyMatched = false;
      }
    }, onError: (e) {
      debugPrint('MATCH: Firestore queue listener error: $e');
      if (!completer.isCompleted) {
        _statusController.add(MatchStatus.serverError);
        completer.complete(MatchStatus.serverError);
      }
    });

    final result = await completer.future;

    if (_cancelled && !completer.isCompleted) {
      await _db!.collection('matchmaking_queue').doc(playerId).delete();
    }

    return result;
  }

  static Future<void> _startFirestorePolling() async {
    if (_roomCode == null || _db == null) return;
    _firestoreRoomSub?.cancel();
    _firestoreRoomSub = _db!.collection('matchmaking_rooms').doc(_roomCode!).snapshots().listen((doc) {
      _processFirestoreSnapshot(doc.data());
    });
    debugPrint('MATCH: Firestore room listener started for $_roomCode');
  }

  static void _processFirestoreSnapshot(Map<String, dynamic>? data) {
    if (data == null) return;

    final oppSmileField = _role == 'host' ? 'guestSmile' : 'hostSmile';
    final oppFaceField = _role == 'host' ? 'guestFace' : 'hostFace';

    final oppSmile = (data[oppSmileField] as num?)?.toDouble() ?? 0.0;
    final oppFace = data[oppFaceField] as String?;
    final started = data['started'] == true;
    final loser = data['loser'] as String?;
    final event = data['event'] as String?;
    final eventBy = data['eventBy'] as String?;

    if (started && !_started) {
      _started = true;
      _controller.add({'type': 'event', 'event': 'started'});
      debugPrint('MATCH: Game started in room $_roomCode');
    }

    if (loser != null && loser.isNotEmpty && !_reportedLoser) {
      _reportedLoser = true;
      if (loser == _playerId) {
        _controller.add({'type': 'event', 'event': 'you_lost'});
      } else {
        _controller.add({'type': 'event', 'event': 'you_won'});
      }
    }

    if (event != null && event.isNotEmpty && eventBy != _playerId) {
      _controller.add({'type': 'event', 'event': event});
    }

    _controller.add({'type': 'smile', 'value': oppSmile});
    if (oppFace != null && oppFace is String && oppFace.length > 50) {
      _controller.add({'type': 'face', 'data': oppFace});
    }
  }

  static Future<bool> reportLaugh({required String playerId}) async {
    if (_roomCode == null) return false;

    if (_backend == _Backend.firestore) {
      return await _firestoreReportLaugh(playerId: playerId);
    }

    final url = Uri.parse('$_baseUrl/rooms/$_roomCode/loser.json');
    final existing = await _httpGet(url);
    if (existing != null) return false;
    final res = await _httpPut(url, jsonEncode(playerId));
    return res != null;
  }

  static Future<bool> _firestoreReportLaugh({required String playerId}) async {
    if (_roomCode == null || _db == null) return false;
    try {
      await _db!.runTransaction((tx) async {
        final ref = _db!.collection('matchmaking_rooms').doc(_roomCode!);
        final doc = await tx.get(ref);
        if (!doc.exists) return;
        final data = doc.data();
        if (data == null) return;
        if (data['loser'] != null) return;
        final hostId = data['hostId'];
        final guestId = data['guestId'];
        final loserId = playerId;
        final winnerId = (playerId == hostId) ? guestId : hostId;
        tx.update(ref, {
          'loser': loserId,
          'winner': winnerId,
          'status': 'finished',
        });
      });
      debugPrint('MATCH: Firestore laugh reported, loser=$playerId');
      return true;
    } catch (e) {
      debugPrint('MATCH: Firestore reportLaugh error: $e');
      return false;
    }
  }

  static void startGame() {
    if (_roomCode == null) return;

    if (_backend == _Backend.firestore) {
      if (_db != null) {
        _db!.collection('matchmaking_rooms').doc(_roomCode!).update({'started': true});
      }
      return;
    }

    _httpPut(Uri.parse('$_baseUrl/rooms/$_roomCode/started.json'), 'true');
  }

  static void sendSmile(double value) {
    if (_roomCode == null) return;

    if (_backend == _Backend.firestore) {
      final field = _role == 'host' ? 'hostSmile' : 'guestSmile';
      _db?.collection('matchmaking_rooms').doc(_roomCode!).update({field: value});
      return;
    }

    final field = _role == 'host' ? 'hostSmile' : 'guestSmile';
    _httpPut(Uri.parse('$_baseUrl/rooms/$_roomCode/$field.json'), jsonEncode(value));
  }

  static void sendFace(String base64) {
    if (_roomCode == null) return;

    if (_backend == _Backend.firestore) {
      final field = _role == 'host' ? 'hostFace' : 'guestFace';
      _db?.collection('matchmaking_rooms').doc(_roomCode!).update({field: base64});
      return;
    }

    final field = _role == 'host' ? 'hostFace' : 'guestFace';
    _httpPut(Uri.parse('$_baseUrl/rooms/$_roomCode/$field.json'), jsonEncode(base64));
  }

  static void sendGameEvent(String event) {
    if (_roomCode == null) return;

    if (_backend == _Backend.firestore) {
      _db?.collection('matchmaking_rooms').doc(_roomCode!).update({
        'event': event,
        'eventBy': _playerId,
      });
      return;
    }

    _httpPut(Uri.parse('$_baseUrl/rooms/$_roomCode/event.json'), jsonEncode({'e': event, 'by': _playerId}));
  }

  static void _startRtdbPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) => _rtdbPoll());
  }

  static Future<void> _rtdbPoll() async {
    if (_roomCode == null) return;
    final url = Uri.parse('$_baseUrl/rooms/$_roomCode.json');
    final data = await _httpGet(url);
    if (data == null) return;

    final oppSmileField = _role == 'host' ? 'guestSmile' : 'hostSmile';
    final oppFaceField = _role == 'host' ? 'guestFace' : 'hostFace';
    final oppSmile = (data[oppSmileField] as num?)?.toDouble() ?? 0.0;
    final oppFace = data[oppFaceField] as String?;
    final started = data['started'] == true;
    if (started && !_started) {
      _started = true;
      _controller.add({'type': 'event', 'event': 'started'});
      debugPrint('MATCH: Game started in room $_roomCode');
    }

    final loser = data['loser'] as String?;
    if (loser != null && loser.isNotEmpty && !_reportedLoser) {
      _reportedLoser = true;
      if (loser == _playerId) {
        _controller.add({'type': 'event', 'event': 'you_lost'});
      } else {
        _controller.add({'type': 'event', 'event': 'you_won'});
      }
    }

    final event = data['event'];
    if (event is Map && event.containsKey('by') && event['by'] != _playerId) {
      _controller.add({'type': 'event', 'event': event['e']});
    }

    _controller.add({'type': 'smile', 'value': oppSmile});
    if (oppFace != null && oppFace is String && oppFace.length > 50) {
      _controller.add({'type': 'face', 'data': oppFace});
    }
  }

  static void dispose() { _dispose(); }

  static void _dispose() {
    _cancelled = true;
    if (_playerId != null) {
      _httpDelete(Uri.parse('$_baseUrl/queue/$_playerId.json'));
      if (_backend == _Backend.firestore && _db != null) {
        _db!.collection('matchmaking_queue').doc(_playerId!).delete().catchError((_) {});
      }
    }
    _firestoreQueueSub?.cancel();
    _firestoreQueueSub = null;
    _firestoreRoomSub?.cancel();
    _firestoreRoomSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _roomCode = null;
    _connected = false;
    _started = false;
    _reportedLoser = false;
    _opponentName = null;

    if (_backend == _Backend.firestore && _roomCode == null && _playerId == null) {
      _backend = _Backend.unknown;
    }
  }

  static String _genCode() {
    const c = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => c[Random().nextInt(c.length)]).join();
  }

  static Future<dynamic> _httpGet(Uri url) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(url).timeout(const Duration(seconds: 8));
      req.headers.set('Cache-Control', 'no-cache');
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        if (body == 'null' || body.isEmpty) return null;
        return jsonDecode(body);
      }
      debugPrint('HTTP GET ${res.statusCode} for $url');
    } on SocketException catch (e) {
      debugPrint('HTTP GET SocketException: $e');
    } on TimeoutException catch (e) {
      debugPrint('HTTP GET timeout: $e');
    } catch (e) {
      debugPrint('HTTP GET error: $e');
    } finally {
      client?.close();
    }
    return null;
  }

  static Future<dynamic> _httpPut(Uri url, String body) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final req = await client.putUrl(url).timeout(const Duration(seconds: 8));
      req.headers.contentType = ContentType.json;
      req.headers.set('Content-Length', body.length.toString());
      req.write(body);
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return res;
      debugPrint('HTTP PUT ${res.statusCode} for $url');
    } on SocketException catch (e) {
      debugPrint('HTTP PUT SocketException: $e');
    } on TimeoutException catch (e) {
      debugPrint('HTTP PUT timeout: $e');
    } catch (e) {
      debugPrint('HTTP PUT error: $e');
    } finally {
      client?.close();
    }
    return null;
  }

  static Future<void> _httpDelete(Uri url) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final req = await client.deleteUrl(url).timeout(const Duration(seconds: 3));
      await req.close().timeout(const Duration(seconds: 3));
    } catch (_) {}
    finally { client?.close(); }
  }

  static Future<dynamic> _rtdbGet(Uri url) async {
    return _httpGet(url);
  }
}
