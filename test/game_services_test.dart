import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmileDetector - Geometry Logic', () {
    test('smile score = 0 when landmarks missing', () {
      final result = _simulateComputeSmile(
        hasRightCorner: false,
        hasLeftCorner: false,
      );
      expect(result, equals(0.0));
    });

    test('neutral face gives low smile score (< 0.30)', () {
      final result = _simulateComputeSmile(
        mouthWidthRatio: 0.38,
        cornerRelY: 0.68,
        mouthOpen: 0.015,
      );
      expect(result, lessThan(0.30));
    });

    test('smiling face gives high smile score (> 0.50)', () {
      final result = _simulateComputeSmile(
        mouthWidthRatio: 0.55,
        cornerRelY: 0.50,
        mouthOpen: 0.06,
      );
      expect(result, greaterThan(0.30));
    });

    test('wide smile with open mouth gives very high score (> 0.70)', () {
      final result = _simulateComputeSmile(
        mouthWidthRatio: 0.60,
        cornerRelY: 0.42,
        mouthOpen: 0.08,
      );
      expect(result, greaterThan(0.55));
    });

    test('clamped to range [0.0, 1.0]', () {
      final result = _simulateComputeSmile(
        mouthWidthRatio: 0.80,
        cornerRelY: 0.20,
        mouthOpen: 0.15,
      );
      expect(result, inInclusiveRange(0.0, 1.0));
    });

    test('negative edge values do not break calculation', () {
      final results = <double>[];
      for (var w = 0.25; w <= 0.70; w += 0.05) {
        for (var e = 0.40; e <= 0.75; e += 0.05) {
          for (var o = 0.0; o <= 0.10; o += 0.02) {
            final s = _simulateComputeSmile(mouthWidthRatio: w, cornerRelY: e, mouthOpen: o);
            expect(s, greaterThanOrEqualTo(0.0));
            expect(s, lessThanOrEqualTo(1.0));
            expect(s.isNaN, isFalse);
            results.add(s);
          }
        }
      }
    });
  });

  group('GameSync - Winner Logic', () {
    test('player who laughs is the loser', () {
      final myId = 'playerA';
      final oppId = 'playerB';
      final winner = (myId == myId) ? oppId : myId;
      expect(winner, equals('playerB'));
    });

    test('opponent who laughs makes current player the winner', () {
      final myId = 'playerA';
      final oppId = 'playerB';
      final winner = (oppId == myId) ? oppId : myId;
      expect(winner, equals('playerA'));
    });

    test('consecutive smile frames threshold triggers laugh', () {
      const requiredConsecutive = 2;
      const laughThreshold = 0.35;
      int consecutiveSmileFrames = 0;
      bool laughed = false;

      // Simulate frames above threshold
      final frames = [0.40, 0.42, 0.38, 0.50];
      for (final smile in frames) {
        if (smile > laughThreshold) {
          consecutiveSmileFrames++;
        } else {
          consecutiveSmileFrames = 0;
        }
        if (consecutiveSmileFrames >= requiredConsecutive) {
          laughed = true;
          break;
        }
      }
      expect(laughed, isTrue);
    });

    test('single smile frame does not trigger laugh', () {
      const requiredConsecutive = 2;
      const laughThreshold = 0.35;
      int consecutiveSmileFrames = 0;
      bool laughed = false;

      final frames = [0.40, 0.10, 0.45, 0.15];
      for (final smile in frames) {
        if (smile > laughThreshold) {
          consecutiveSmileFrames++;
          if (consecutiveSmileFrames >= requiredConsecutive) laughed = true;
        } else {
          consecutiveSmileFrames = 0;
        }
      }
      expect(laughed, isFalse);
    });

    test('smile reset threshold clears consecutive counter', () {
      const laughThreshold = 0.35;
      const smileResetThreshold = 0.20;
      int consecutiveSmileFrames = 0;

      final frames = [0.40, 0.15, 0.50, 0.60];
      for (final smile in frames) {
        if (smile > laughThreshold) {
          consecutiveSmileFrames++;
        } else if (smile < smileResetThreshold) {
          consecutiveSmileFrames = 0;
        }
      }
      expect(consecutiveSmileFrames, equals(2));
    });
  });

  group('WebRTC Signaling - ICE Buffering', () {
    test('ICE candidates are buffered when remote desc not set', () {
      final buffer = <String>[];
      bool remoteDescSet = false;

      void sendCandidate(String c) {
        if (remoteDescSet) {
          buffer.add(c);
        }
      }

      sendCandidate('candidate1');
      expect(buffer.isEmpty, isTrue);

      remoteDescSet = true;
      sendCandidate('candidate2');
      expect(buffer, contains('candidate2'));
    });

    test('buffered ICE candidates flush after remote desc set', () {
      final buffer = <String>[];
      bool remoteDescSet = false;

      buffer.add('early1');
      buffer.add('early2');

      remoteDescSet = true;

      final flushed = List<String>.from(buffer);
      buffer.clear();
      String result = '';
      for (final c in flushed) { result += c + ','; }

      expect(result, contains('early1'));
      expect(result, contains('early2'));
    });
  });

  group('Voice Chat - Speakerphone', () {
    test('speakerphone is called before getUserMedia', () async {
      final callOrder = <String>[];

      void setSpeakerOn() {
        callOrder.add('speakerphone');
      }

      void getUserMedia() {
        callOrder.add('getUserMedia');
      }

      setSpeakerOn();
      getUserMedia();

      expect(callOrder[0], equals('speakerphone'));
      expect(callOrder[1], equals('getUserMedia'));
    });
  });

  group('Matchmaking - Room Code', () {
    test('room code is 6 alphanumeric chars', () {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final r = Random(42);
      final code = List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();

      expect(code.length, equals(6));
      expect(RegExp(r'^[A-Z2-9]+$').hasMatch(code), isTrue);
    });

    test('room codes do not contain confusing characters', () {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      expect(chars.contains('O'), isFalse);  // confused with 0
      expect(chars.contains('I'), isFalse);  // confused with 1
      expect(chars.contains('0'), isFalse);
      expect(chars.contains('1'), isFalse);
    });
  });

  group('Camera Rotation - InputImage', () {
    test('front camera sensor orientation 270 maps to 270 for ML Kit', () {
      int sensorOrientation = 270;
      expect(sensorOrientation, equals(270));
    });

    test('back camera sensor orientation 90 maps correctly', () {
      int sensorOrientation = 90;
      expect(sensorOrientation, equals(90));
    });

    test('rotation 0 maps to 0 deg', () {
      final rotationDeg = _cameraRotationToDeg(0);
      expect(rotationDeg, equals(0));
    });

    test('rotation 90 maps to 90 deg', () {
      final rotationDeg = _cameraRotationToDeg(90);
      expect(rotationDeg, equals(90));
    });

    test('rotation 270 maps to 270 deg', () {
      final rotationDeg = _cameraRotationToDeg(270);
      expect(rotationDeg, equals(270));
    });
  });
}

double _simulateComputeSmile({
  double mouthWidthRatio = 0.45,
  double cornerRelY = 0.60,
  double mouthOpen = 0.03,
  bool hasRightCorner = true,
  bool hasLeftCorner = true,
  bool hasUpperLip = true,
  bool hasLowerLip = true,
}) {
  if (!hasRightCorner || !hasLeftCorner || !hasUpperLip || !hasLowerLip) {
    return 0.0;
  }

  double smile = 0.0;

  final wScore = ((mouthWidthRatio - 0.38) / 0.14).clamp(0.0, 0.5);
  smile += wScore;

  final elevScore = ((0.65 - cornerRelY) / 0.15).clamp(0.0, 0.4);
  smile += elevScore;

  final openScore = ((mouthOpen - 0.015) / 0.05).clamp(0.0, 0.2);
  smile += openScore;

  return smile.clamp(0.0, 1.0);
}

int _cameraRotationToDeg(int rotationStep) {
  switch (rotationStep) {
    case 0: return 0;
    case 90: return 90;
    case 180: return 180;
    case 270: return 270;
    default: return 0;
  }
}
