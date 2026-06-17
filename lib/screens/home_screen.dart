import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../l10n/localization.dart';
import '../services/auth_service.dart';
import '../services/error_handler.dart';
import '../services/firebase_service.dart';
import '../widgets/error_fallback.dart';
import 'lobby/lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = false;
  String? _error;
  Map<String, int> _stats = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      _stats = {
        'wins': prefs.getInt('wins') ?? 0,
        'losses': prefs.getInt('losses') ?? 0,
        'total': prefs.getInt('totalGames') ?? 0,
      };
    } catch (e, stack) {
      ErrorHandler.logError('HomeScreen', e, stack);
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => _showSnack('No notifications yet'),
          ),
        ],
      ),
      body: _buildBody(l, theme),
    );
  }

  Widget _buildBody(L l, ThemeData theme) {
    if (_error != null) {
      return ErrorFallbackWidget(message: _error!, onRetry: _loadData);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildWelcomeCard(l, theme),
          const SizedBox(height: 20),
          _sectionHeader('Quick Play'),
          const SizedBox(height: 12),
          _buildQuickActions(l, theme),
          const SizedBox(height: 24),
          _sectionHeader('Your Stats'),
          const SizedBox(height: 12),
          _buildStatsGrid(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard(L l, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l.welcome} ${AuthService.displayName}',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              _statChip('\ud83c\udfc6', '${_stats['wins'] ?? 0} Wins', Colors.amber),
              const SizedBox(width: 12),
              _statChip('\ud83d\ude22', '${_stats['losses'] ?? 0} Losses', Colors.redAccent),
              const SizedBox(width: 12),
              _statChip('\ud83c\udfae', '${_stats['total'] ?? 0} Games', const Color(0xFF6C63FF)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final winRate = _stats['total'] != null && _stats['total']! > 0
        ? (_stats['wins']! / _stats['total']! * 100).toStringAsFixed(0)
        : '0';
    return Row(children: [
      Expanded(child: _statCard('\ud83c\udfaf', '$winRate%', 'Win Rate', const Color(0xFF00E676))),
      const SizedBox(width: 10),
      Expanded(child: _statCard('\ud83d\udd25', '${_stats['wins'] ?? 0}', 'Total Wins', Colors.amber)),
      const SizedBox(width: 10),
      Expanded(child: _statCard('\ud83c\udfae', '${_stats['total'] ?? 0}', 'Games', const Color(0xFF6C63FF))),
    ]);
  }

  Widget _statCard(String emoji, String value, String label, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ]),
      ),
    );
  }

  Widget _statChip(String emoji, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text('$emoji $text', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold));
  }

  Widget _buildQuickActions(L l, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _actionButton(Icons.shuffle, l.playRandom, const Color(0xFFFF6584), () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LobbyScreen()));
        }),
        _actionButton(Icons.vpn_lock, l.privateRoom, const Color(0xFF6C63FF), () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LobbyScreen()));
        }),
        _actionButton(Icons.leaderboard, 'Leaderboard', const Color(0xFF00D9FF), () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
        }),
        _actionButton(Icons.card_giftcard, 'Rewards', const Color(0xFF00E676), () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RewardsScreen()));
        }),
      ],
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        CircleAvatar(radius: 28, backgroundColor: color.withOpacity(0.15), child: Icon(icon, color: color)),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ]),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<Map<String, dynamic>> _players = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    final currentId = AuthService.currentUserId;
    final prefs = await SharedPreferences.getInstance();
    final myWins = prefs.getInt('wins') ?? 0;

    final db = FirebaseService.firestore;
    if (db != null) {
      try {
        final snapshot = await db.collection('leaderboard')
            .orderBy('wins', descending: true)
            .limit(50)
            .get();
        final list = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'name': data['name'] ?? 'Player',
            'wins': data['wins'] ?? 0,
            'isYou': doc.id == currentId,
          };
        }).toList();

        if (mounted) setState(() { _players = list; _loading = false; });
        return;
      } catch (_) {}
    }

    _players = [
      {'name': AuthService.displayName, 'wins': myWins, 'isYou': true},
    ];
    _players.sort((a, b) => (b['wins'] as int).compareTo(a['wins'] as int));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _players.isEmpty
              ? const Center(child: Text('No players yet. Play games to rank!', style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _players.length,
                  itemBuilder: (ctx, i) {
                    final p = _players[i];
                    final isYou = p['isYou'] == true;
                    final rankColor = i == 0
                        ? const Color(0xFFFFD700)
                        : i == 1
                            ? const Color(0xFFC0C0C0)
                            : i == 2
                                ? const Color(0xFFCD7F32)
                                : Colors.white;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isYou ? const Color(0xFF6C63FF).withOpacity(0.15) : null,
                      child: ListTile(
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: isYou ? const Color(0xFF6C63FF).withOpacity(0.2) : Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: rankColor))),
                        ),
                        title: Text(p['name'] as String, style: TextStyle(fontWeight: FontWeight.w600, color: isYou ? const Color(0xFF6C63FF) : Colors.white)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.emoji_events, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text('${p['wins']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});
  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  Map<String, int> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    _stats = {
      'wins': prefs.getInt('wins') ?? 0,
      'losses': prefs.getInt('losses') ?? 0,
      'total': prefs.getInt('totalGames') ?? 0,
      'gems': prefs.getInt('gems') ?? 0,
    };
    if (mounted) setState(() => _loading = false);
  }

  int _calcGems() {
    return (_stats['wins'] ?? 0) * 10 + (_stats['total'] ?? 0) * 2;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('Rewards')), body: const Center(child: CircularProgressIndicator()));
    }

    final gems = _stats['gems']! > 0 ? _stats['gems']! : _calcGems();
    final totalGames = _stats['total'] ?? 0;
    final wins = _stats['wins'] ?? 0;

    final rewards = [
      {'title': 'Win 5 Matches', 'desc': 'Win 5 multiplayer games', 'reward': '250 Gems', 'icon': '\ud83c\udfc6', 'progress': (wins / 5).clamp(0.0, 1.0)},
      {'title': 'Play 20 Games', 'desc': 'Complete 20 total games', 'reward': '500 Gems', 'icon': '\ud83c\udfae', 'progress': (totalGames / 20).clamp(0.0, 1.0)},
      {'title': 'Win Streak', 'desc': 'Win 3 games in a row', 'reward': '150 Gems', 'icon': '\ud83d\udd25', 'progress': (wins >= 3 ? 1.0 : wins / 3)},
      {'title': 'Play Daily', 'desc': 'Play at least 1 game today', 'reward': '50 Gems', 'icon': '\ud83c\udf1f', 'progress': totalGames > 0 ? 1.0 : 0.0},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Rewards')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(colors: [Color(0xFFFF6584), Color(0xFF6C63FF)]),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Text('\ud83c\udf81', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                const Text('Your Rewards', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Complete challenges to earn gems', style: TextStyle(fontSize: 13, color: Colors.white70)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.diamond, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text('$gems Gems', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ]),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          ...rewards.map((r) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(r['icon'] as String, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(r['desc'] as String, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6584).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(r['reward'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFFFF6584), fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: (r['progress'] as double?) ?? 0,
                  backgroundColor: Colors.white10,
                  color: const Color(0xFF6C63FF),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
              ]),
            ),
          )),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
