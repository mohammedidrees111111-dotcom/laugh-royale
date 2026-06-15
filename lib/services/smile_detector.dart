import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class SmileData {
  final double smileScore;
  final double classificationProb;
  final double contourScore;
  final int faceCount;
  final double detectionMs;

  SmileData({
    required this.smileScore,
    required this.classificationProb,
    required this.contourScore,
    required this.faceCount,
    required this.detectionMs,
  });

  @override
  String toString() => 'Smile:${smileScore.toStringAsFixed(2)} cls:${classificationProb.toStringAsFixed(2)} cnt:${contourScore.toStringAsFixed(2)} faces:$faceCount';
}

class SmileDetector {
  final FaceDetector _detector;
  bool _isRunning = false;
  int _fpsCounter = 0;
  int _fps = 0;
  DateTime _lastFpsReset = DateTime.now();

  final StreamController<double> _smileController = StreamController<double>.broadcast();
  final StreamController<SmileData> _debugController = StreamController<SmileData>.broadcast();

  Stream<double> get smileStream => _smileController.stream;
  Stream<SmileData> get debugStream => _debugController.stream;

  bool get isRunning => _isRunning;
  int get fps => _fps;

  SmileDetector()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.accurate,
            enableClassification: true,
            enableContours: true,
            enableLandmarks: true,
          ),
        );

  void start() {
    _isRunning = true;
    _lastFpsReset = DateTime.now();
    _fpsCounter = 0;
  }

  Future<double> processFrame(InputImage inputImage) async {
    if (!_isRunning) return 0.0;
    final sw = Stopwatch()..start();

    try {
      final faces = await _detector.processImage(inputImage);
      sw.stop();

      _fpsCounter++;
      final now = DateTime.now();
      if (now.difference(_lastFpsReset).inMilliseconds >= 1000) {
        _fps = _fpsCounter;
        _fpsCounter = 0;
        _lastFpsReset = now;
      }

      if (faces.isEmpty) {
        if (_fpsCounter == 0) debugPrint('[MLKIT] No faces detected FPS=$_fps');
        final data = SmileData(smileScore: 0, classificationProb: 0, contourScore: 0, faceCount: 0, detectionMs: sw.elapsedMilliseconds.toDouble());
        _debugController.add(data);
        _smileController.add(0.0);
        return 0.0;
      }

      final face = faces.first;
      final classProb = face.smilingProbability ?? -1.0;
      final contourScore = _computeMouthContourSmile(face);
      final smileScore = classProb >= 0 ? (classProb * 0.7 + contourScore * 0.3) : contourScore;

      if (_fpsCounter == 0) {
        debugPrint('[MLKIT] Face found | classProb=${classProb.toStringAsFixed(2)} contour=${contourScore.toStringAsFixed(2)} smile=${smileScore.toStringAsFixed(2)} faces=${faces.length} ms=${sw.elapsedMilliseconds}');
      }

      final data = SmileData(
        smileScore: smileScore,
        classificationProb: classProb,
        contourScore: contourScore,
        faceCount: faces.length,
        detectionMs: sw.elapsedMilliseconds.toDouble(),
      );
      _debugController.add(data);
      _smileController.add(smileScore);
      return smileScore;
    } catch (e) {
      sw.stop();
      return 0.0;
    }
  }

  double _computeMouthContourSmile(Face face) {
    try {
      final contours = face.contours;
      if (contours.isEmpty) return 0.0;

      final upperLip = contours[FaceContourType.upperLipBottom];
      final lowerLip = contours[FaceContourType.lowerLipTop];

      if (upperLip == null || lowerLip == null) return 0.0;
      final uPoints = upperLip.points;
      final lPoints = lowerLip.points;
      if (uPoints.length < 3 || lPoints.length < 3) return 0.0;

      final n = (uPoints.length < lPoints.length ? uPoints.length : lPoints.length) - 2;
      if (n <= 0) return 0.0;

      double mouthOpening = 0;
      for (int i = 1; i < n + 1; i++) {
        mouthOpening += (lPoints[i].y - uPoints[i].y).abs().toDouble();
      }
      final avgOpening = mouthOpening / n;

      final mouthWidth = (uPoints.last.x - uPoints.first.x).abs().toDouble();
      if (mouthWidth <= 0) return 0.0;

      final smileRatio = avgOpening / mouthWidth;
      final upperCorners = (uPoints.first.y - uPoints.last.y).abs().toDouble();
      final lipCornerRaise = upperCorners / mouthWidth;
      final score = (lipCornerRaise * 0.5 + smileRatio * 0.5).clamp(0.0, 1.0);

      return (score * 2.5).clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  Future<void> stop() async {
    _isRunning = false;
    await _detector.close();
  }

  void dispose() {
    _isRunning = false;
    _smileController.close();
    _debugController.close();
    _detector.close();
  }
}
