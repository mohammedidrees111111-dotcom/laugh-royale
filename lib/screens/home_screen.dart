import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/localization.dart';
import '../services/auth_service.dart';
import '../services/error_handler.dart';
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
          _sectionHeader('Trending'),
          const SizedBox(height: 12),
          _buildTrendingList(l),
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

  Widget _buildTrendingList(L l) {
    final items = [
      {'title': 'Top Players Today', 'subtitle': 'See who\'s dominating the leaderboard', 'icon': '\ud83d\udd25'},
      {'title': 'Funniest Moments', 'subtitle': 'Best laugh fails of the week', 'icon': '\ud83d\ude02'},
      {'title': 'Challenge of the Day', 'subtitle': 'Special daily challenge - win gems', 'icon': '\ud83d\udc9b'},
      {'title': 'New Emotes', 'subtitle': 'Check out the latest reactions', 'icon': '\ud83c\udfad'},
    ];

    return Column(
      children: items.asMap().entries.map((entry) {
        final item = entry.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
              child: Text(item['icon']!, style: const TextStyle(fontSize: 20)),
            ),
            title: Text(item['title']!, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(item['subtitle']!),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSnack('${item['title']} coming soon!'),
          ),
        );
      }).toList(),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final players = [
      {'name': 'LaughKing', 'wins': 342, 'flag': '\ud83c\uddf8\ud83c\udde6'},
      {'name': 'SmileQueen', 'wins': 298, 'flag': '\ud83c\uddfa\ud83c\uddf8'},
      {'name': 'JokeMaster', 'wins': 256, 'flag': '\ud83c\uddec\ud83c\udde7'},
      {'name': 'ChucklePro', 'wins': 221, 'flag': '\ud83c\uddee\ud83c\uddf3'},
      {'name': 'FunnyGuy', 'wins': 198, 'flag': '\ud83c\uddf2\ud83c\udde6'},
      {'name': 'HaHaHero', 'wins': 175, 'flag': '\ud83c\udde6\ud83c\uddea'},
      {'name': 'GiggleStar', 'wins': 152, 'flag': '\ud83c\uddf5\ud83c\uddf8'},
      {'name': 'WitWizard', 'wins': 134, 'flag': '\ud83c\udde9\ud83c\uddea'},
      {'name': 'PrankLord', 'wins': 118, 'flag': '\ud83c\uddf3\ud83c\uddec'},
      {'name': 'MemeKing', 'wins': 99, 'flag': '\ud83c\uddf9\ud83c\uddf7'},
      {'name': 'You', 'wins': 42, 'flag': '\ud83c\uddf5\ud83c\uddf8', 'isYou': true},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: players.length,
        itemBuilder: (ctx, i) {
          final p = players[i];
          final isYou = p['isYou'] == true;
          final rankColor = i == 0 ? const Color(0xFFFFD700) : i == 1 ? const Color(0xFFC0C0C0) : i == 2 ? const Color(0xFFCD7F32) : Colors.white;
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
              title: Row(children: [
                Text(p['flag'] as String, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(p['name'] as String, style: TextStyle(fontWeight: FontWeight.w600, color: isYou ? const Color(0xFF6C63FF) : Colors.white)),
                if (isYou) const Text(' (You)', style: TextStyle(fontSize: 12, color: Color(0xFF6C63FF))),
              ]),
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

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rewards = [
      {'title': 'Daily Login', 'desc': 'Log in every day for 7 days', 'reward': '100 Gems', 'icon': '\ud83c\udf1f', 'progress': 0.7},
      {'title': 'Win 5 Matches', 'desc': 'Win 5 multiplayer games', 'reward': '250 Gems', 'icon': '\ud83c\udfc6', 'progress': 0.4},
      {'title': 'Make 3 Players Laugh', 'desc': 'Use actions to make opponents laugh', 'reward': '150 Gems', 'icon': '\ud83d\ude02', 'progress': 0.9},
      {'title': 'Play 20 Games', 'desc': 'Complete 20 total games', 'reward': '500 Gems', 'icon': '\ud83c\udfae', 'progress': 0.25},
      {'title': 'Share the App', 'desc': 'Invite 3 friends to play', 'reward': '300 Gems', 'icon': '\ud83d\udc8c', 'progress': 0.0},
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
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.diamond, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text('1,250 Gems', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
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
