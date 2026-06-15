import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';

class FaceShareService {
  FaceShareService._();

  static FirebaseFirestore? get _db => FirebaseService.firestore;
  static StreamSubscription? _photoSub;

  static Future<void> shareMyFaceRaw({
    required String matchId,
    required String playerId,
    required String base64Data,
  }) async {
    if (_db == null) return;
    if (base64Data.length > 300000) return;
    try {
      await _db!.collection('match_rooms').doc(matchId).update({
        '${playerId}_photo': base64Data,
        '${playerId}_photo_ts': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Face share error: $e');
    }
  }

  static Future<void> shareMyFace({
    required String matchId,
    required String playerId,
    required String photoPath,
  }) async {
    if (_db == null) return;
    try {
      final file = File(photoPath);
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 200000) return;
      final base64 = base64Encode(bytes);
      await _db!.collection('match_rooms').doc(matchId).update({
        '${playerId}_photo': base64,
        '${playerId}_photo_ts': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Face share error: $e');
    }
  }

  static void watchOpponentFace({
    required String matchId,
    required String myId,
    required void Function(String base64Photo) onPhoto,
  }) {
    if (_db == null) return;
    _photoSub?.cancel();
    _photoSub = _db!.collection('match_rooms').doc(matchId).snapshots().listen((doc) {
      final data = doc.data();
      if (data == null) return;
      final p1Id = data['player1Id'] as String?;
      final p2Id = data['player2Id'] as String?;
      if (p1Id == null || p2Id == null) return;
      final oppId = p1Id == myId ? p2Id : p1Id;
      final photo = data['${oppId}_photo'] as String?;
      if (photo != null && photo.length > 30) {
        onPhoto(photo);
      }
    });
  }

  static void dispose() {
    _photoSub?.cancel();
    _photoSub = null;
  }
}
