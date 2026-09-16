import 'package:flutter/material.dart';

/// 相册 Tab（阶段 0 空壳）：月分组网格在 W6 相册阶段实现
/// 空态按走查三要素先行就位。
class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('相册')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary.withAlpha(120)),
            const SizedBox(height: 12),
            Text('相册将在 W6 上线', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '图片会按月分组展示在这里',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }
}