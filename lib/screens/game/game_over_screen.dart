import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/ws_game_service.dart';
import '../../services/fb_online_service.dart';
import 'game_screen.dart';

class GameOverScreen extends StatefulWidget {
  final bool won;
  final String opponent;
  final String reason;
  final bool isFbOnline;
  final bool isLocal;
  final bool isWebSocket;

  const GameOverScreen({
    super.key,
    required this.won,
    required this.opponent,
    required this.reason,
    this.isFbOnline = false,
    this.isLocal = false,
    this.isWebSocket = false,
  });

  @override
  State<GameOverScreen> createState() => _GameOverScreenState();
}

class _GameOverScreenState extends State<GameOverScreen> {
  bool _searching = false;
  final int _gemsEarned = Random().nextInt(50) + 30;

  void _playAgain() {
    if (widget.isFbOnline || widget.isWebSocket) {
      _searchAgain();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _searchAgain() async {
    setState(() => _searching = true);

    if (widget.isWebSocket) {
      final id = 'R${DateTime.now().millisecondsSinceEpoch}';
      final name = 'Player';

      WsGameService.messages.listen((msg) {
        if (!mounted) return;
        if (msg['type'] == 'event' && msg['event'] == 'started') {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => GameScreen(
              matchId: WsGameService.roomCode ?? 'R_${DateTime.now().millisecondsSinceEpoch}',
              opponentId: WsGameService.opponentId ?? 'opp',
              opponentName: WsGameService.opponentName ?? 'Player',
              isWebSocket: true,
            )),
            (route) => route.isFirst,
          );
        }
      });

      final result = await WsGameService.joinMatchmakingQueue(
        playerId: id,
        playerName: name,
      );

      if (!mounted) return;

      if (result != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => GameScreen(
            matchId: result['roomId'] as String? ?? 'R_${DateTime.now().millisecondsSinceEpoch}',
            opponentId: result['opponentId'] as String? ?? 'opp',
            opponentName: result['opponentName'] as String? ?? 'Player',
            isWebSocket: true,
          )),
          (route) => route.isFirst,
        );
      } else {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No players found')),
        );
      }
    } else {
      final id = 'R${DateTime.now().millisecondsSinceEpoch}';
      final status = await FbOnlineService.joinQueue(
        playerId: id,
        playerName: 'Player',
      );
      if (!mounted) return;
      if (status == MatchStatus.matched) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => GameScreen(
            matchId: 'R_${DateTime.now().millisecondsSinceEpoch}',
            opponentId: 'opp',
            opponentName: FbOnlineService.opponentName ?? 'Player',
            isFbOnline: true,
          )),
          (route) => route.isFirst,
        );
      } else {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No players found')),
        );
      }
    }
  }

  void _goHome() {
    FbOnlineService.dispose();
    WsGameService.dispose();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    if (_searching) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F1A),
        body: SafeArea(child: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(
              width: 56, height: 56,
              child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFFFF6584)),
            ),
            const SizedBox(height: 24),
            const Text('SEARCHING FOR NEXT GAME',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 8),
            const Text('Finding another player...',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                setState(() => _searching = false);
                WsGameService.dispose();
                FbOnlineService.dispose();
              },
              child: const Text('Cancel'),
            ),
          ]),
        ))),
      );
    }

    final won = widget.won;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: won
                        ? [Colors.amber.shade300, Colors.amber.shade800]
                        : [Colors.redAccent.shade100, Colors.redAccent.shade700],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (won ? Colors.amber : Colors.redAccent).withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  won ? Icons.emoji_events : Icons.sentiment_very_dissatisfied,
                  size: 60,
                  color: won ? Colors.white : Colors.white70,
                ),
              ),
              const SizedBox(height: 20),

              Text(
                won ? 'YOU WIN!' : 'YOU LOST!',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  color: won ? Colors.amber : Colors.redAccent,
                  letterSpacing: 2,
                ),
              ),

              if (won) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withOpacity(0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.diamond, color: Colors.amber, size: 18),
                    const SizedBox(width: 6),
                    Text('+$_gemsEarned Gems',
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                ),
              ],

              const SizedBox(height: 20),

              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: won ? Colors.greenAccent.withOpacity(0.1) : Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: won ? Colors.greenAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person, size: 16, color: won ? Colors.greenAccent : Colors.redAccent),
                    const SizedBox(width: 6),
                    Text(
                      won ? 'Winner: You' : 'Loser: You',
                      style: TextStyle(
                        color: won ? Colors.greenAccent : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.person_outline, size: 16, color: Color(0xFF6C63FF)),
                    const SizedBox(width: 6),
                    Text(
                      won ? 'Loser: ${widget.opponent}' : 'Winner: ${widget.opponent}',
                      style: const TextStyle(
                        color: Color(0xFF6C63FF),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ]),
                ),
              ]),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity, height: 56,
                child: FilledButton.icon(
                  onPressed: _playAgain,
                  icon: const Icon(Icons.replay),
                  label: Text(
                    (widget.isFbOnline || widget.isWebSocket) ? 'PLAY AGAIN' : 'Play Again',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6584),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity, height: 56,
                child: OutlinedButton.icon(
                  onPressed: _goHome,
                  icon: const Icon(Icons.home),
                  label: const Text('Back to Lobby', style: TextStyle(fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
