import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/media_storage_service.dart';

class VideoViewerScreen extends StatefulWidget {
  final String? videoUrl;
  final String? localPath;
  final String? title;
  final String? subtitle;
  final String? fileName;

  const VideoViewerScreen({
    super.key,
    this.videoUrl,
    this.localPath,
    this.title,
    this.subtitle,
    this.fileName,
  });

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  bool _isSaving = false;
  bool _isSharing = false;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      VideoPlayerController controller;

      // 1. Priority: Local file if exists
      if (widget.localPath != null && widget.localPath!.isNotEmpty) {
        final f = File(widget.localPath!);
        if (await f.exists()) {
          controller = VideoPlayerController.file(f);
          await _setupController(controller);
          return;
        }
      }

      final url = widget.videoUrl;
      if (url == null || url.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Video source not available';
        });
        return;
      }

      // 2. Data URI
      if (url.startsWith('data:')) {
        final comma = url.indexOf(',');
        if (comma == -1) throw Exception('Invalid video data URI');
        final bytes = base64Decode(url.substring(comma + 1));
        final dir = await getTemporaryDirectory();
        final tmpFile = File('${dir.path}/vid_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await tmpFile.writeAsBytes(bytes);
        controller = VideoPlayerController.file(tmpFile);
        await _setupController(controller);
        return;
      }

      // 3. Cached local file
      final cleanName = widget.fileName ?? url.split('/').last.split('?').first;
      final cached = await MediaStorageService.findLocalFile(category: 'Videos', fileName: cleanName);
      if (cached != null && await cached.exists()) {
        controller = VideoPlayerController.file(cached);
        await _setupController(controller);
        return;
      }

      // 4. Remote network streaming URL
      controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await _setupController(controller);
    } catch (e) {
      debugPrint("VideoViewer init error: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _setupController(VideoPlayerController controller) async {
    await controller.initialize();
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    await controller.play();
    if (mounted) {
      setState(() {
        _controller = controller;
        _isInitialized = true;
      });
    }
  }

  Future<File?> _resolveVideoFile() async {
    // 1. Local path
    if (widget.localPath != null && widget.localPath!.isNotEmpty) {
      final f = File(widget.localPath!);
      if (await f.exists()) return f;
    }

    final url = widget.videoUrl;
    if (url == null || url.isEmpty) return null;

    final cleanName = widget.fileName ?? 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // 2. Check cache
    final cached = await MediaStorageService.findLocalFile(category: 'Videos', fileName: cleanName);
    if (cached != null && await cached.exists()) return cached;

    // 3. Download
    return await MediaStorageService.downloadMediaToLocal(
      remoteUrl: url,
      category: 'Videos',
      targetFileName: cleanName,
    );
  }

  Future<void> _saveToDownloads() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    HapticFeedback.lightImpact();

    try {
      final file = await _resolveVideoFile();
      if (file == null || !await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not download video file.'),
              backgroundColor: AppTheme.callRed,
            ),
          );
        }
        return;
      }

      final fileName = widget.fileName ?? 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      Directory? targetDir;
      if (Platform.isAndroid) {
        final publicDownload = Directory('/storage/emulated/0/Download');
        if (await publicDownload.exists()) targetDir = publicDownload;
        final moviesDir = Directory('/storage/emulated/0/Movies/LiChat');
        if (await moviesDir.exists()) targetDir = moviesDir;
      }
      targetDir ??= await getApplicationDocumentsDirectory();

      final destination = File('${targetDir.path}/LiChat_$fileName');
      await file.copy(destination.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video saved to: ${destination.path.split('/').last}'),
            backgroundColor: AppTheme.bubbleMe,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(destination.path)])),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e'), backgroundColor: AppTheme.callRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _shareVideo() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    HapticFeedback.lightImpact();

    try {
      final file = await _resolveVideoFile();
      if (file != null && await file.exists()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: widget.title != null ? '${widget.title} - via LiChat' : 'Video via LiChat',
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not prepare video for sharing')),
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

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = _controller?.value.position ?? Duration.zero;
    final dur = _controller?.value.duration ?? Duration.zero;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => setState(() => _showControls = !_showControls),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Video Player Area
              Center(
                child: _hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 54),
                          const SizedBox(height: 12),
                          const Text('Could not play video', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                          ),
                        ],
                      )
                    : (_isInitialized && _controller != null
                        ? AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: VideoPlayer(_controller!),
                          )
                        : const CircularProgressIndicator(color: AppTheme.mint)),
              ),

              // 2. Play/Pause Center Indicator when paused
              if (_isInitialized && _controller != null && !_controller!.value.isPlaying)
                Center(
                  child: GestureDetector(
                    onTap: _togglePlayPause,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 56),
                    ),
                  ),
                ),

              // 3. Top Header Bar
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                top: _showControls ? 0 : -80,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title ?? 'Video',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.subtitle != null)
                              Text(
                                widget.subtitle!,
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      // Save / Download button
                      IconButton(
                        icon: _isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppTheme.mint, strokeWidth: 2))
                            : const Icon(Icons.download_rounded, color: Colors.white),
                        tooltip: 'Save to Device',
                        onPressed: _saveToDownloads,
                      ),
                      // Share button
                      IconButton(
                        icon: _isSharing
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppTheme.mint, strokeWidth: 2))
                            : const Icon(Icons.share_rounded, color: Colors.white),
                        tooltip: 'Share',
                        onPressed: _shareVideo,
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Bottom Controls Bar
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                bottom: _showControls ? 0 : -100,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Scrubbing progress slider
                      if (_isInitialized && _controller != null)
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: AppTheme.mint,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: AppTheme.mint,
                          ),
                          child: Slider(
                            value: pos.inMilliseconds.toDouble().clamp(0.0, dur.inMilliseconds.toDouble().clamp(1.0, double.infinity)),
                            min: 0.0,
                            max: dur.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                            onChanged: (val) {
                              _controller!.seekTo(Duration(milliseconds: val.toInt()));
                            },
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  _controller != null && _controller!.value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                onPressed: _togglePlayPause,
                              ),
                              IconButton(
                                icon: Icon(
                                  _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                  color: Colors.white70,
                                  size: 22,
                                ),
                                onPressed: _toggleMute,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${MediaStorageService.formatDuration(pos.inSeconds)} / ${MediaStorageService.formatDuration(dur.inSeconds)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.save_alt_rounded, color: AppTheme.mint, size: 18),
                            label: const Text('Save', style: TextStyle(color: AppTheme.mint, fontWeight: FontWeight.bold, fontSize: 13)),
                            onPressed: _saveToDownloads,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
