import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../services/smile_detector.dart';
import '../../services/lobby_service.dart';
import '../../services/auth_service.dart';
import '../../services/game_sync_service.dart';
import '../../services/face_share_service.dart';
import '../../services/local_game_service.dart';
import '../../services/ws_game_service.dart';
import '../../services/fb_online_service.dart';
import '../../services/game_sound_service.dart';
import 'game_over_screen.dart';

class GameScreen extends StatefulWidget {
  final String matchId;
  final String opponentId;
  final String opponentName;
  final bool isHost;
  final bool isPractice;
  final bool isLocal;
  final bool isWebSocket;
  final bool isFbOnline;

  const GameScreen({
    super.key,
    required this.matchId,
    required this.opponentId,
    required this.opponentName,
    this.isHost = true,
    this.isPractice = false,
    this.isLocal = false,
    this.isWebSocket = false,
    this.isFbOnline = false,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription>? _cameras;
  late SmileDetector _detector;
  Timer? _faceTimer;
  Timer? _cameraTimeout;

  int _timeLeft = 0;
  Timer? _countdownTimer;

  double _mySmile = 0.0;
  double _oppSmile = 0.0;
  bool _gameOver = false;
  String? _winner;

  int _frameSkipCounter = 0;
  bool _processingFrame = false;
  CameraImage? _pendingFrame;

  String _oppStatus = 'Ready';
  String? _oppFaceBase64;
  Uint8List? _oppFaceBytes;
  bool _oppFaceLoaded = false;
  bool _cameraReady = false;
  String? _cameraError;

  final List<Map<String, dynamic>> _actions = [
    {'icon': Icons.emoji_emotions, 'label': 'Funny Face', 'color': 0xFF6C63FF},
    {'icon': Icons.record_voice_over, 'label': 'Joke', 'color': 0xFFFF6584},
    {'icon': Icons.music_note, 'label': 'Sound', 'color': 0xFF00D9FF},
    {'icon': Icons.pets, 'label': 'Imitation', 'color': 0xFF00E676},
    {'icon': Icons.sentiment_very_satisfied, 'label': 'Tease', 'color': 0xFFFFAB40},
    {'icon': Icons.waving_hand, 'label': 'Gesture', 'color': 0xFFE040FB},
  ];

  final List<String> _jokes = [
    'Why don\'t scientists trust atoms?\nBecause they make up everything!',
    'What do you call a bear with no teeth?\nA gummy bear!',
    'Parallel lines have so much in common.\nIt\'s a shame they\'ll never meet!',
    'I told my wife she was drawing her eyebrows too high.\nShe looked surprised!',
    'What do you call a fake noodle?\nAn impasta!',
    'How does a penguin build its house?\nIgloos it together!',
    'Why did the scarecrow win an award?\nBecause he was outstanding in his field!',
  ];

  String _actionMessage = '';
  String _myId = '';
  late String _matchId;
  bool _iLaughed = false;
  bool _gameEnding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detector = SmileDetector();
    GameSoundService.init();
    _myId = AuthService.currentUserId ?? 'unknown';
    _matchId = widget.matchId;

    _initCamera();
    if (widget.isPractice) {
      _startPracticeAI();
    } else if (widget.isLocal || widget.isWebSocket || widget.isFbOnline) {
      _startOnlineGame();
    } else {
      _startGameSync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _camera?.stopImageStream();
    } else if (state == AppLifecycleState.resumed && !_gameOver) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras().timeout(const Duration(seconds: 5));
    } catch (_) {
      _cameras = null;
    }

    if (_cameras == null || _cameras!.isEmpty) {
      if (mounted) setState(() => _cameraError = 'No camera available');
      _startGame();
      return;
    }

    CameraDescription front;
    try {
      front = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );
    } catch (_) {
      front = _cameras!.first;
    }

    final preset = await _bestResolution(front);

    _camera = CameraController(
      front,
      preset,
      enableAudio: false,
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _camera!.initialize().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) setState(() => _cameraError = 'Camera failed to start');
      _startGame();
      return;
    }

    try {
      await _camera!.startImageStream(_onCameraFrame);
    } catch (_) {}

    if (mounted) setState(() => _cameraReady = true);

    _startGame();
    if (!widget.isPractice) {
      _startFaceSharing();
      _watchOpponentFace();
    }
  }

  Future<ResolutionPreset> _bestResolution(CameraDescription camera) async {
    final presets = [
      ResolutionPreset.medium,
      ResolutionPreset.low,
    ];
    for (final preset in presets) {
      try {
        final testCtrl = CameraController(camera, preset, enableAudio: false);
        await testCtrl.initialize().timeout(const Duration(seconds: 2));
        await testCtrl.dispose();
        return preset;
      } catch (_) {}
    }
    return ResolutionPreset.low;
  }

  void _onCameraFrame(CameraImage image) {
    if (_gameOver || _gameEnding) return;
    _pendingFrame = image;
    if (_processingFrame) return;
    _processingFrame = true;
    _processNextFrame();
  }

  Future<void> _processNextFrame() async {
    while (_pendingFrame != null && !_gameOver && !_gameEnding) {
      final frame = _pendingFrame!;
      _pendingFrame = null;
      try {
        final inputImage = _cameraImageToInputImage(frame);
        if (inputImage == null) continue;
        final smile = await _detector.processFrame(inputImage);
        if (!mounted || _gameOver || _gameEnding) break;
        GameSyncService.updateMySmile(matchId: _matchId, playerId: _myId, smileValue: smile);
        if (widget.isLocal) LocalGameService.sendSmile(smile);
        if (widget.isWebSocket) WsGameService.sendSmile(smile);
        if (widget.isFbOnline) FbOnlineService.sendSmile(smile);
        setState(() {
          _mySmile = smile;
          if (smile > 0.40 && !_iLaughed) {
            _iLaughed = true;
            debugPrint('GAME: I laughed! smile=$smile');
            if (widget.isLocal) {
              LocalGameService.sendGameEvent('laughed');
              _endGame(won: false, reason: 'player_laughed');
            } else if (widget.isWebSocket) {
              WsGameService.sendGameEvent('laughed');
              _endGame(won: false, reason: 'player_laughed');
            } else if (widget.isFbOnline) {
              FbOnlineService.sendGameEvent('laughed');
              FbOnlineService.reportLaugh(playerId: _myId);
              _endGame(won: false, reason: 'player_laughed');
            } else {
              GameSyncService.iLaughed(matchId: _matchId, myId: _myId);
            }
          }
        });
      } catch (_) {}
    }
    _processingFrame = false;
  }

  InputImage? _cameraImageToInputImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    InputImageFormat inputFormat;
    Uint8List bytes;
    final rawFormat = image.format.raw;
    if (rawFormat == 17) {
      inputFormat = InputImageFormat.nv21;
      bytes = _packNv21(image, width, height);
    } else if (rawFormat == 35) {
      inputFormat = InputImageFormat.yuv_420_888;
      bytes = _packYuv420(image, width, height);
    } else if (rawFormat == 4 || rawFormat == 1111970369) {
      inputFormat = InputImageFormat.bgra8888;
      bytes = _packBgra(image, width, height);
    } else {
      inputFormat = InputImageFormat.nv21;
      bytes = _packNv21(image, width, height);
    }
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: inputFormat,
        bytesPerRow: width,
      ),
    );
  }

  Uint8List _packNv21(CameraImage image, int width, int height) {
    final uvHeight = height ~/ 2;
    final int totalSize = width * height + width * uvHeight;
    final Uint8List nv21 = Uint8List(totalSize);
    final yPlane = image.planes[0];
    final yRowStride = yPlane.bytesPerRow;
    for (int y = 0; y < height; y++) {
      final int offset = y * yRowStride;
      nv21.setRange(y * width, y * width + width, yPlane.bytes, offset);
    }
    final vuPlane = image.planes[1];
    final vuRowStride = vuPlane.bytesPerRow;
    final int vuOffset = width * height;
    for (int y = 0; y < uvHeight; y++) {
      final int offset = y * vuRowStride;
      nv21.setRange(vuOffset + y * width, vuOffset + y * width + width, vuPlane.bytes, offset);
    }
    return nv21;
  }

  Uint8List _packYuv420(CameraImage image, int width, int height) {
    final uvHeight = height ~/ 2;
    final int uvWidth = width ~/ 2;
    final int totalSize = width * height + uvWidth * uvHeight * 2;
    final Uint8List yuv420 = Uint8List(totalSize);
    final yPlane = image.planes[0];
    final yRowStride = yPlane.bytesPerRow;
    for (int y = 0; y < height; y++) {
      final int offset = y * yRowStride;
      yuv420.setRange(y * width, y * width + width, yPlane.bytes, offset);
    }
    final uPlane = image.planes[1];
    final uRowStride = uPlane.bytesPerRow;
    final int uOffset = width * height;
    for (int y = 0; y < uvHeight; y++) {
      final int offset = y * uRowStride;
      yuv420.setRange(uOffset + y * uvWidth, uOffset + y * uvWidth + uvWidth, uPlane.bytes, offset);
    }
    final vPlane = image.planes[2];
    final vRowStride = vPlane.bytesPerRow;
    final int vOffset = uOffset + uvWidth * uvHeight;
    for (int y = 0; y < uvHeight; y++) {
      final int offset = y * vRowStride;
      yuv420.setRange(vOffset + y * uvWidth, vOffset + y * uvWidth + uvWidth, vPlane.bytes, offset);
    }
    return yuv420;
  }

  Uint8List _packBgra(CameraImage image, int width, int height) {
    final int totalSize = width * height * 4;
    final Uint8List bgra = Uint8List(totalSize);
    final plane = image.planes[0];
    final rowStride = plane.bytesPerRow;
    for (int y = 0; y < height; y++) {
      bgra.setRange(y * width * 4, y * width * 4 + width * 4, plane.bytes, y * rowStride);
    }
    return bgra;
  }

  void _startFaceSharing() {
    _sendMyFace();
    _faceTimer = Timer.periodic(const Duration(milliseconds: 800), (t) {
      _sendMyFace();
    });
  }

  Future<void> _sendMyFace() async {
    if (_gameOver || _camera == null || !_camera!.value.isInitialized) return;
    try {
      final XFile image = await _camera!.takePicture().timeout(const Duration(seconds: 2));
      final file = File(image.path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      if (bytes.length < 100 || bytes.length > 300000) return;
      final String b64 = base64Encode(bytes);
      await FaceShareService.shareMyFaceRaw(matchId: _matchId, playerId: _myId, base64Data: b64);
      if (widget.isLocal) LocalGameService.sendFace(b64);
      if (widget.isWebSocket) WsGameService.sendFace(b64);
      if (widget.isFbOnline) FbOnlineService.sendFace(b64);
    } catch (e) {
      debugPrint('Face send: $e');
    }
  }

  void _watchOpponentFace() {
    FaceShareService.watchOpponentFace(
      matchId: _matchId,
      myId: _myId,
      onPhoto: (base64Photo) {
        if (mounted && !_gameOver) {
          try {
            final bytes = base64Decode(base64Photo);
            if (bytes.length > 50) {
              setState(() { _oppFaceBytes = bytes; _oppFaceLoaded = true; });
            }
          } catch (_) {}
        }
      },
    );
  }

  void _startGameSync() {
    GameSyncService.startGame(
      matchId: _matchId,
      playerId: _myId,
      onOpponentUpdate: (data) {
        if (!mounted || _gameOver) return;
        final oppSmile = (data['opponentSmile'] as num?)?.toDouble() ?? 0.0;
        setState(() {
          _oppSmile = oppSmile;
          _oppStatus = oppSmile > 0.3 ? 'Nervous' : 'Holding';
        });
      },
      onGameEnd: (winner, loser) {
        if (!mounted || _gameOver) return;
        final iWon = winner == _myId;
        _endGame(won: iWon, reason: iWon ? 'opponent_laughed' : 'player_laughed');
      },
    );
    if (widget.isHost) {
      GameSyncService.setGameStarted(_matchId);
    }
  }

  void _startOnlineGame() {
    Stream<Map<String, dynamic>> svc;
    if (widget.isFbOnline) {
      svc = FbOnlineService.messages;
    } else if (widget.isWebSocket) {
      svc = WsGameService.messages;
    } else {
      svc = LocalGameService.messages;
    }
    svc.listen((msg) {
      if (!mounted || _gameOver) return;
      final type = msg['type'] as String?;
      if (type == 'smile') {
        final val = (msg['value'] as num?)?.toDouble() ?? 0.0;
        setState(() {
          _oppSmile = val;
          _oppStatus = val > 0.3 ? 'Nervous' : 'Holding';
        });
        if (val > 0.40 && !_gameOver) {
          _endGame(won: true, reason: 'opponent_laughed');
        }
      } else if (type == 'face') {
        final data = msg['data'] as String?;
        if (data != null && data.length > 50) {
          try {
            final bytes = base64Decode(data);
            setState(() { _oppFaceBytes = bytes; _oppFaceLoaded = true; });
          } catch (_) {}
        }
      } else if (type == 'event') {
        final evt = msg['event'] as String?;
        if (evt == 'laughed' || evt == 'you_won') {
          if (!_gameOver) { _endGame(won: true, reason: 'opponent_laughed'); }
        } else if (evt == 'you_lost' && !_gameOver) {
          _endGame(won: false, reason: 'player_laughed');
        } else if (evt == 'quit') {
          if (!_gameOver) _endGame(won: true, reason: 'opponent_quit');
        } else if (evt == 'opponent_disconnected') {
          setState(() => _oppStatus = 'Reconnecting...');
        } else if (evt == 'opponent_reconnected') {
          setState(() => _oppStatus = 'Ready');
        } else if (evt != null && evt.startsWith('sound_')) {
          final soundIdx = int.tryParse(evt.substring(6)) ?? -1;
          if (soundIdx >= 0) GameSoundService.play(soundIdx);
        }
      }
    });
  }

  void _startPracticeAI() {
    Timer.periodic(const Duration(seconds: 2), (t) {
      if (!mounted || _gameOver) { t.cancel(); return; }
      final rng = Random();
      final aiSmile = (0.2 + rng.nextDouble() * 0.6).clamp(0.0, 1.0);
      setState(() {
        _oppSmile = aiSmile;
        _oppStatus = aiSmile > 0.3 ? 'Nervous' : 'Serious';
      });
      if (aiSmile > 0.40 && !_gameOver) {
        _endGame(won: true, reason: 'ai_laughed');
        t.cancel();
      }
    });
  }

  void _startGame() {
    _detector.start();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _gameOver) { t.cancel(); return; }
      setState(() { _timeLeft++; });
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _confirmQuit() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Game?'),
        content: const Text('You will lose this match.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Stay')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (!_gameOver) {
                if (widget.isFbOnline) { FbOnlineService.sendGameEvent('quit'); }
                if (widget.isWebSocket) { WsGameService.sendGameEvent('quit'); }
                if (widget.isLocal) { LocalGameService.sendGameEvent('quit'); }
                _endGame(won: false, reason: 'quit');
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _doAction(int index) {
    if (_gameOver) return;
    GameSoundService.play(index);
    if (widget.isLocal) LocalGameService.sendGameEvent('sound_$index');
    if (widget.isWebSocket) WsGameService.sendGameEvent('sound_$index');
    if (widget.isFbOnline) FbOnlineService.sendGameEvent('sound_$index');

    String msg;
    switch (index) {
      case 0:
        msg = ['Pulling a funny face!', 'You made a silly face!', 'Check out THIS expression!'][Random().nextInt(3)];
        break;
      case 1:
        msg = _jokes[Random().nextInt(_jokes.length)];
        break;
      case 2:
        msg = ['*FART NOISE*', '*CLUCK CLUCK*', '*QUACK QUACK*'][Random().nextInt(3)];
        break;
      case 3:
        msg = ['*OOH OOH AAH AAH*', 'Honk honk!', '*RAWRRRR*'][Random().nextInt(3)];
        break;
      case 4:
        msg = ['Can\'t handle the pressure?', 'You\'re about to break!', 'I see that smile forming!'][Random().nextInt(3)];
        break;
      case 5:
        msg = ['*WAVING WILDLY*', '*DANCING BADLY*', '*DOING A SILLY WALK*'][Random().nextInt(3)];
        break;
      default:
        msg = '';
    }
    setState(() => _actionMessage = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() {
            if (_actionMessage == msg) _actionMessage = '';
          });
    });
  }

  void _endGame({required bool won, required String reason}) {
    if (_gameOver || _gameEnding) return;
    _gameEnding = true;
    _gameOver = true;
    _camera?.stopImageStream();
    _faceTimer?.cancel();
    _countdownTimer?.cancel();
    _detector.stop();
    _winner = won ? 'You' : widget.opponentName;

    LobbyService.saveGameResult(won: won, opponent: widget.opponentName);

    GameSyncService.dispose();
    FaceShareService.dispose();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GameOverScreen(
            won: won,
            opponent: widget.opponentName,
            reason: reason,
            isFbOnline: widget.isFbOnline,
            isLocal: widget.isLocal,
            isWebSocket: widget.isWebSocket,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraTimeout?.cancel();
    _camera?.stopImageStream();
    _faceTimer?.cancel();
    _countdownTimer?.cancel();
    _camera?.dispose();
    _detector.dispose();
    GameSyncService.dispose();
    FaceShareService.dispose();
    LocalGameService.dispose();
    FbOnlineService.dispose();
    WsGameService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.videocam_off, size: 64, color: Colors.white38),
              const SizedBox(height: 16),
              Text(_cameraError!, style: const TextStyle(color: Colors.white54, fontSize: 16)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  setState(() => _cameraError = null);
                  _initCamera();
                },
                child: const Text('Retry'),
              ),
            ]),
          ),
        ),
      );
    }

    if (!_cameraReady) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFFFF6584))),
              const SizedBox(height: 24),
              const Text('Laugh Royale', style: TextStyle(color: Color(0xFFFF6584), fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('VS ${widget.opponentName}', style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('Starting camera...', style: TextStyle(color: Colors.white54, fontSize: 14)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(),
          Expanded(
            child: Column(children: [
              Expanded(flex: 1, child: _buildOpponentHalf()),
              _buildDivider(),
              Expanded(flex: 1, child: _buildPlayerHalf()),
            ]),
          ),
          _buildActionBar(),
          _buildStatusMessage(),
        ]),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF0A0A14),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.timer, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Text(_formatTime(_timeLeft), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.greenAccent.withAlpha(100)),
          ),
          child: const Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.greenAccent, letterSpacing: 2)),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _miniSmile(widget.opponentName, _oppSmile),
          const SizedBox(width: 8),
          _miniSmile('YOU', _mySmile),
        ]),
        GestureDetector(
          onTap: () => _confirmQuit(),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.white.withAlpha(10), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.close, size: 18, color: Colors.white30),
          ),
        ),
      ]),
    );
  }

  Widget _miniSmile(String label, double val) {
    final displayLabel = label.length > 6 ? '${label.substring(0, 6)}..' : label;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(displayLabel, style: TextStyle(fontSize: 8, color: val > 0.55 ? Colors.redAccent : Colors.white38)),
      const SizedBox(height: 2),
      Text('${(val * 100).toInt()}%', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: val > 0.55 ? Colors.redAccent : Colors.white54)),
    ]);
  }

  Widget _buildOpponentHalf() {
    return Container(
      color: const Color(0xFF0A0A14),
      child: Stack(fit: StackFit.expand, children: [
        if (_oppFaceLoaded && _oppFaceBytes != null)
          Positioned.fill(
            child: Image.memory(
              _oppFaceBytes!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _oppPlaceholder(),
            ),
          )
        else
          Positioned.fill(child: _oppPlaceholder()),
        Positioned(right: 8, top: 0, bottom: 0, child: _verticalMeter(_oppSmile, const Color(0xFF6C63FF))),
        Positioned(left: 8, top: 8, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.black.withAlpha(120), borderRadius: BorderRadius.circular(8)),
            child: const Text('OPPONENT', style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 2)),
          ),
          const SizedBox(height: 2),
          Text(widget.opponentName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.black.withAlpha(120), borderRadius: BorderRadius.circular(6)),
            child: Text(_oppStatus, style: TextStyle(color: _oppSmile > 0.5 ? Colors.redAccent : Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.w600)),
          ),
        ])),
      ]),
    );
  }

  Widget _oppPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF6C63FF).withAlpha(20), const Color(0xFFFF6584).withAlpha(10)],
        ),
      ),
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6C63FF).withAlpha(30),
              border: Border.all(color: const Color(0xFF6C63FF).withAlpha(80), width: 3),
            ),
            child: const Center(child: Icon(Icons.person, size: 40, color: Colors.white24)),
          ),
          const SizedBox(height: 12),
          Text(widget.opponentName, style: const TextStyle(color: Colors.white38, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Waiting...', style: TextStyle(color: Colors.white10, fontSize: 10)),
        ]),
      ),
    );
  }

  Widget _buildPlayerHalf() {
    return Container(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        Positioned.fill(
          child: ClipRRect(
            child: CameraPreview(_camera!),
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, height: 50, child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)])),
        )),
        Positioned(left: 12, bottom: 8, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Colors.black.withAlpha(140), borderRadius: BorderRadius.circular(12)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.videocam, size: 12, color: Colors.redAccent),
            SizedBox(width: 4),
            Text('YOU', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
        )),
        Positioned(right: 8, top: 0, bottom: 0, child: _verticalMeter(_mySmile, Colors.redAccent)),
        if (_mySmile > 0.15)
          Positioned(left: 40, right: 40, top: 8, child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: _mySmile > 0.30 ? Colors.red.withAlpha(200) : Colors.orange.withAlpha(180),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _mySmile > 0.30 ? 'NERVOUS!' : 'Keep a straight face!',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          )),
      ]),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFFFF6584).withAlpha(80), const Color(0xFF6C63FF).withAlpha(80)]),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 120, height: 3,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFF6584), Color(0xFF6C63FF)]),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ]),
    );
  }

  Widget _verticalMeter(double value, Color color) {
    final pct = (value * 100).toInt();
    final danger = value > 0.30;
    return SizedBox(
      width: 32,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('$pct%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: danger ? Colors.redAccent : Colors.white38)),
          const SizedBox(height: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(alignment: Alignment.bottomCenter, children: [
                Container(decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(6))),
                LayoutBuilder(builder: (ctx, constraints) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: (value.clamp(0.0, 1.0) * constraints.maxHeight),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter, end: Alignment.topCenter,
                        colors: danger ? [Colors.redAccent, Colors.orange, Colors.yellow] : [color, color.withAlpha(150)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: danger ? [BoxShadow(color: Colors.redAccent.withAlpha(80), blurRadius: 8)] : null,
                    ),
                  );
                }),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      color: const Color(0xFF0F0F1A),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _actions.map((a) {
          final color = Color(a['color'] as int);
          return GestureDetector(
            onTap: _gameOver ? null : () => _doAction(_actions.indexOf(a)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 18, backgroundColor: color.withAlpha(40), child: Icon(a['icon'] as IconData, color: color, size: 18)),
              const SizedBox(height: 2),
              Text(a['label'] as String, style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 7)),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusMessage() {
    if (_actionMessage.isEmpty && !_gameOver) return const SizedBox.shrink();
    final Color bg = _gameOver
        ? (_winner == 'You' ? Colors.amber.withAlpha(220) : Colors.redAccent.withAlpha(220))
        : const Color(0xFF6C63FF).withAlpha(200);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: bg,
      child: Text(
        _gameOver
            ? (_winner == 'You' ? 'YOU WIN! ${widget.opponentName} got nervous!' : 'YOU GOT NERVOUS! ${widget.opponentName} wins!')
            : _actionMessage,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }
}
