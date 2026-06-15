import 'package:flutter/material.dart';
import '../services/error_handler.dart';
import '../widgets/loading_widget.dart';
import '../models/content_item.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _simulateLoad();
    });
  }

  Future<void> _simulateLoad() async {
    try {
      await Future.delayed(const Duration(milliseconds: 600));
    } catch (e, stack) {
      ErrorHandler.logError('FeedScreen', e, stack);
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.white30),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 12),
          FilledButton(onPressed: () { setState(() { _loading = true; _error = null; }); _simulateLoad(); }, child: const Text('Retry')),
        ]),
      );
    }
    if (_loading) {
      return const LoadingWidget(message: 'Loading feed...');
    }
    return _buildFeed(theme);
  }

  Widget _buildFeed(ThemeData theme) {
    final items = [
      {
        'user': 'ComedyKing',
        'avatar': '\ud83d\udc51',
        'content': 'When the code finally compiles after 3 hours... \ud83d\ude05',
        'likes': '12.4K',
        'comments': '842',
        'time': '2h ago',
      },
      {
        'user': 'MemeQueen',
        'avatar': '\ud83d\udc78',
        'content': 'Me explaining my bug to the rubber duck \ud83e\udd86',
        'likes': '8.7K',
        'comments': '561',
        'time': '4h ago',
      },
      {
        'user': 'DadJokesInc',
        'avatar': '\ud83e\udd13',
        'content': 'Why don\'t scientists trust atoms? Because they make up everything! \ud83e\uddea',
        'likes': '15.1K',
        'comments': '1.2K',
        'time': '6h ago',
      },
      {
        'user': 'TechHumor',
        'avatar': '\ud83e\udd16',
        'content': 'IT Support: "Have you tried turning it off and on again?"\nEveryone: "..."',
        'likes': '22.3K',
        'comments': '3.4K',
        'time': '8h ago',
      },
    ];

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _loading = true);
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) setState(() => _loading = false);
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                        child: Text(item['avatar']!, style: const TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['user']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(item['time']!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.more_horiz, color: Colors.white54, size: 20),
                        onPressed: () {},
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(item['content']!, style: const TextStyle(fontSize: 15, height: 1.4)),
                  const SizedBox(height: 16),
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [theme.colorScheme.primary.withOpacity(0.08), theme.colorScheme.secondary.withOpacity(0.04)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_outlined, size: 48, color: Colors.white.withOpacity(0.2)),
                          const SizedBox(height: 8),
                          Text('Content Image', style: TextStyle(color: Colors.white.withOpacity(0.3))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    _actionChip(Icons.favorite_border, item['likes']!),
                    const SizedBox(width: 16),
                    _actionChip(Icons.chat_bubble_outline, item['comments']!),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.bookmark_border, color: Colors.white54, size: 20),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.white54, size: 20),
                      onPressed: () {},
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _actionChip(IconData icon, String label) {
    return GestureDetector(
      onTap: () {},
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white54),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }
}
