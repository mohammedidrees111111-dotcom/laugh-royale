import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/auth_service.dart';
import '../../services/matchmaking_service.dart';
import '../../services/firebase_service.dart';
import '../game/game_screen.dart';

class WaitingRoomScreen extends StatefulWidget {
  final String mode;
  final String? roomCode;

  const WaitingRoomScreen({super.key, required this.mode, this.roomCode});

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  String? _opponentId;
  String? _opponentName;
  String? _roomId;
  bool _found = false;
  int _countdown = 3;
  Timer? _countdownTimer;
  StreamSubscription? _roomSub;

  @override
  void initState() {
    super.initState();
    _listenToRoomDoc();
  }

  void _listenToRoomDoc() {
    final myId = AuthService.currentUserId;
    if (myId == null) return;

    final rId = widget.roomCode ?? MatchmakingService.currentRoomId;
    if (rId == null) return;
    _roomId = rId;

    final db = FirebaseService.firestore;
    if (db == null) return;

    final docRef = db.collection('match_rooms').doc(_roomId);

    _roomSub = docRef.snapshots().listen((doc) {
      if (!mounted || _found) return;
      final data = doc.data();
      if (data == null) return;

      final p1Id = data['player1Id'] as String?;
      final p2Id = data['player2Id'] as String?;
      final p1Name = data['player1Name'] as String?;
      final p2Name = data['player2Name'] as String?;
      final status = data['status'] as String?;

      if (status != 'playing') return;
      if (p1Id == null || p2Id == null) return;

      final isPlayer1 = p1Id == myId;
      final oppId = isPlayer1 ? p2Id : p1Id;
      final oppName = (isPlayer1 ? p2Name : p1Name) ?? 'Player';

      if (oppId.isEmpty || oppId == myId) return;

      _roomSub?.cancel();
      setState(() {
        _opponentId = oppId;
        _opponentName = oppName;
        _found = true;
      });
      _startCountdown(_roomId ?? widget.roomCode ?? 'unknown');
    });
  }

  void _startCountdown(String roomId) {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GameScreen(
              matchId: roomId,
              opponentId: _opponentId ?? 'unknown',
              opponentName: _opponentName ?? 'Player',
              isHost: widget.mode != 'join',
            ),
          ),
        );
      } else {
        setState(() => _countdown--);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _roomSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_found) ...[
                  const SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: Color(0xFFFF6584),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(l.searching,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Looking for a REAL player...',
                      style: TextStyle(fontSize: 14, color: Colors.white54)),
                  const SizedBox(height: 4),
                  const Text('NO BOTS - Real humans only',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (widget.roomCode != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                const Color(0xFF6C63FF).withOpacity(0.3)),
                      ),
                      child: Column(children: [
                        const Text('Share this code with a friend:',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(widget.roomCode!,
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 6,
                                color: const Color(0xFF6C63FF))),
                      ]),
                    ),
                  const SizedBox(height: 32),
                  OutlinedButton(
                    onPressed: () {
                      MatchmakingService.cancelSearch();
                      Navigator.of(context).pop();
                    },
                    child: Text(l.cancel),
                  ),
                ] else ...[
                  const Icon(Icons.people, size: 64, color: Colors.greenAccent),
                  const SizedBox(height: 16),
                  Text(l.opponentFound,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('REAL PLAYER FOUND',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_opponentName ?? '',
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6C63FF))),
                  ),
                  const SizedBox(height: 32),
                  Text('$_countdown',
                      style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(l.ready,
                      style: const TextStyle(
                          fontSize: 16, color: Colors.white54)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
