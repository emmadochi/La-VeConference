import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/media_storage_service.dart';

/// A collage bubble that displays multiple images in a beautiful grid.
/// Tapping any image opens a full-screen swipeable gallery viewer.
class MediaGalleryBubble extends StatelessWidget {
  final List<Map<String, dynamic>> images;
  final bool isMe;
  final String senderName;
  final String? caption;

  const MediaGalleryBubble({
    super.key,
    required this.images,
    required this.isMe,
    required this.senderName,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildGrid(context),
        if (caption != null && caption!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(caption!, style: TextStyle(color: isMe ? Colors.white : AppTheme.textPrimary, fontSize: 14)),
        ],
      ],
    );
  }

  Widget _buildGrid(BuildContext context) {
    final count = images.length;
    if (count == 1) {
      return _galleryTile(context, 0, borderRadius: BorderRadius.circular(12));
    }
    if (count == 2) {
      return Row(children: [
        Expanded(child: _galleryTile(context, 0, borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)))),
        const SizedBox(width: 2),
        Expanded(child: _galleryTile(context, 1, borderRadius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)))),
      ]);
    }
    if (count == 3) {
      return Row(children: [
        Expanded(flex: 2, child: _galleryTile(context, 0, height: 180, borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)))),
        const SizedBox(width: 2),
        Expanded(child: Column(children: [
          _galleryTile(context, 1, height: 89, borderRadius: const BorderRadius.only(topRight: Radius.circular(12))),
          const SizedBox(height: 2),
          _galleryTile(context, 2, height: 89, borderRadius: const BorderRadius.only(bottomRight: Radius.circular(12))),
        ])),
      ]);
    }
    final displayCount = count > 4 ? 4 : count;
    final extra = count > 4 ? count - 4 : 0;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: 1.0),
      itemCount: displayCount,
      itemBuilder: (context, i) {
        final isLast = i == displayCount - 1 && extra > 0;
        BorderRadius radius = BorderRadius.zero;
        if (i == 0) radius = const BorderRadius.only(topLeft: Radius.circular(12));
        if (i == 1) radius = const BorderRadius.only(topRight: Radius.circular(12));
        if (i == 2) radius = const BorderRadius.only(bottomLeft: Radius.circular(12));
        if (i == 3) radius = const BorderRadius.only(bottomRight: Radius.circular(12));
        if (isLast) {
          return Stack(fit: StackFit.expand, children: [
            _galleryTile(context, i, borderRadius: radius),
            ClipRRect(borderRadius: radius, child: Container(color: Colors.black54, alignment: Alignment.center, child: Text('+$extra', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)))),
          ]);
        }
        return _galleryTile(context, i, borderRadius: radius);
      },
    );
  }

  Widget _galleryTile(BuildContext context, int index, {BorderRadius borderRadius = BorderRadius.zero, double? height}) {
    final img = images[index];
    final url = img['url'] as String?;
    final localPath = img['localPath'] as String?;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          pageBuilder: (ctx, _, __) => _GalleryViewer(images: images, initialIndex: index),
        ));
      },
      child: ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox(height: height, child: _buildImageWidget(url, localPath)),
      ),
    );
  }

  Widget _buildImageWidget(String? url, String? localPath) {
    if (localPath != null && File(localPath).existsSync()) {
      return Image.file(File(localPath), fit: BoxFit.cover);
    }
    if (url != null && url.startsWith('data:')) {
      try {
        final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
        return Image.memory(bytes, fit: BoxFit.cover);
      } catch (_) {}
    }
    if (url != null && url.isNotEmpty) {
      return Image.network(url, fit: BoxFit.cover,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return Container(color: Colors.black26, child: Center(child: CircularProgressIndicator(value: progress.expectedTotalBytes != null ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes! : null, color: AppTheme.mint, strokeWidth: 2)));
        },
        errorBuilder: (ctx, _, __) => Container(color: Colors.black26, child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 28))),
      );
    }
    return Container(color: Colors.black26, child: const Center(child: Icon(Icons.image_not_supported_rounded, color: Colors.white24)));
  }
}

class _GalleryViewer extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final int initialIndex;
  const _GalleryViewer({required this.images, required this.initialIndex});
  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.images.length}', style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white),
            onPressed: () async {
              final img = widget.images[_currentIndex];
              final localPath = img['localPath'] as String?;
              final url = img['url'] as String?;
              if (localPath != null && File(localPath).existsSync()) {
                await MediaStorageService.openOrShareFile(localPath, 'image.jpg');
              } else if (url != null) {
                final downloaded = await MediaStorageService.downloadMediaToLocal(remoteUrl: url, category: 'Images', targetFileName: 'shared_$_currentIndex.jpg');
                if (downloaded != null) await MediaStorageService.openOrShareFile(downloaded.path, 'image.jpg');
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (ctx, i) {
                final img = widget.images[i];
                final url = img['url'] as String?;
                final localPath = img['localPath'] as String?;
                Widget imageWidget;
                if (localPath != null && File(localPath).existsSync()) {
                  imageWidget = Image.file(File(localPath), fit: BoxFit.contain);
                } else if (url != null && url.startsWith('data:')) {
                  try {
                    final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
                    imageWidget = Image.memory(bytes, fit: BoxFit.contain);
                  } catch (_) {
                    imageWidget = const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48));
                  }
                } else if (url != null && url.isNotEmpty) {
                  imageWidget = Image.network(url, fit: BoxFit.contain);
                } else {
                  imageWidget = const Center(child: Icon(Icons.image_not_supported_rounded, color: Colors.white24, size: 48));
                }
                return InteractiveViewer(minScale: 0.8, maxScale: 4.0, child: Center(child: imageWidget));
              },
            ),
          ),
          if (widget.images.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.images.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentIndex == i ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(color: _currentIndex == i ? AppTheme.mint : Colors.white38, borderRadius: BorderRadius.circular(4)),
                )),
              ),
            ),
        ],
      ),
    );
  }
}
