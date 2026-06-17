import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';
import 'error_handler.dart';

class GameSyncService {
  GameSyncService._();

  static const String _collection = 'match_rooms';

  static StreamSubscription? _gameSub;
  static String? _lastProcessedEvent;

  static FirebaseFirestore? get _db => FirebaseService.firestore;

  static Future<void> startGame({
    required String matchId,
    required String playerId,
    required Function(Map<String, dynamic>) onOpponentUpdate,
    required Function(String winner, String loser) onGameEnd,
    Function(String event)? onGameEvent,
  }) async {
    if (_db == null) {
      throw Exception('Firebase not available - real multiplayer required');
    }
    _lastProcessedEvent = null;
    await _startOnline(matchId, playerId, onOpponentUpdate, onGameEnd, onGameEvent);
  }

  static Future<void> _startOnline(
    String matchId, String playerId,
    Function(Map<String, dynamic>) onOpponentUpdate,
    Function(String, String) onGameEnd,
    Function(String event)? onGameEvent,
  ) async {
    try {
      await _db!.collection(_collection).doc(matchId).update({
        '${playerId}_smile': 0.0,
        'status': 'playing',
      });
    } catch (e) {
      debugPrint('Game sync init error: $e');
    }

    _gameSub = _db!.collection(_collection).doc(matchId).snapshots().listen((doc) {
      final data = doc.data();
      if (data == null) return;
      final status = data['status'];
      final winner = data['winner'];
      final loser = data['loser'];
      if (status == 'finished' && winner != null && loser != null) {
        onGameEnd(winner.toString(), loser.toString());
        return;
      }
      final p1Id = data['player1Id']?.toString();
      final p2Id = data['player2Id']?.toString();
      if (p1Id == null || p2Id == null) return;
      final isPlayer1 = p1Id == playerId;
      final oppId = isPlayer1 ? p2Id : p1Id;
      final oppSmile = (data['${oppId}_smile'] as num?)?.toDouble() ?? 0.0;
      onOpponentUpdate({'opponentId': oppId, 'opponentSmile': oppSmile, 'isReal': true});

      if (onGameEvent != null) {
        final eventData = data['gameEvent'];
        if (eventData is Map) {
          final eventKey = '${eventData['senderId']}_${eventData['timestamp']}';
          if (eventKey != _lastProcessedEvent) {
            _lastProcessedEvent = eventKey;
            final event = eventData['event'] as String?;
            if (event != null && eventData['senderId'] != playerId) {
              onGameEvent(event);
            }
          }
        }
      }
    });
  }

  static Future<void> sendGameEvent({
    required String matchId,
    required String playerId,
    required String event,
  }) async {
    if (_db == null) return;
    try {
      await _db!.collection(_collection).doc(matchId).update({
        'gameEvent': {
          'senderId': playerId,
          'event': event,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      });
    } catch (_) {}
  }

  static Future<void> updateMySmile({
    required String matchId,
    required String playerId,
    required double smileValue,
  }) async {
    if (_db == null) return;
    try {
      await _db!.collection(_collection).doc(matchId).update({
        '${playerId}_smile': smileValue,
      });
    } catch (_) {}
  }

  static Future<void> iLaughed({
    required String matchId,
    required String myId,
  }) async {
    if (_db == null) return;
    try {
      await _db!.runTransaction((tx) async {
        final docRef = _db!.collection(_collection).doc(matchId);
        final doc = await tx.get(docRef);
        if (!doc.exists) return;
        final data = doc.data();
        if (data == null) return;
        if (data['status'] == 'finished') return;
        final p1 = data['player1Id'];
        final p2 = data['player2Id'];
        final winnerId = (myId == p1) ? p2 : p1;
        tx.update(docRef, {
          'status': 'finished',
          'winner': winnerId,
          'loser': myId,
          'finishedAt': DateTime.now().millisecondsSinceEpoch,
        });
      });
    } catch (_) {}
  }

  static Future<void> setGameStarted(String matchId) async {
    if (_db == null) return;
    try {
      await _db!.collection(_collection).doc(matchId).update({
        'status': 'playing',
      });
    } catch (_) {}
  }

  static void dispose() {
    _gameSub?.cancel();
    _gameSub = null;
    _lastProcessedEvent = null;
  }
}
