/// Data model for feed content items.
class ContentItem {
  final String id;
  final String authorName;
  final String authorAvatar;
  final String content;
  final String? imageUrl;
  final int likes;
  final int comments;
  final DateTime createdAt;

  const ContentItem({
    required this.id,
    required this.authorName,
    required this.authorAvatar,
    required this.content,
    this.imageUrl,
    this.likes = 0,
    this.comments = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorName': authorName,
        'authorAvatar': authorAvatar,
        'content': content,
        'imageUrl': imageUrl,
        'likes': likes,
        'comments': comments,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ContentItem.fromJson(Map<String, dynamic> json) {
    return ContentItem(
      id: json['id'] ?? '',
      authorName: json['authorName'] ?? '',
      authorAvatar: json['authorAvatar'] ?? '',
      content: json['content'] ?? '',
      imageUrl: json['imageUrl'],
      likes: json['likes'] ?? 0,
      comments: json['comments'] ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}
