import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/error_handler.dart';
import '../services/feed_service.dart';

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _picker = ImagePicker();
  String? _selectedImagePath;
  final _captionController = TextEditingController();
  String? _selectedCategory;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, maxWidth: 1920, maxHeight: 1920);
      if (picked != null && mounted) {
        setState(() => _selectedImagePath = picked.path);
      }
    } catch (e, stack) {
      ErrorHandler.logError('Image picker', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to pick image')),
        );
      }
    }
  }

  void _showPickerDialog() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _postContent() async {
    final caption = _captionController.text.trim();
    if (caption.isEmpty && _selectedImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a caption or image to post')),
      );
      return;
    }

    setState(() {});

    final ok = await FeedService.createPost(
      content: caption.isEmpty ? 'Check this out!' : caption,
      imagePath: _selectedImagePath,
      category: _selectedCategory,
    );

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post created!'), backgroundColor: Colors.green),
      );
      setState(() {
        _selectedImagePath = null;
        _captionController.clear();
        _selectedCategory = null;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to post. Check connection.'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create'),
        actions: [
          TextButton(
            onPressed: () => _postContent(),
            child: const Text('Post', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          GestureDetector(
            onTap: _showPickerDialog,
            child: Container(
              height: 280,
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2), width: 2),
                image: _selectedImagePath != null
                    ? DecorationImage(image: FileImage(File(_selectedImagePath!)), fit: BoxFit.cover)
                    : null,
              ),
              child: _selectedImagePath == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 56, color: Colors.white.withOpacity(0.4)),
                        const SizedBox(height: 12),
                        Text('Tap to add photo or video', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('Camera or Gallery', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13)),
                      ],
                    )
                  : Stack(children: [
                      Positioned(
                        top: 8, right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          style: IconButton.styleFrom(backgroundColor: Colors.black54),
                          onPressed: () => setState(() => _selectedImagePath = null),
                        ),
                      ),
                    ]),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _captionController,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Write a caption...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6C63FF))),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: ['Comedy', 'Memes', 'Reaction', 'Sketch', 'Prank', 'Art', 'Music'].map((cat) {
              final selected = _selectedCategory == cat;
              return FilterChip(
                label: Text(cat),
                selected: selected,
                onSelected: (v) => setState(() => _selectedCategory = v ? cat : null),
                backgroundColor: theme.colorScheme.surface,
                selectedColor: const Color(0xFF6C63FF).withOpacity(0.2),
                checkmarkColor: const Color(0xFF6C63FF),
                side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.2)),
              );
            }).toList(),
          ),
          const SizedBox(height: 100),
        ]),
      ),
    );
  }
}
