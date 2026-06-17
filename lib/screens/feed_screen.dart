import 'package:flutter/material.dart';
import '../services/feed_service.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() { _loading = true; _error = null; });
    try {
      FeedService.getPosts().listen((posts) {
        if (mounted) setState(() { _posts = posts; _loading = false; });
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = (timestamp as dynamic).toDate();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
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
          FilledButton(onPressed: _loadPosts, child: const Text('Retry')),
        ]),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPosts,
        child: ListView(children: const [
          SizedBox(height: 120),
          Center(child: Text('No posts yet. Be the first!', style: TextStyle(color: Colors.white54, fontSize: 16))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        _loadPosts();
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        itemCount: _posts.length,
        itemBuilder: (ctx, i) {
          final item = _posts[i];
          final hasImage = item['imageUrl'] != null && (item['imageUrl'] as String).isNotEmpty;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                      child: Text((item['authorName'] as String? ?? 'P')[0].toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item['authorName'] ?? 'Player', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(_formatTime(item['createdAt']), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ]),
                    ),
                    if (item['category'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF6C63FF).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                        child: Text(item['category'] as String, style: const TextStyle(fontSize: 10, color: Color(0xFF6C63FF))),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Text(item['content'] ?? '', style: const TextStyle(fontSize: 15, height: 1.4)),
                  if (hasImage) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [theme.colorScheme.primary.withOpacity(0.08), theme.colorScheme.secondary.withOpacity(0.04)],
                          ),
                        ),
                        child: Center(
                          child: Icon(Icons.image, size: 48, color: Colors.white.withOpacity(0.2)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    _actionChip(Icons.favorite_border, '${item['likes'] ?? 0}'),
                    const SizedBox(width: 16),
                    _actionChip(Icons.chat_bubble_outline, '${item['comments'] ?? 0}'),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.bookmark_border, color: Colors.white54, size: 20), onPressed: () {}),
                    IconButton(icon: const Icon(Icons.share, color: Colors.white54, size: 20), onPressed: () {}),
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
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18, color: Colors.white54),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
    ]);
  }
}
