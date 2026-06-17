// laugh-royale/lib/screens/game/game_screen.dart
// FIXED VERSION - With proper smile detection and winner determination

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import '../../services/smile_detector.dart';
import '../../services/lobby_service.dart';
import '../../services/auth_service.dart';
import '../../services/game_sync_service.dart';
import '../../services/face_share_service.dart';
import '../../services/local_game_service.dart';
import '../../services/ws_game_service.dart';
import '../../services/fb_online_service.dart';
import '../../services/game_sound_service.dart';
import '../../services/voice_chat_service.dart';
import 'game_over_screen.dart';

class GameScreen extends StatefulWidget {
  final String matchId;
  final String opponentId;
  final String opponentName;
  final bool isHost;
  final bool isLocal;
  final bool isWebSocket;
  final bool isFbOnline;

  const GameScreen({
    super.key,
    required this.matchId,
    required this.opponentId,
    required this.opponentName,
    this.isHost = true,
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
  int _totalFrames = 0;
  int _facesFound = 0;
  int _smilesDetected = 0;
  int _framesProcessed = 0;

  // ========== FIXED: Track who laughed FIRST ==========
  static const double _laughThreshold = 0.35;
  static const double _smileResetThreshold = 0.20;

  bool _iLaughed = false;
  bool _opponentLaughed = false;
  DateTime? _myLaughTime;
  DateTime? _opponentLaughTime;
  bool _gameEnding = false;

  // Track if we already sent the laugh event (prevent duplicates)
  bool _laughEventSent = false;

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
  StreamSubscription? _wsSubscription;
  Timer? _opponentLaughTimeout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detector = SmileDetector();
    GameSoundService.init();
    _myId = AuthService.currentUserId ?? 'unknown';
    _matchId = widget.matchId;
    _initCamera();

    if (widget.isLocal || widget.isWebSocket || widget.isFbOnline) {
      _startOnlineGame();
    } else {
      _startGameSync();
    }

    if (widget.isWebSocket) {
      Future.delayed(const Duration(milliseconds: 500), _startVoiceChat);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _detector.stop();
      _camera?.stopImageStream();
    } else if (state == AppLifecycleState.resumed && !_gameOver) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        debugPrint('[CAMERA] Camera permission DENIED');
        if (mounted) setState(() => _cameraError = 'Camera permission denied');
        return;
      }
      debugPrint('[CAMERA] Camera permission GRANTED');
    } catch (e) {
      debugPrint('[CAMERA] Permission check error: $e');
    }

    try {
      _cameras = await availableCameras().timeout(const Duration(seconds: 5));
    } catch (_) {
      _cameras = null;
    }

    if (_cameras == null || _cameras!.isEmpty) {
      if (mounted) setState(() => _cameraError = 'No camera available');
      return;
    }

    CameraDescription frontCamera;
    try {
      frontCamera = _cameras!.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
      );
    } catch (_) {
      frontCamera = _cameras!.first;
    }

    _camera = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _camera!.initialize();
      debugPrint('[CAMERA] Initialized successfully');

      if (mounted) {
        setState(() {
          _cameraReady = true;
          _cameraError = null;
        });
      }

      _detector.start();
      _camera!.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('[CAMERA] Initialize error: $e');
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  void _onCameraFrame(CameraImage image) {
    if (_gameOver || _gameEnding) return;
    if (_processingFrame) {
      _pendingFrame = image;
      return;
    }
    _processFrame(image);
  }

  Future<void> _processFrame(CameraImage image) async {
    _processingFrame = true;
    _totalFrames++;

    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) {
        _processingFrame = false;
        return;
      }

      final smile = await _detector.processFrame(inputImage);

      if (mounted) {
        setState(() {
          _mySmile = smile;
          if (smile > 0) _facesFound++;
          if (smile > _laughThreshold) _smilesDetected++;
        });
      }

      // ========== FIXED: Detect laugh and determine winner ==========
      _checkForLaugh(smile);

    } catch (e) {
      debugPrint('[GAME] Frame processing error: $e');
    }

    _processingFrame = false;

    if (_pendingFrame != null) {
      final next = _pendingFrame!;
      _pendingFrame = null;
      _processFrame(next);
    }
  }

  // ========== FIXED: Complete laugh detection logic ==========
  void _checkForLaugh(double smile) {
    if (_gameOver || _gameEnding) return;

    // Check if I just laughed (crossed threshold)
    if (smile > _laughThreshold && !_iLaughed && !_laughEventSent) {
      _iLaughed = true;
      _myLaughTime = DateTime.now();
      debugPrint('[GAME] 😐 I LAUGHED at ${_myLaughTime!.toIso8601String()}!');

      // Send laugh event to server with timestamp
      WsGameService.sendLaughEvent(DateTime.now().millisecondsSinceEpoch);
      _laughEventSent = true;

      // Check if opponent already laughed
      if (_opponentLaughed && _opponentLaughTime != null) {
        _determineWinner();
      } else {
        // Wait for opponent's laugh (timeout after 3 seconds)
        _opponentLaughTimeout?.cancel();
        _opponentLaughTimeout = Timer(const Duration(seconds: 3), () {
          if (!_gameOver && !_gameEnding) {
            debugPrint('[GAME] Opponent did not laugh in time - I WIN!');
            _endGame(_myId, 'opponent_timeout');
          }
        });
      }
    }

    // Check if smile dropped below threshold (reset)
    if (smile < _smileResetThreshold) {
      if (_iLaughed && !_opponentLaughed) {
        debugPrint('[GAME] My smile dropped - I can still be caught!');
        // Don't reset completely, just mark we smiled but can still win if opponent doesn't laugh
      }
    }
  }

  // ========== FIXED: Handle opponent's laugh ==========
  void _handleOpponentLaugh(int timestamp) {
    if (_gameOver || _gameEnding) return;

    _opponentLaughed = true;
    _opponentLaughTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    debugPrint('[GAME] 😤 OPPONENT LAUGHED at ${_opponentLaughTime!.toIso8601String()}!');

    // Cancel my timeout
    _opponentLaughTimeout?.cancel();

    // Now determine who laughed FIRST
    _determineWinner();
  }

  // ========== FIXED: Compare timestamps to determine winner ==========
  void _determineWinner() {
    if (_gameOver || _gameEnding) return;

    _gameEnding = true;
    _opponentLaughTimeout?.cancel();

    if (_myLaughTime != null && _opponentLaughTime != null) {
      // Both laughed - compare timestamps
      final myTime = _myLaughTime!.millisecondsSinceEpoch;
      final oppTime = _opponentLaughTime!.millisecondsSinceEpoch;

      debugPrint('[GAME] Comparing laugh times:');
      debugPrint('[GAME]   My laugh: ${_myLaughTime!.toIso8601String()}');
      debugPrint('[GAME]   Opp laugh: ${_opponentLaughTime!.toIso8601String()}');
      debugPrint('[GAME]   Difference: ${(oppTime - myTime)}ms');

      if (myTime <= oppTime) {
        // I laughed first (or same time) - I LOSE
        debugPrint('[GAME] 😢 I LAUGHED FIRST - I LOSE!');
        _endGame(widget.opponentId, 'i_laughed_first');
      } else {
        // Opponent laughed first - I WIN
        debugPrint('[GAME] 🎉 OPPONENT LAUGHED FIRST - I WIN!');
        _endGame(_myId, 'opponent_laughed_first');
      }
    } else if (_opponentLaughed && !_iLaughed) {
      // Only opponent laughed - I WIN
      debugPrint('[GAME] 🎉 Opponent laughed but I didn't - I WIN!');
      _endGame(_myId, 'opponent_laughed');
    } else if (_iLaughed && !_opponentLaughed) {
      // Only I laughed - I LOSE
      debugPrint('[GAME] 😢 I laughed but opponent didn't - I LOSE!');
      _endGame(widget.opponentId, 'i_laughed');
    } else {
      // Edge case - should not happen
      debugPrint('[GAME] ⚠️ No clear winner - declaring tie');
      _endGame(null, 'tie');
    }
  }

  void _endGame(String? winnerId, String reason) {
    if (_gameOver) return;
    _gameOver = true;

    _faceTimer?.cancel();
    _countdownTimer?.cancel();
    _opponentLaughTimeout?.cancel();
    _camera?.stopImageStream();
    _detector.stop();

    GameSoundService.playGameOver();

    final iWon = winnerId == _myId;
    _winner = iWon ? 'You Won!' : 'You Lost!';

    debugPrint('[GAME] Game Over - Winner: $_winner (reason: $reason)');

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GameOverScreen(
            winner: _winner!,
            isWinner: iWon,
            myId: _myId,
            matchId: _matchId,
          ),
        ),
      );
    }
  }

  void _startOnlineGame() {
    debugPrint('[GAME] Starting online game with WebSocket...');

    _wsSubscription = WsGameService.messages.listen(_onWsMessage);

    _startCountdown();
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;

    if (type == 'event') {
      final event = msg['event'] as String?;
      debugPrint('[GAME] Event received: $event');

      // ========== FIXED: Handle opponent laugh event ==========
      if (event == 'laughed') {
        final timestamp = msg['timestamp'] as int?;
        if (timestamp != null) {
          debugPrint('[GAME] Opponent laughed at timestamp: $timestamp');
          _handleOpponentLaugh(timestamp);
        }
      }

      if (event == 'started') {
        _startCountdown();
      }
      if (event == 'opponent_disconnected') {
        debugPrint('[GAME] Opponent disconnected - I WIN!');
        _endGame(_myId, 'opponent_disconnected');
      }
    }

    if (type == 'smile') {
      final value = (msg['value'] as num?)?.toDouble() ?? 0.0;
      if (mounted) setState(() => _oppSmile = value);
    }

    if (type == 'opponent_face') {
      final data = msg['data'] as String?;
      if (data != null && mounted) {
        setState(() {
          _oppFaceBase64 = data;
          _oppFaceBytes = base64Decode(data);
          _oppFaceLoaded = true;
        });
      }
    }

    if (type == 'game_action') {
      final action = msg['action'] as String?;
      final value = msg['value'] as String?;
      if (action != null && mounted) {
        setState(() {
          _actionMessage = value ?? '';
          _oppStatus = action;
        });
        GameSoundService.playAction();
      }
    }
  }

  void _sendSmileValue() {
    if (!_iLaughed) {
      WsGameService.sendSmile(_mySmile);
    }
  }

  void _startCountdown() {
    _timeLeft = 3;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_timeLeft > 0) {
            _timeLeft--;
            if (_timeLeft == 0) {
              _oppStatus = 'Go!';
              _startGameplay();
              timer.cancel();
            }
          }
        });
      }
    });
  }

  void _startGameplay() {
    _faceTimer?.cancel();
    _faceTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _sendSmileValue();
      _shareMyFace();
    });
    GameSoundService.playStart();
  }

  void _shareMyFace() {
    if (_oppFaceLoaded || _camera == null || !_cameraReady) return;
    if (_frameSkipCounter++ % 10 != 0) return;
    _frameSkipCounter = 0;
  }

  void _sendAction(int index) {
    if (index >= _actions.length) return;
    final action = _actions[index];
    _oppStatus = action['label'] as String;

    if (index == 1 && _jokes.isNotEmpty) {
      final rng = Random();
      final joke = _jokes[rng.nextInt(_jokes.length)];
      setState(() => _actionMessage = joke);
      WsGameService.sendGameAction('joke', joke);
    } else {
      setState(() => _actionMessage = '');
      WsGameService.sendGameAction(action['label'] as String, '');
    }

    GameSoundService.playAction();
  }

  void _startVoiceChat() async {
    if (!widget.isWebSocket) return;

    debugPrint('[GAME] Starting voice chat...');
    final success = await VoiceChatService.startVoiceChat(
      roomCode: _matchId,
      isHost: widget.isHost,
    );

    if (success) {
      debugPrint('[GAME] Voice chat started successfully');
    } else {
      debugPrint('[GAME] Voice chat failed to start');
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final camera = _camera;
      if (camera == null) return null;

      final rotation = InputImageRotationValue.fromRawValue(camera.description.sensorOrientation);
      if (rotation == null) return null;

      final format = Platform.isAndroid
          ? InputImageFormat.nv21
          : InputImageFormat.bgra8888;

      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('[CAMERA] Image conversion error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _faceTimer?.cancel();
    _countdownTimer?.cancel();
    _opponentLaughTimeout?.cancel();
    _camera?.dispose();
    _camera?.stopImageStream();
    _detector.dispose();
    _wsSubscription?.cancel();
    VoiceChatService.stopVoiceChat();
    super.dispose();
  }

  // ... UI Widget build methods remain the same ...
  // (keeping the existing UI code unchanged)

  @override
  Widget build(BuildContext context) {
    // ... (keep existing build method)
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _buildMainContent(),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$_timeLeft',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            _oppStatus,
            style: const TextStyle(
              fontSize: 24,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Row(
      children: [
        Expanded(
          child: _buildMyCamera(),
        ),
        Container(
          width: 2,
          color: Colors.white24,
        ),
        Expanded(
          child: _buildOpponentView(),
        ),
      ],
    );
  }

  Widget _buildMyCamera() {
    if (_cameraError != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Text(
            _cameraError!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!_cameraReady || _camera == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: Transform.scale(
            scale: 1.0,
            child: CameraPreview(_camera!),
          ),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Your Smile: ${(_mySmile * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: _mySmile,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _mySmile > _laughThreshold
                        ? Colors.red
                        : Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_iLaughed)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '😐 LAUGHED!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOpponentView() {
    if (!_oppFaceLoaded || _oppFaceBytes == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Waiting for opponent...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: Colors.black,
          child: Image.memory(
            _oppFaceBytes!,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Opponent Smile: ${(_oppSmile * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: _oppSmile,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _oppSmile > _laughThreshold
                        ? Colors.red
                        : Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_opponentLaughed)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '😤 LAUGHED!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_actionMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _actionMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _actions.length,
              itemBuilder: (context, index) {
                final action = _actions[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ElevatedButton(
                    onPressed: _gameOver ? null : () => _sendAction(index),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(action['color'] as int),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          action['icon'] as IconData,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          action['label'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
