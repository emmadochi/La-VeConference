import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import '../services/status_upload_queue.dart';
import '../theme/app_theme.dart';
import '../widgets/status_privacy_dialog.dart';

class CreateMediaStatusScreen extends StatefulWidget {
  final File file;
  final String type; // 'image' or 'video'

  const CreateMediaStatusScreen({
    super.key,
    required this.file,
    this.type = 'image',
  });

  @override
  State<CreateMediaStatusScreen> createState() => _CreateMediaStatusScreenState();
}

class _CreateMediaStatusScreenState extends State<CreateMediaStatusScreen> {
  final TextEditingController _captionController = TextEditingController();

  StatusPrivacySettings _privacy = const StatusPrivacySettings(privacy: 'all');
  int _durationHours = 24;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    StatusPrivacySettings.load().then((p) {
      if (mounted) setState(() => _privacy = p);
    });

    if (widget.type == 'video') {
      _initVideoPlayer();
    }
  }

  Future<void> _initVideoPlayer() async {
    try {
      final ctrl = VideoPlayerController.file(widget.file);
      await ctrl.initialize();
      ctrl.setLooping(true);
      await ctrl.play();
      if (mounted) {
        setState(() {
          _videoController = ctrl;
          _isVideoInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Error initializing status video preview: $e");
    }
  }

  Future<void> _openPrivacyPicker() async {
    final updated = await StatusPrivacyDialog.show(context, _privacy);
    if (updated != null && mounted) {
      setState(() => _privacy = updated);
    }
  }

  Future<void> _openDurationPicker() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final textPrim = AppTheme.text(ctx);
        final textSec = AppTheme.textSec(ctx);
        final mint = AppTheme.mintColor(ctx);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.borderColor(ctx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.hourglass_bottom_rounded, color: mint, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Status Longevity',
                      style: TextStyle(color: textPrim, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Select how long your status remains visible before disappearing:',
                  style: TextStyle(color: textSec, fontSize: 13),
                ),
                const SizedBox(height: 16),
                for (final hours in [4, 12, 24, 48])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _durationHours == hours ? mint.withValues(alpha: 0.15) : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hours == 24 ? Icons.timer_rounded : Icons.schedule_rounded,
                        color: _durationHours == hours ? mint : textSec,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      '$hours Hours${hours == 24 ? ' (Standard 24h)' : ''}',
                      style: TextStyle(
                        color: _durationHours == hours ? mint : textPrim,
                        fontWeight: _durationHours == hours ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    trailing: _durationHours == hours
                        ? Icon(Icons.check_circle_rounded, color: mint, size: 22)
                        : null,
                    onTap: () => Navigator.pop(ctx, hours),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _durationHours = selected);
    }
  }

  void _postMediaStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    StatusUploadQueue.instance.enqueueMediaStatus(
      uid: user.uid,
      userName: user.displayName ?? 'Me',
      userAvatar: user.photoURL,
      file: widget.file,
      type: widget.type,
      caption: _captionController.text.trim(),
      privacy: _privacy.privacy,
      privacyUids: _privacy.selectedUids,
      durationHours: _durationHours,
    );

    // Instant 0ms exit back to status list
    Navigator.pop(context, true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Sending status update...'),
          ],
        ),
        backgroundColor: Color(0xFF1E1A36),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. Media Preview
            Positioned.fill(
              child: Center(
                child: widget.type == 'video'
                    ? (_isVideoInitialized && _videoController != null
                        ? GestureDetector(
                            onTap: () {
                              setState(() {
                                if (_videoController!.value.isPlaying) {
                                  _videoController!.pause();
                                } else {
                                  _videoController!.play();
                                }
                              });
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                AspectRatio(
                                  aspectRatio: _videoController!.value.aspectRatio,
                                  child: VideoPlayer(_videoController!),
                                ),
                                if (!_videoController!.value.isPlaying)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 48,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : const Center(
                            child: CircularProgressIndicator(color: AppTheme.mint),
                          ))
                    : Image.file(
                        widget.file,
                        fit: BoxFit.contain,
                      ),
              ),
            ),

            // 2. Top Action Bar
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  // Privacy Pill Button
                  GestureDetector(
                    onTap: _openPrivacyPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            _privacy.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 18),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Duration Longevity Pill
                  GestureDetector(
                    onTap: _openDurationPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer_outlined, color: Colors.white70, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${_durationHours}h',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 3. Bottom Caption Input Bar & Send Button
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1A36).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        cursorColor: AppTheme.mint,
                        decoration: const InputDecoration(
                          hintText: 'Add a caption...',
                          hintStyle: TextStyle(color: Colors.white54, fontSize: 15),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton(
                    heroTag: 'post_media_status_fab',
                    onPressed: _postMediaStatus,
                    backgroundColor: AppTheme.mint,
                    elevation: 4,
                    child: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
