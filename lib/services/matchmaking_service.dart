import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'error_handler.dart';
import 'firebase_service.dart';

class MatchmakingService {
  MatchmakingService._();

  static const String _collection = 'match_rooms';

  static String? _currentRoomId;
  static StreamSubscription? _roomSub;
  static VoidCallback? _onMatchFound;
  static bool _isSearching = false;

  static String? get currentRoomId => _currentRoomId;
  static bool get isSearching => _isSearching;

  static FirebaseFirestore? get _db => FirebaseService.firestore;
  static bool get isOnline => FirebaseService.isAvailable;

  static Future<void> searchRandomMatch({
    required String playerId,
    required String playerName,
    required String country,
    required VoidCallback onMatchFound,
    required void Function(String opponent) onOpponentJoined,
  }) async {
    cancelSearch();

    if (_db == null) {
      throw Exception('Firebase not available. Real multiplayer requires Firebase.');
    }

    _isSearching = true;
    final roomsRef = _db!.collection(_collection);

    for (int attempt = 0; attempt < 6; attempt++) {
      if (attempt > 0) await Future.delayed(const Duration(seconds: 1));

      final waitingSnapshot = await roomsRef
          .where('status', isEqualTo: 'waiting')
          .where('isPrivate', isEqualTo: false)
          .limit(5)
          .get();

      for (final doc in waitingSnapshot.docs) {
        final data = doc.data();
        final p1Id = data['player1Id'] as String?;
        final p2Id = data['player2Id'] as String?;

        if (p2Id != null) continue;
        if (p1Id == null || p1Id == playerId) continue;

        final roomId = doc.id;
        final p1Name = data['player1Name'] as String? ?? 'Player';

        try {
          await doc.reference.update({
            'player2Id': playerId,
            'player2Name': playerName,
            'player2Country': country,
            'status': 'playing',
            'matchedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {
          continue;
        }

        _currentRoomId = roomId;
        _isSearching = false;
        onOpponentJoined(p1Name);
        onMatchFound();
        return;
      }
    }

    final roomRef = roomsRef.doc();
    _currentRoomId = roomRef.id;
    await roomRef.set({
      'roomId': roomRef.id,
      'player1Id': playerId,
      'player1Name': playerName,
      'player1Country': country,
      'player2Id': null,
      'player2Name': null,
      'player2Country': null,
      'status': 'waiting',
      'isPrivate': false,
      'createdAt': FieldValue.serverTimestamp(),
      'winner': null,
      'loser': null,
    });

    _listenForMatch(roomId: roomRef.id, playerId: playerId, onMatchFound: onMatchFound);
  }

  static void _listenForMatch({
    required String roomId,
    required String playerId,
    required VoidCallback onMatchFound,
  }) {
    _roomSub?.cancel();
    _roomSub = _db!.collection(_collection).doc(roomId).snapshots().listen((doc) {
      if (!_isSearching) return;
      final data = doc.data();
      if (data == null) return;
      final status = data['status'] as String?;
      final p2Id = data['player2Id'] as String?;

      if (status == 'playing' && p2Id != null && p2Id != playerId) {
        _isSearching = false;
        _onMatchFound = onMatchFound;
        _currentRoomId = roomId;
        onMatchFound();
      }
    });
  }

  static Future<String> createPrivateRoom({
    required String playerId,
    required String playerName,
    required String country,
  }) async {
    cancelSearch();

    if (_db == null) {
      throw Exception('Firebase not available. Cannot create room.');
    }

    final code = _generateCode();
    final roomsRef = _db!.collection(_collection);

    final existing = await roomsRef.where('roomCode', isEqualTo: code).limit(1).get();
    final finalCode = existing.docs.isEmpty ? code : _generateCode();

    _currentRoomId = finalCode;

    await roomsRef.doc(finalCode).set({
      'roomId': finalCode,
      'roomCode': finalCode,
      'player1Id': playerId,
      'player1Name': playerName,
      'player1Country': country,
      'player2Id': null,
      'player2Name': null,
      'player2Country': null,
      'status': 'waiting',
      'isPrivate': true,
      'createdAt': FieldValue.serverTimestamp(),
      'winner': null,
      'loser': null,
    });

    return finalCode;
  }

  static void listenToRoom({
    required String roomCode,
    required VoidCallback onOpponentJoined,
    required void Function(String opponentId, String opponentName) onReady,
  }) {
    cancelSearch();
    _currentRoomId = roomCode;

    if (_db == null) return;

    _roomSub = _db!.collection(_collection).doc(roomCode).snapshots().listen((doc) {
      final data = doc.data();
      if (data == null) return;
      final status = data['status'] as String?;
      final guestId = data['player2Id'] as String?;
      final guestName = data['player2Name'] as String?;

      if (status == 'playing' && guestId != null) {
        onReady(guestId, (guestName ?? 'Player'));
      } else if (guestId != null && status != 'playing') {
        onOpponentJoined();
      }
    });
  }

  static Future<bool> joinPrivateRoom({
    required String roomCode,
    required String playerId,
    required String playerName,
    required String country,
  }) async {
    if (_db == null) return false;

    try {
      final roomsRef = _db!.collection(_collection);

      final query = await roomsRef.where('roomCode', isEqualTo: roomCode).limit(1).get();
      if (query.docs.isEmpty) return false;

      final doc = query.docs.first;
      final data = doc.data();
      final docId = doc.id;

      if (data['status'] != 'waiting') return false;
      if (data['player2Id'] != null) return false;

      await roomsRef.doc(docId).update({
        'player2Id': playerId,
        'player2Name': playerName,
        'player2Country': country,
        'status': 'playing',
        'matchedAt': FieldValue.serverTimestamp(),
      });

      _currentRoomId = docId;
      return true;
    } catch (e, s) {
      ErrorHandler.logError('Join room', e, s);
      return false;
    }
  }

  static Future<void> cancelSearch() async {
    _isSearching = false;
    _onMatchFound = null;
    _roomSub?.cancel();
    _roomSub = null;

    if (_db != null && _currentRoomId != null) {
      try {
        final doc = await _db!.collection(_collection).doc(_currentRoomId!).get();
        if (doc.exists) {
          final data = doc.data();
          final status = data?['status'];
          if (status == 'waiting') {
            await _db!.collection(_collection).doc(_currentRoomId!).delete();
          }
        }
      } catch (_) {}
    }

    _currentRoomId = null;
  }

  static Future<void> leaveMatch() async {
    _isSearching = false;
    _onMatchFound = null;
    _roomSub?.cancel();
    _roomSub = null;

    if (_db != null && _currentRoomId != null) {
      try {
        final doc = await _db!.collection(_collection).doc(_currentRoomId!).get();
        if (doc.exists) {
          final data = doc.data();
          final status = data?['status'];
          if (status == 'waiting' || status == 'playing') {
            await _db!.collection(_collection).doc(_currentRoomId!).update({
              'status': 'finished',
            });
          }
        }
      } catch (_) {}
    }

    _currentRoomId = null;
  }

  static Future<Map<String, String>?> getOpponentInfo(String playerId, String roomId) async {
    if (_db == null) return null;
    try {
      final doc = await _db!.collection(_collection).doc(roomId).get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final p1 = data['player1Id'] as String?;
      final p2 = data['player2Id'] as String?;
      final p1Name = data['player1Name'] as String?;
      final p2Name = data['player2Name'] as String?;
      final isPlayer1 = p1 == playerId;
      return {
        'opponentId': (isPlayer1 ? p2 : p1) ?? '',
        'opponentName': (isPlayer1 ? p2Name : p1Name) ?? 'Player',
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> finishGame({
    required String roomId,
    required String winnerId,
    required String loserId,
  }) async {
    if (_db == null) return;
    try {
      await _db!.collection(_collection).doc(roomId).update({
        'status': 'finished',
        'winner': winnerId,
        'loser': loserId,
        'finishedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static void dispose() {
    _roomSub?.cancel();
    _roomSub = null;
    _isSearching = false;
    _onMatchFound = null;
  }

  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
