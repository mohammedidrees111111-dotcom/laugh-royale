import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'firebase_service.dart';

class LobbyService {
  LobbyService._();

  static Future<void> saveGameResult({required bool won, required String opponent}) async {
    final prefs = await SharedPreferences.getInstance();
    final wins = (prefs.getInt('wins') ?? 0) + (won ? 1 : 0);
    final losses = (prefs.getInt('losses') ?? 0) + (won ? 0 : 1);
    final total = (prefs.getInt('totalGames') ?? 0) + 1;
    await prefs.setInt('wins', wins);
    await prefs.setInt('losses', losses);
    await prefs.setInt('totalGames', total);
    debugPrint('Game result saved: ${won ? "WON" : "LOST"} vs $opponent | W:$wins L:$losses');

    final uid = AuthService.currentUserId;
    final name = AuthService.displayName;
    final db = FirebaseService.firestore;
    if (uid != null && name.isNotEmpty && db != null) {
      try {
        final docRef = db.collection('leaderboard').doc(uid);
        final snapshot = await docRef.get();
        if (snapshot.exists) {
          await docRef.update({
            'name': name,
            'wins': wins,
            'losses': losses,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
        } else {
          await docRef.set({
            'name': name,
            'wins': wins,
            'losses': losses,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
        }
      } catch (_) {}
    }
  }

  static Future<Map<String, int>> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'wins': prefs.getInt('wins') ?? 0,
      'losses': prefs.getInt('losses') ?? 0,
      'total': prefs.getInt('totalGames') ?? 0,
    };
  }
}
