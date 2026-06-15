import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../services/smile_detector.dart';

class TestSmileScreen extends StatefulWidget {
  const TestSmileScreen({super.key});
  @override
  State<TestSmileScreen> createState() => _TestSmileScreenState();
}

class _TestSmileScreenState extends State<TestSmileScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  late SmileDetector _detector;
  bool _ready = false;
  bool _processing = false;
  int _frameSkip = 0;
  SmileData? _data;
  String _status = 'Initializing...';
  final List<double> _history = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detector = SmileDetector();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _status = 'No camera found');
        return;
      }
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      _camera = CameraController(front, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await _camera!.initialize();
      _detector.start();
      await _camera!.startImageStream(_onFrame);
      setState(() { _ready = true; _status = 'Detecting...'; });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  void _onFrame(CameraImage image) {
    if (_processing) return;
    _frameSkip++;
    if (_frameSkip % 2 != 0) return;
    _processing = true;
    _process(image);
  }

  Future<void> _process(CameraImage image) async {
    try {
      final input = _toInputImage(image);
      if (input == null) { _processing = false; return; }
      final smile = await _detector.processFrame(input);
      if (!mounted) { _processing = false; return; }
      _history.add(smile);
      if (_history.length > 100) _history.removeAt(0);

      String status;
      if (smile > 0.60) {
        status = 'LAUGHING!';
      } else if (smile > 0.40) {
        status = 'Starting to smile...';
      } else if (smile > 0.15) {
        status = 'Slight smile';
      } else {
        status = 'Neutral';
      }

      setState(() => _status = status);
    } catch (_) {
    } finally { _processing = false; }
  }

  InputImage? _toInputImage(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final raw = image.format.raw;
    InputImageFormat fmt;
    Uint8List bytes;
    if (raw == 17) { fmt = InputImageFormat.nv21; bytes = _packNv21(image, w, h); }
    else if (raw == 35) { fmt = InputImageFormat.yuv_420_888; bytes = _packYuv420(image, w, h); }
    else if (raw == 4 || raw == 1111970369) { fmt = InputImageFormat.bgra8888; bytes = _packBgra(image, w, h); }
    else { return null; }
    return InputImage.fromBytes(bytes: bytes, metadata: InputImageMetadata(size: Size(w.toDouble(), h.toDouble()), rotation: InputImageRotation.rotation0deg, format: fmt, bytesPerRow: w));
  }

  Uint8List _packNv21(CameraImage img, int w, int h) {
    final uvH = h ~/ 2;
    final total = w * h + w * uvH;
    final nv21 = Uint8List(total);
    final yP = img.planes[0]; final yRs = yP.bytesPerRow;
    for (int y = 0; y < h; y++) { nv21.setRange(y * w, y * w + w, yP.bytes, y * yRs); }
    final vuP = img.planes[1]; final vuRs = vuP.bytesPerRow;
    for (int y = 0; y < uvH; y++) { nv21.setRange(w * h + y * w, w * h + y * w + w, vuP.bytes, y * vuRs); }
    return nv21;
  }

  Uint8List _packYuv420(CameraImage img, int w, int h) {
    final uvH = h ~/ 2; final int uvW = w ~/ 2;
    final total = w * h + uvW * uvH * 2;
    final yuv = Uint8List(total);
    final yP = img.planes[0]; final yRs = yP.bytesPerRow;
    for (int y = 0; y < h; y++) { yuv.setRange(y * w, y * w + w, yP.bytes, y * yRs); }
    final uP = img.planes[1]; final uRs = uP.bytesPerRow;
    for (int y = 0; y < uvH; y++) { yuv.setRange(w * h + y * uvW, w * h + y * uvW + uvW, uP.bytes, y * uRs); }
    final vP = img.planes[2]; final vRs = vP.bytesPerRow;
    for (int y = 0; y < uvH; y++) { yuv.setRange(w * h + uvW * uvH + y * uvW, w * h + uvW * uvH + y * uvW + uvW, vP.bytes, y * vRs); }
    return yuv;
  }

  Uint8List _packBgra(CameraImage img, int w, int h) {
    final bgra = Uint8List(w * h * 4);
    final p = img.planes[0]; final rs = p.bytesPerRow;
    for (int y = 0; y < h; y++) { bgra.setRange(y * w * 4, y * w * 4 + w * 4, p.bytes, y * rs); }
    return bgra;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.stopImageStream();
    _camera?.dispose();
    _detector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Smile Detection Test'), backgroundColor: Colors.black),
      body: Column(children: [
        Expanded(
          child: _ready && _camera != null ? CameraPreview(_camera!) : Center(
            child: Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 16)),
          ),
        ),
        _buildPanel(),
      ]),
    );
  }

  Widget _buildPanel() {
    final d = _data;
    final hist = _history;
    final last = hist.isNotEmpty ? hist.last : 0.0;
    final avg = hist.isNotEmpty ? hist.reduce((a, b) => a + b) / hist.length : 0.0;
    final maxS = hist.isNotEmpty ? hist.reduce(max) : 0.0;
    final color = last > 0.55 ? Colors.redAccent : last > 0.30 ? Colors.orange : Colors.greenAccent;

    return Container(
      color: const Color(0xFF0A0A14),
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_status, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _stat('NOW', '${(last * 100).toInt()}%', color),
          _stat('AVG', '${(avg * 100).toInt()}%', Colors.white54),
          _stat('MAX', '${(maxS * 100).toInt()}%', Colors.white54),
          _stat('FPS', '${_detector.fps}', Colors.white38),
        ]),
        if (d != null) ...[
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _stat('Class', d.classificationProb >= 0 ? '${(d.classificationProb * 100).toInt()}%' : '-', Colors.white38),
            _stat('Contour', '${(d.contourScore * 100).toInt()}%', Colors.white38),
            _stat('Faces', '${d.faceCount}', Colors.white38),
            _stat('ms', '${d.detectionMs.toInt()}', Colors.white38),
          ]),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 20,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: last.clamp(0.0, 1.0), backgroundColor: Colors.white10, color: color, minHeight: 20),
          ),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white24, fontSize: 9)),
    ]);
  }
}
