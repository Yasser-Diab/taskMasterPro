import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    required this.name,
    required this.imagePath,
    required this.radius,
    super.key,
  });

  final String name;
  final String? imagePath;
  final double radius;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Future<String?>? _resolved;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) _resolve();
  }

  void _resolve() {
    final value = widget.imagePath;
    if (value == null ||
        value.isEmpty ||
        value.startsWith('http://') ||
        value.startsWith('https://') ||
        File(value).existsSync()) {
      _resolved = Future.value(value);
      return;
    }
    _resolved = Supabase.instance.client.storage
        .from('avatars')
        .createSignedUrl(value, 60 * 60)
        .then<String?>((url) => url)
        .catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _resolved,
      builder: (context, snapshot) {
        final path = snapshot.data;
        ImageProvider<Object>? provider;
        if (path != null && path.isNotEmpty) {
          if (path.startsWith('http://') || path.startsWith('https://')) {
            provider = NetworkImage(path);
          } else if (File(path).existsSync()) {
            provider = FileImage(File(path));
          }
        }
        return CircleAvatar(
          radius: widget.radius,
          foregroundImage: provider,
          onForegroundImageError: provider == null ? null : (_, _) {},
          child: provider == null
              ? Text(
                  widget.name.isEmpty
                      ? '?'
                      : widget.name.characters.first.toUpperCase(),
                  style: Theme.of(context).textTheme.titleLarge,
                )
              : null,
        );
      },
    );
  }
}
