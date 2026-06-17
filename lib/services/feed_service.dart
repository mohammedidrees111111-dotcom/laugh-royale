import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';
import 'auth_service.dart';

class FeedService {
  FeedService._();

  static const String _collection = 'feed_posts';

  static FirebaseFirestore? get _db => FirebaseService.firestore;

  static Future<bool> createPost({
    required String content,
    String? imagePath,
    String? category,
  }) async {
    final db = _db;
    if (db == null) return false;
    final uid = AuthService.currentUserId;
    final name = AuthService.displayName;
    if (uid == null) return false;

    try {
      await db.collection(_collection).add({
        'authorId': uid,
        'authorName': name,
        'content': content,
        'imageUrl': imagePath,
        'category': category,
        'likes': 0,
        'comments': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[FEED] Post created by $name');
      return true;
    } catch (e) {
      debugPrint('[FEED] Error creating post: $e');
      return false;
    }
  }

  static Stream<List<Map<String, dynamic>>> getPosts() {
    final db = _db;
    if (db == null) {
      return Stream.value([]);
    }
    return db.collection(_collection)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return {
                'id': doc.id,
                'authorName': data['authorName'] ?? 'Player',
                'content': data['content'] ?? '',
                'imageUrl': data['imageUrl'],
                'category': data['category'],
                'likes': data['likes'] ?? 0,
                'comments': data['comments'] ?? 0,
                'createdAt': data['createdAt'],
              };
            }).toList());
  }
}
