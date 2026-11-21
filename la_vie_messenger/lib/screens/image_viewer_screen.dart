import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/media_storage_service.dart';

class ImageViewerScreen extends StatefulWidget {
  final String? imageUrl;
  final String? localPath;
  final String? title;
  final String? subtitle;

  const ImageViewerScreen({
    super.key,
    this.imageUrl,
    this.localPath,
    this.title,
    this.subtitle,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  final TransformationController _transformController = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _isSaving = false;
  bool _isSharing = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      _transformController.value = Matrix4.identity()
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
    }
  }

  Future<File?> _resolveLocalFile() async {
    // 1. Check localPath if valid
    if (widget.localPath != null && widget.localPath!.isNotEmpty) {
      final f = File(widget.localPath!);
      if (await f.exists()) return f;
    }

    final url = widget.imageUrl;
    if (url == null || url.isEmpty) return null;

    // 2. If data URI, decode to temp file
    if (url.startsWith('data:')) {
      final commaIndex = url.indexOf(',');
      if (commaIndex != -1) {
        final bytes = base64Decode(url.substring(commaIndex + 1));
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/view_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await file.writeAsBytes(bytes);
        return file;
      }
    }

    // 3. If remote URL, check if already in LiChat local media
    final fileName = url.split('/').last.split('?').first;
    final cleanName = fileName.isEmpty ? 'image_${DateTime.now().millisecondsSinceEpoch}.jpg' : fileName;
    final cached = await MediaStorageService.findLocalFile(category: 'Images', fileName: cleanName);
    if (cached != null) return cached;

    // 4. Download temporarily
    try {
      final downloaded = await MediaStorageService.downloadMediaToLocal(
        remoteUrl: url,
        category: 'Images',
        targetFileName: cleanName,
      );
      return downloaded;
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareImage() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    HapticFeedback.lightImpact();

    try {
      final file = await _resolveLocalFile();
      if (file != null && await file.exists()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: widget.title != null ? '${widget.title} - via LiChat' : 'Shared via LiChat',
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not prepare image for sharing')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _downloadImage() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final file = await _resolveLocalFile();
      if (file != null && await file.exists()) {
        // Save to public Downloads directory on Android / Documents
        Directory? targetDir;
        if (Platform.isAndroid) {
          final extDir = Directory('/storage/emulated/0/Download');
          if (await extDir.exists()) {
            targetDir = extDir;
          }
        }
        targetDir ??= await getApplicationDocumentsDirectory();

        final fileName = 'LiChat_IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await file.copy('${targetDir.path}/$fileName');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.surfaceElevated,
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppTheme.mint, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Saved to ${Platform.isAndroid ? 'Downloads' : 'Documents'}/$fileName',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save image')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildImageWidget() {
    // 1. Local file
    if (widget.localPath != null && widget.localPath!.isNotEmpty) {
      final f = File(widget.localPath!);
      if (f.existsSync()) {
        return Image.file(
          f,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildErrorWidget(),
        );
      }
    }

    final url = widget.imageUrl;
    if (url == null || url.isEmpty) return _buildErrorWidget();

    // 2. Base64 Data URI
    if (url.startsWith('data:')) {
      final commaIndex = url.indexOf(',');
      if (commaIndex != -1) {
        try {
          final bytes = base64Decode(url.substring(commaIndex + 1));
          return Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _buildErrorWidget(),
          );
        } catch (_) {
          return _buildErrorWidget();
        }
      }
    }

    // 3. Network URL
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            color: AppTheme.mint,
            value: progress.expectedTotalBytes != null
                ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                : null,
          ),
        );
      },
      errorBuilder: (_, __, ___) => _buildErrorWidget(),
    );
  }

  Widget _buildErrorWidget() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, color: Colors.white38, size: 64),
          SizedBox(height: 12),
          Text('Unable to load image', style: TextStyle(color: Colors.white54, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.65),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: (widget.title != null || widget.subtitle != null)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.title != null)
                    Text(
                      widget.title!,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                ],
              )
            : null,
        actions: [
          IconButton(
            icon: _isSharing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.share_rounded, color: Colors.white),
            tooltip: 'Share to Other Apps',
            onPressed: _shareImage,
          ),
          IconButton(
            icon: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.download_rounded, color: Colors.white),
            tooltip: 'Save to Device',
            onPressed: _downloadImage,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapDetails = details,
        onDoubleTap: _handleDoubleTap,
        child: Center(
          child: InteractiveViewer(
            transformationController: _transformController,
            minScale: 0.8,
            maxScale: 4.0,
            child: _buildImageWidget(),
          ),
        ),
      ),
    );
  }
}
