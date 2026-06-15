import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';

class WebRTCSignaling {
  WebRTCSignaling._();

  static FirebaseFirestore? get _db => FirebaseService.firestore;

  static StreamSubscription? _offerSub;
  static StreamSubscription? _answerSub;
  static StreamSubscription? _iceSub;

  static Future<void> sendOffer({
    required String matchId,
    required String playerId,
    required String sdp,
  }) async {
    if (_db == null) return;
    await _db!.collection('match_rooms').doc(matchId).update({
      'offer': {'sdp': sdp, 'from': playerId},
    });
  }

  static Future<void> sendAnswer({
    required String matchId,
    required String playerId,
    required String sdp,
  }) async {
    if (_db == null) return;
    await _db!.collection('match_rooms').doc(matchId).update({
      'answer': {'sdp': sdp, 'from': playerId},
    });
  }

  static Future<void> sendIceCandidate({
    required String matchId,
    required String playerId,
    required String candidate,
    required String sdpMid,
    required int sdpMLineIndex,
  }) async {
    if (_db == null) return;
    await _db!.collection('match_rooms').doc(matchId).collection('ice').add({
      'candidate': candidate,
      'sdpMid': sdpMid,
      'sdpMLineIndex': sdpMLineIndex,
      'from': playerId,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  static void listenForOffer({
    required String matchId,
    required String myId,
    required void Function(String sdp) onOffer,
  }) {
    if (_db == null) return;
    _offerSub = _db!.collection('match_rooms').doc(matchId).snapshots().listen((doc) {
      final data = doc.data();
      if (data == null) return;
      final offer = data['offer'];
      if (offer != null && offer['from'] != myId) {
        onOffer(offer['sdp'] as String);
      }
    });
  }

  static void listenForAnswer({
    required String matchId,
    required String myId,
    required void Function(String sdp) onAnswer,
  }) {
    if (_db == null) return;
    _answerSub?.cancel();
    _answerSub = _db!.collection('match_rooms').doc(matchId).snapshots().listen((doc) {
      final data = doc.data();
      if (data == null) return;
      final answer = data['answer'];
      if (answer != null && answer['from'] != myId) {
        onAnswer(answer['sdp'] as String);
      }
    });
  }

  static void listenForIceCandidates({
    required String matchId,
    required String myId,
    required void Function(String candidate, String sdpMid, int sdpMLineIndex) onCandidate,
  }) {
    if (_db == null) return;
    _iceSub?.cancel();
    _iceSub = _db!.collection('match_rooms').doc(matchId).collection('ice')
        .orderBy('timestamp')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && data['from'] != myId) {
            onCandidate(
              data['candidate'] as String,
              data['sdpMid'] as String,
              data['sdpMLineIndex'] as int,
            );
          }
        }
      }
    });
  }

  static Future<void> clearSignaling(String matchId) async {
    if (_db == null) return;
    try {
      final iceDocs = await _db!.collection('match_rooms').doc(matchId).collection('ice').get();
      for (var doc in iceDocs.docs) {
        await doc.reference.delete();
      }
      await _db!.collection('match_rooms').doc(matchId).update({
        'offer': FieldValue.delete(),
        'answer': FieldValue.delete(),
      });
    } catch (_) {}
  }

  static void dispose() {
    _offerSub?.cancel();
    _offerSub = null;
    _answerSub?.cancel();
    _answerSub = null;
    _iceSub?.cancel();
    _iceSub = null;
  }
}
