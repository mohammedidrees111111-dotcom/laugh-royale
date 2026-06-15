import 'dart:math';
import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/lobby_service.dart';
import '../../services/local_game_service.dart';
import '../../services/ws_game_service.dart';
import '../../services/fb_online_service.dart';
import '../game/test_smile_screen.dart';
import '../game/game_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _ipCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _searching = false;
  bool _hosting = false;
  bool _connecting = false;
  Map<String, int> _stats = {};
  int? _hostPort;
  String? _opponentName;
  String? _localIp;
  String? _searchRoomCode;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  Future<void> _loadStats() async {
    final stats = await LobbyService.getStats();
    if (mounted) setState(() => _stats = stats);
  }

  void _startPractice() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(
      matchId: 'p_${DateTime.now().millisecondsSinceEpoch}',
      opponentId: 'ai',
      opponentName: 'AI Bot',
      isPractice: true,
    ))).then((_) => _loadStats());
  }

  void _openTestSmile() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TestSmileScreen()));
  }

  // ──────────────────────────────────────────────────────────────
  //  LOCAL WIFI
  // ──────────────────────────────────────────────────────────────

  Future<void> _hostLocal() async {
    final id = AuthService.currentUserId ?? 'L${Random().nextInt(99999)}';
    final name = AuthService.displayName;
    setState(() => _hosting = true);
    try {
      final port = await LocalGameService.startHosting(playerName: name, playerId: id);
      if (!mounted) return;
      _hostPort = port;
      _localIp = await LocalGameService.getLocalIp();
      setState(() {});
      LocalGameService.messages.listen((msg) {
        if (!mounted || _opponentName != null) return;
        if (msg['type'] == 'handshake') setState(() => _opponentName = msg['name'] as String? ?? 'Player2');
      });
    } catch (e) {
      if (mounted) { setState(() => _hosting = false); _snack('Failed'); }
    }
  }

  void _startLocalGame() {
    LocalGameService.sendGameEvent('start');
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(
      matchId: 'L_${DateTime.now().millisecondsSinceEpoch}',
      opponentId: 'local',
      opponentName: _opponentName ?? 'Player2',
      isLocal: true,
    ))).then((_) { LocalGameService.dispose(); _loadStats(); });
  }

  Future<void> _joinLocal() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) { _snack('Enter host IP'); return; }
    final id = AuthService.currentUserId ?? 'L${Random().nextInt(99999)}';
    final name = AuthService.displayName;
    setState(() => _connecting = true);
    final ok = await LocalGameService.connectToHost(
        host: ip, port: 9999, playerName: name, playerId: id);
    if (!mounted) return;
    if (ok) {
      setState(() => _connecting = false);
      LocalGameService.messages.listen((msg) {
        if (!mounted) return;
        final t = msg['type'] as String?;
        if (t == 'handshake') setState(() => _opponentName = msg['name'] as String? ?? 'Host');
        if (t == 'event' && msg['event'] == 'start') _gotoGame('L', _opponentName ?? 'Host', isLocal: true);
      });
    } else {
      setState(() => _connecting = false);
      _snack('Could not connect');
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  RANDOM MATCH (WebSocket matchmaking) — CRITICAL FIX
  // ──────────────────────────────────────────────────────────────

  Future<void> _startRandomMatch() async {
    if (_searching) return;

    final id = AuthService.currentUserId ?? 'R${Random().nextInt(99999)}';
    final name = AuthService.displayName;

    setState(() {
      _loading = true;
      _searching = true;
      _opponentName = null;
    });

    debugPrint('[LOBBY] Starting random match for $name ($id)');

    final result = await WsGameService.joinMatchmakingQueue(
      playerId: id,
      playerName: name,
    );

    if (!mounted) return;

    if (result != null) {
      final roomId = result['roomId'] as String;
      final oppName = result['opponentName'] as String? ?? 'Player';
      final role = result['role'] as String? ?? 'host';

      debugPrint('[LOBBY] Matched! Room: $roomId, Opponent: $oppName, Role: $role');

      setState(() {
        _loading = false;
        _searching = false;
        _opponentName = oppName;
        _searchRoomCode = roomId;
      });

      _gotoGame('R', oppName, isWebSocket: true, roomCode: roomId);
    } else {
      debugPrint('[LOBBY] Matchmaking returned null — no match');

      setState(() {
        _loading = false;
        _searching = false;
      });

      if (!WsGameService.isConnected) {
        _showOfflineDialog(id, name);
      } else {
        _snack('No player found. Try again.');
      }
    }
  }

  void _showOfflineDialog(String playerId, String playerName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server Unreachable'),
        content: const Text(
          'Cannot connect to game server.\n\n'
          'Make sure:\n'
          '  1. The server is running\n'
          '  2. Both devices are on the same network\n'
          '  3. The server IP is correct\n\n'
          'Try Local WiFi mode instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startRandomMatch();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  //  GAME START — ensures both players transition together
  // ──────────────────────────────────────────────────────────────

  void _startWsGame(String oppName) {
    WsGameService.startGame();
    _gotoGame('R', oppName, isWebSocket: true);
  }

  void _startFbGame(String oppName) {
    FbOnlineService.startGame();
    _gotoGame('R', oppName, isFbOnline: true);
  }

  void _gotoGame(String prefix, String oppName, {
    bool isLocal = false,
    bool isWebSocket = false,
    bool isFbOnline = false,
    String? roomCode,
  }) {
    final matchId = roomCode ?? '${prefix}_${DateTime.now().millisecondsSinceEpoch}';

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(
      matchId: matchId,
      opponentId: WsGameService.opponentId ?? 'opp',
      opponentName: oppName,
      isLocal: isLocal,
      isWebSocket: isWebSocket,
      isFbOnline: isFbOnline,
    ))).then((_) {
      WsGameService.dispose();
      FbOnlineService.dispose();
      LocalGameService.dispose();
      _loadStats();
    });
  }

  // ──────────────────────────────────────────────────────────────
  //  JOIN WITH CODE (RTDB)
  // ──────────────────────────────────────────────────────────────

  Future<void> _joinWithCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) { _snack('Enter room code'); return; }
    final id = AuthService.currentUserId ?? 'J${Random().nextInt(99999)}';
    final name = AuthService.displayName;
    final ok = await FbOnlineService.joinRoom(code: code, playerId: id, playerName: name);
    if (!mounted) return;
    if (ok) {
      _snack('Connected! Waiting for host...');
      FbOnlineService.messages.listen((msg) {
        if (!mounted) return;
        if (msg['type'] == 'event' && msg['event'] == 'started') {
          _gotoGame('J', 'Host', isFbOnline: true);
        }
      });
    } else {
      _snack('Room not found');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────
  //  UI
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);
    final name = AuthService.displayName;

    if (_opponentName != null && (_hosting || LocalGameService.isConnected)) {
      return _connectedScreen('WiFi', _opponentName!, _startLocalGame);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.lobby)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // ── Player card ──
          Card(child: Padding(
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
                    _searching ? 'Searching for opponent...' : _hosting ? 'Hosting...' : 'Ready',
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
          )),
          const SizedBox(height: 16),

          _bigBtn('PRACTICE MODE', Icons.play_circle_fill, const Color(0xFF00E676), _startPractice),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity, height: 36,
            child: OutlinedButton.icon(
              onPressed: _openTestSmile,
              icon: const Icon(Icons.science, size: 16),
              label: const Text('Test Smile Detection', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white38,
                side: const BorderSide(color: Colors.white12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Searching UI ──
          if (_searching) ...[
            Container(
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
                const Text('SEARCHING WORLDWIDE',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 8),
                const Text('Waiting for another player...',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 4),
                const Text('Will keep searching until found',
                    style: TextStyle(color: Colors.white30, fontSize: 11)),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () {
                    setState(() { _searching = false; _loading = false; });
                    WsGameService.leaveMatchmakingQueue();
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white38),
                  child: const Text('Cancel'),
                ),
              ]),
            ),
          ] else ...[
            _bigBtn('RANDOM MATCH', Icons.shuffle, const Color(0xFFFF6584), _startRandomMatch),
            const SizedBox(height: 16),
          ],

          _sectionHeader('LOCAL WIFI (Same Network)'),
          if (_hosting && _hostPort != null)
            Card(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  const Row(children: [
                    Icon(Icons.wifi, color: Color(0xFF6C63FF)),
                    SizedBox(width: 6),
                    Text('Hosting...', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  const Text('Other phone enter:', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text('$_localIp', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2)),
                ]),
              ),
            )
          else ...[
            SizedBox(
              width: double.infinity, height: 42,
              child: FilledButton.icon(
                onPressed: _hosting ? null : _hostLocal,
                icon: const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('Host Local Match', style: TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: TextField(
                controller: _ipCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Host IP',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  isDense: true,
                ),
              )),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: _connecting ? null : _joinLocal,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00D9FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                child: _connecting
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Join', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ]),
          ],

          const SizedBox(height: 14),
          _sectionHeader('JOIN WITH CODE'),
          Row(children: [
            Expanded(child: TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: InputDecoration(
                hintText: 'Room code',
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                isDense: true,
              ),
            )),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _joinWithCode,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              child: const Text('Join', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _connectedScreen(String mode, String opp, VoidCallback go) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connected!')),
      body: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              mode == 'WiFi' ? Icons.wifi : Icons.public,
              size: 64,
              color: mode == 'WiFi' ? const Color(0xFF6C63FF) : const Color(0xFFFF6584),
            ),
            const SizedBox(height: 16),
            const Text('PLAYER FOUND!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('vs $opp', style: const TextStyle(fontSize: 18, color: Color(0xFF6C63FF))),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity, height: 56,
              child: FilledButton.icon(
                onPressed: go,
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Text('START GAME', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      )),
    );
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
              style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 2)),
        ),
        const Expanded(child: Divider()),
      ]),
    );
  }
}
