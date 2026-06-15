import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GameSoundService {
  GameSoundService._();

  static const int FUNNY_FACE = 0;
  static const int JOKE = 1;
  static const int SOUND_FX = 2;
  static const int IMITATION = 3;
  static const int TEASE = 4;
  static const int GESTURE = 5;

  static void init() {}

  static Future<void> play(int actionIndex) async {
    try {
      switch (actionIndex) {
        case FUNNY_FACE:
          HapticFeedback.mediumImpact();
          break;
        case JOKE:
          HapticFeedback.heavyImpact();
          break;
        case SOUND_FX:
          HapticFeedback.lightImpact();
          await Future.delayed(const Duration(milliseconds: 50));
          HapticFeedback.lightImpact();
          break;
        case IMITATION:
          HapticFeedback.mediumImpact();
          await Future.delayed(const Duration(milliseconds: 80));
          HapticFeedback.lightImpact();
          break;
        case TEASE:
          HapticFeedback.heavyImpact();
          break;
        case GESTURE:
          HapticFeedback.lightImpact();
          await Future.delayed(const Duration(milliseconds: 40));
          HapticFeedback.lightImpact();
          await Future.delayed(const Duration(milliseconds: 40));
          HapticFeedback.mediumImpact();
          break;
      }
      SystemSound.play(SystemSoundType.click);
    } catch (e) {
      debugPrint('Sound/vibrate error: $e');
    }
  }
}
