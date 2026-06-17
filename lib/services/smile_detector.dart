import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

class SmileData {
  final double smileScore;
  final double mouthWidthRatio;
  final double cornerElevation;
  final int pointCount;
  final double detectionMs;

  SmileData({
    required this.smileScore,
    required this.mouthWidthRatio,
    required this.cornerElevation,
    required this.pointCount,
    required this.detectionMs,
  });

  @override
  String toString() =>
      'Smile:${smileScore.toStringAsFixed(2)} mouthW:${mouthWidthRatio.toStringAsFixed(3)} elev:${cornerElevation.toStringAsFixed(3)} pts:$pointCount';
}

class SmileDetector {
  FaceMeshDetector? _detector;
  bool _isRunning = false;
  bool _isDisposed = false;
  int _fpsCounter = 0;
  int _fps = 0;
  DateTime _lastFpsReset = DateTime.now();
  int _frameLogCounter = 0;

  final StreamController<double> _smileController = StreamController<double>.broadcast();
  final StreamController<SmileData> _debugController = StreamController<SmileData>.broadcast();

  Stream<double> get smileStream => _smileController.stream;
  Stream<SmileData> get debugStream => _debugController.stream;

  bool get isRunning => _isRunning;
  int get fps => _fps;

  SmileDetector();

  void start() {
    if (_detector != null) {
      try {
        _detector!.close();
      } catch (_) {}
      _detector = null;
    }
    _detector = FaceMeshDetector(
      option: FaceMeshDetectorOptions.faceMesh,
    );
    _isRunning = true;
    _lastFpsReset = DateTime.now();
    _fpsCounter = 0;
    _frameLogCounter = 0;
    debugPrint('[FACEMESH] Detector started (468-point mesh, option=faceMesh)');
  }

  Future<double> processFrame(InputImage inputImage) async {
    if (!_isRunning || _detector == null) return 0.0;
    final sw = Stopwatch()..start();

    try {
      final faces = await _detector!.processImage(inputImage);
      sw.stop();

      _fpsCounter++;
      _frameLogCounter++;
      final now = DateTime.now();
      if (now.difference(_lastFpsReset).inMilliseconds >= 1000) {
        _fps = _fpsCounter;
        _fpsCounter = 0;
        _lastFpsReset = now;
      }

      if (faces.isEmpty) {
        if (_frameLogCounter % 30 == 0) {
          debugPrint('[FACEMESH] No face detected (frame#$_frameLogCounter) FPS=$_fps ms=${sw.elapsedMilliseconds}');
        }
        _smileController.add(0.0);
        return 0.0;
      }

      final faceMesh = faces.first;
      final points = faceMesh.points;

      if (_frameLogCounter % 15 == 0) {
        debugPrint('[FACEMESH] Frame#$_frameLogCounter face detected pts=${points.length} ms=${sw.elapsedMilliseconds} FPS=$_fps');
      }

      final smile = _computeSmileFromMesh(points, _frameLogCounter);

      final data = SmileData(
        smileScore: smile,
        mouthWidthRatio: _lastMouthW,
        cornerElevation: _lastElev,
        pointCount: points.length,
        detectionMs: sw.elapsedMilliseconds.toDouble(),
      );
      _debugController.add(data);
      _smileController.add(smile);
      return smile;
    } catch (e) {
      sw.stop();
      debugPrint('[FACEMESH] processFrame ERROR: $e');
      return 0.0;
    }
  }

  double _lastMouthW = 0.0;
  double _lastElev = 0.0;

  double _computeSmileFromMesh(List<FaceMeshPoint> points, int frameNum) {
    if (points.isEmpty) return 0.0;

    final pointMap = <int, FaceMeshPoint>{};
    for (final p in points) {
      pointMap[p.index] = p;
    }

    final rightCorner = pointMap[61];  // right mouth corner
    final leftCorner = pointMap[291];  // left mouth corner
    final upperLip = pointMap[13];     // upper lip top center
    final lowerLip = pointMap[14];     // lower lip bottom center
    final noseTip = pointMap[1];       // nose tip
    final chin = pointMap[152];        // chin
    final rightCheek = pointMap[117];  // right cheek reference
    final leftCheek = pointMap[346];   // left cheek reference

    final missing = <String>[];
    if (rightCorner == null) missing.add('Rcorner(61)');
    if (leftCorner == null) missing.add('Lcorner(291)');
    if (upperLip == null) missing.add('upperLip(13)');
    if (lowerLip == null) missing.add('lowerLip(14)');
    if (missing.isNotEmpty) {
      if (frameNum % 60 == 0) debugPrint('[FACEMESH] Missing landmarks: ${missing.join(', ')}');
      return 0.0;
    }

    // ── 1. Mouth width relative to lower face ──────────────────
    final mouthW = _dist(rightCorner!, leftCorner!);

    double refW;
    if (rightCheek != null && leftCheek != null) {
      refW = _dist(rightCheek, leftCheek);
    } else if (noseTip != null && chin != null) {
      refW = _dist(noseTip, chin) * 1.2;
    } else {
      refW = mouthW * 2.5;
    }

    final mouthWratio = (mouthW / refW).clamp(0.0, 2.0);

    // ── 2. Mouth corner height relative to nose-chin line ─────
    final cornerY = (rightCorner!.y + leftCorner!.y) / 2.0;
    double topY, bottomY;
    if (noseTip != null && chin != null) {
      topY = noseTip.y;
      bottomY = chin.y;
    } else {
      topY = upperLip!.y;
      bottomY = lowerLip!.y + _dist(upperLip!, lowerLip!) * 4;
    }
    var rawFaceHeight = (bottomY - topY).abs();
    final faceHeight = rawFaceHeight < 0.001 ? 1.0 : rawFaceHeight;

    final cornerRelY = (cornerY - topY) / faceHeight;

    // ── 3. Mouth openness ──────────────────────────────────────
    final mouthOpen = _dist(upperLip!, lowerLip!) / (refW.clamp(1.0, 9999.0));

    // ── 4. Composite smile score ───────────────────────────────
    double smile = 0.0;

    final wScore = ((mouthWratio - 0.38) / 0.14).clamp(0.0, 0.5);
    smile += wScore;

    final elevScore = ((0.65 - cornerRelY) / 0.15).clamp(0.0, 0.4);
    smile += elevScore;

    final openScore = ((mouthOpen - 0.015) / 0.05).clamp(0.0, 0.2);
    smile += openScore;

    smile = smile.clamp(0.0, 1.0);

    _lastMouthW = mouthWratio;
    _lastElev = cornerRelY;

    if (frameNum % 30 == 0) {
      debugPrint('[SMILE] F#$frameNum smile=${smile.toStringAsFixed(3)} | w=${mouthWratio.toStringAsFixed(3)}(s${wScore.toStringAsFixed(2)}) elev=${cornerRelY.toStringAsFixed(3)}(s${elevScore.toStringAsFixed(2)}) open=${mouthOpen.toStringAsFixed(3)}(s${openScore.toStringAsFixed(2)}) pts=${points.length}');
    }

    return smile;
  }

  static double _dist(FaceMeshPoint a, FaceMeshPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }

  Future<void> stop() async {
    _isRunning = false;
    if (!_isDisposed && _detector != null) {
      try {
        await _detector!.close();
      } catch (_) {}
    }
    _detector = null;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _isRunning = false;
    _smileController.close();
    _debugController.close();
    try {
      _detector?.close();
    } catch (_) {}
    _detector = null;
  }
}
