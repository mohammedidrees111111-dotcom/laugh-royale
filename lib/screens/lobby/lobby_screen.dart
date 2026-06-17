import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/auth_service.dart';
import '../../services/lobby_service.dart';
import '../../services/ws_game_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../game/game_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _searching = false;
  Map<String, int> _stats = {};
  bool _creatingRoom = false;
  bool _joiningRoom = false;
  String? _privateRoomCode;
  String? _opponentName;
  String? _opponentId;
  bool _userCancelled = false;
  int _warmupSeconds = 0;
  Timer? _warmupTimer;
  StreamSubscription? _roomSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStats();
    });
  }

  Future<void> _loadStats() async {
    final stats = await LobbyService.getStats();
    if (mounted) setState(() => _stats = stats);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  void _startWarmupTimer() {
    _warmupSeconds = 0;
    _warmupTimer?.cancel();
    _warmupTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _warmupSeconds++);
    });
  }

  void _stopWarmupTimer() {
    _warmupTimer?.cancel();
    _warmupTimer = null;
  }

  String get _warmupText {
    if (_warmupSeconds < 10) return 'Waking up game server...';
    if (_warmupSeconds < 25) return 'Server is waking up (cold start)...';
    if (_warmupSeconds < 40) return 'Almost ready...';
    return 'Still waiting for server...';
  }

  // ──────────────────────────────────────────────────────────────
  //  RANDOM MATCH (WebSocket matchmaking)
  // ──────────────────────────────────────────────────────────────

  Future<void> _startRandomMatch() async {
    if (_searching) return;

    final id = AuthService.currentUserId ?? 'R${Random().nextInt(99999)}';
    final name = AuthService.displayName;

    setState(() {
      _loading = true;
      _searching = true;
      _opponentName = null;
      _userCancelled = false;
    });

    _startWarmupTimer();

    debugPrint('[LOBBY] Starting random match for $name ($id)');

    Permission.microphone.request();

    final result = await WsGameService.joinMatchmakingQueue(
      playerId: id,
      playerName: name,
    );

    _stopWarmupTimer();

    if (!mounted) return;

    if (_userCancelled) {
      setState(() { _loading = false; _searching = false; });
      return;
    }

    if (result != null) {
      final roomId = result['roomId'] as String;
      final oppName = result['opponentName'] as String? ?? 'Player';
      final role = result['role'] as String? ?? 'host';

      debugPrint('[LOBBY] Matched! Room: $roomId, Opponent: $oppName, Role: $role');

      setState(() {
        _loading = false;
        _searching = false;
      });

      _gotoGame(
        roomCode: roomId,
        opponentId: WsGameService.opponentId ?? 'opp',
        opponentName: oppName,
        isWebSocket: true,
        isHost: role == 'host',
      );
    } else {
      setState(() { _loading = false; _searching = false; });

      if (!WsGameService.isConnected && !_userCancelled) {
        _showOfflineDialog();
      } else if (!_userCancelled) {
        _snack('No player found. Try again.');
      }
    }
  }

  void _showOfflineDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server Unreachable'),
        content: const Text(
          'Could not reach the game server.\n\n'
          'This may be because:\n'
          '  1. Server is waking up (retry in 30s)\n'
          '  2. No internet connection\n\n'
          'Try again or create a Private Room.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () { Navigator.pop(ctx); _startRandomMatch(); },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  //  PRIVATE ROOM (WebSocket — same server as random match)
  // ──────────────────────────────────────────────────────────────

  Future<void> _createPrivateRoom() async {
    if (_creatingRoom) return;

    final id = AuthService.currentUserId ?? 'P${Random().nextInt(99999)}';
    final name = AuthService.displayName;

    setState(() { _creatingRoom = true; _privateRoomCode = null; });

    _startWarmupTimer();

    final result = await WsGameService.hostRoom(
      playerId: id,
    );

    _stopWarmupTimer();

    if (!mounted) return;

    if (result != null) {
      final code = result['code'] as String;
      setState(() {
        _creatingRoom = false;
        _privateRoomCode = code;
      });

      _roomSub?.cancel();
      _roomSub = WsGameService.messages.listen((msg) {
        if (!mounted) return;
        if (msg['type'] == 'player_joined') {
          final oppId = msg['id'] as String? ?? 'guest';
          final oppName = msg['name'] as String? ?? 'Player';
          setState(() {
            _opponentId = oppId;
            _opponentName = oppName;
          });
          _gotoGame(
            roomCode: code,
            opponentId: oppId,
            opponentName: oppName,
            isWebSocket: true,
          );
        }
      });
    } else {
      setState(() { _creatingRoom = false; });
      _snack('Failed to create room. Check connection.');
    }
  }

  Future<void> _joinPrivateRoom() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) { _snack('Enter room code'); return; }

    final id = AuthService.currentUserId ?? 'J${Random().nextInt(99999)}';
    final name = AuthService.displayName;

    setState(() => _joiningRoom = true);

    _startWarmupTimer();

    final ok = await WsGameService.joinRoom(
      code: code,
      playerId: id,
      playerName: name,
    );

    _stopWarmupTimer();

    if (!mounted) return;

    if (ok) {
      setState(() {
        _joiningRoom = false;
        _opponentId = WsGameService.opponentId;
        _opponentName = WsGameService.opponentName;
      });

      _gotoGame(
        roomCode: code,
        opponentId: WsGameService.opponentId ?? 'host',
        opponentName: WsGameService.opponentName ?? 'Host',
        isWebSocket: true,
        isHost: false,
      );
    } else {
      setState(() => _joiningRoom = false);
      _snack('Room not found or already full.');
    }
  }

  void _cancelPrivateRoom() {
    _roomSub?.cancel();
    _roomSub = null;
    WsGameService.dispose();
    setState(() {
      _privateRoomCode = null;
      _opponentName = null;
    });
  }

  // ──────────────────────────────────────────────────────────────
  //  NAVIGATE TO GAME
  // ──────────────────────────────────────────────────────────────

  void _gotoGame({
    required String roomCode,
    required String opponentId,
    required String opponentName,
    bool isHost = true,
    bool isWebSocket = false,
  }) {
    _roomSub?.cancel();
    _roomSub = null;

    if (isWebSocket) {
      WsGameService.startGame();
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(
      matchId: roomCode,
      opponentId: opponentId,
      opponentName: opponentName,
      isHost: isHost,
      isWebSocket: isWebSocket,
    ))).then((_) {
      WsGameService.dispose();
      _loadStats();
      if (mounted) {
        setState(() {
          _privateRoomCode = null;
          _opponentName = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _warmupTimer?.cancel();
    _roomSub?.cancel();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────
  //  UI
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = AuthService.displayName;

    return Scaffold(
      appBar: AppBar(title: Text(L.of(context).lobby)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _buildPlayerCard(theme, name),
          const SizedBox(height: 16),

          if (_searching)
            _buildSearchingUI()
          else ...[
            _bigBtn('RANDOM MATCH', Icons.shuffle, const Color(0xFFFF6584), _startRandomMatch),
            const SizedBox(height: 16),
          ],

          _sectionHeader('PRIVATE ROOM'),
          const SizedBox(height: 8),

          if (_creatingRoom || _joiningRoom)
            _buildConnectingUI()
          else if (_privateRoomCode != null && _opponentName == null)
            _buildRoomCreatedUI()
          else if (_opponentName != null && _privateRoomCode != null)
            _buildConnectedUI()
          else
            _buildPrivateRoomForm(),
        ]),
      ),
    );
  }

  Widget _buildPlayerCard(ThemeData theme, String name) {
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              _searching ? 'Searching for opponent...' : _privateRoomCode != null ? 'Room active' : 'Ready',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        )),
        Column(children: [
          Text('${_stats['wins'] ?? 0}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
          const Text('Wins', style: TextStyle(fontSize: 10, color: Colors.white38)),
        ]),
        const SizedBox(width: 10),
        Column(children: [
          Text('${_stats['losses'] ?? 0}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent)),
          const Text('Losses', style: TextStyle(fontSize: 10, color: Colors.white38)),
        ]),
      ]),
    ));
  }

  Widget _buildSearchingUI() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6584).withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFF6584).withOpacity(0.2)),
      ),
      child: Column(children: [
        const SizedBox(
          width: 56, height: 56,
          child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFFFF6584)),
        ),
        const SizedBox(height: 20),
        const Text('CONNECTING TO SERVER',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 8),
        Text(_warmupText,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 4),
        Text('${_warmupSeconds}s elapsed',
            style: const TextStyle(color: Colors.white30, fontSize: 11)),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () {
            _userCancelled = true;
            _stopWarmupTimer();
            setState(() { _searching = false; _loading = false; });
            WsGameService.leaveMatchmakingQueue();
          },
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white38),
          child: const Text('Cancel'),
        ),
      ]),
    );
  }

  Widget _buildConnectingUI() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2)),
      ),
      child: Column(children: [
        const SizedBox(
          width: 40, height: 40,
          child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF6C63FF)),
        ),
        const SizedBox(height: 12),
        const Text('Connecting to server...',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(_warmupText, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            _stopWarmupTimer();
            setState(() { _creatingRoom = false; _joiningRoom = false; });
            WsGameService.dispose();
          },
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white38),
          child: const Text('Cancel'),
        ),
      ]),
    );
  }

  Widget _buildRoomCreatedUI() {
    return Card(
      color: const Color(0xFF6C63FF).withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.vpn_lock, color: Color(0xFF6C63FF)),
            SizedBox(width: 8),
            Text('Room Created', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const SizedBox(height: 16),
          const Text('Share this code:', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
            ),
            child: Text(_privateRoomCode!,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 6, color: Color(0xFF6C63FF))),
          ),
          const SizedBox(height: 16),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Waiting for opponent...', style: TextStyle(color: Colors.white54)),
          ]),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _cancelPrivateRoom,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent.withOpacity(0.7)),
            child: const Text('Cancel'),
          ),
        ]),
      ),
    );
  }

  Widget _buildConnectedUI() {
    return Card(
      color: const Color(0xFF00E676).withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Icon(Icons.check_circle, size: 56, color: Color(0xFF00E676)),
          const SizedBox(height: 12),
          const Text('PLAYER FOUND!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('vs $_opponentName', style: const TextStyle(fontSize: 16, color: Color(0xFF6C63FF))),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 52,
            child: FilledButton.icon(
              onPressed: () {
                _gotoGame(
                  roomCode: _privateRoomCode!,
                  opponentId: _opponentId ?? 'opp',
                  opponentName: _opponentName!,
                  isWebSocket: true,
                  isHost: true,
                );
              },
              icon: const Icon(Icons.play_arrow, size: 28),
              label: const Text('START GAME', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildPrivateRoomForm() {
    return Column(children: [
      SizedBox(
        width: double.infinity, height: 48,
        child: FilledButton.icon(
          onPressed: _creatingRoom ? null : _createPrivateRoom,
          icon: _creatingRoom
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.add, size: 20),
          label: Text(_creatingRoom ? 'Creating...' : 'Create Room', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        const SizedBox(width: 4),
        const Text('or', style: TextStyle(color: Colors.white38, fontSize: 13)),
        const SizedBox(width: 4),
        const Expanded(child: Divider()),
        const SizedBox(width: 8),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(
          controller: _codeCtrl,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: InputDecoration(
            hintText: 'Enter room code',
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            isDense: true,
          ),
        )),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _joiningRoom ? null : _joinPrivateRoom,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00D9FF),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _joiningRoom
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Join', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ]),
      const SizedBox(height: 40),
    ]);
  }

  Widget _bigBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: FilledButton.icon(
        onPressed: _loading || _searching ? null : onTap,
        icon: Icon(icon, size: 22),
        label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: color == const Color(0xFF00E676) ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(title,
              style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
        ),
        const Expanded(child: Divider()),
      ]),
    );
  }
}
