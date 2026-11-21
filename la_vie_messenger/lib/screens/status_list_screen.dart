import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/status_model.dart';
import '../services/status_service.dart';
import '../services/status_upload_queue.dart';
import '../services/media_storage_service.dart';
import '../theme/app_theme.dart';
import 'create_text_status_screen.dart';
import 'create_media_status_screen.dart';
import 'create_audio_status_screen.dart';
import 'story_viewer_screen.dart';

class SegmentedStatusPainter extends CustomPainter {
  final int count;
  final int seenCount;
  final Color activeColor;
  final Color seenColor;
  final double strokeWidth;

  SegmentedStatusPainter({
    required this.count,
    required this.seenCount,
    required this.activeColor,
    required this.seenColor,
    this.strokeWidth = 2.4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 1) {
      final paint = Paint()
        ..color = (count == 1 && seenCount == 0) ? activeColor : seenColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), (size.width - strokeWidth) / 2, paint);
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const gapAngle = 0.08;
    final totalGap = count * gapAngle;
    final arcLength = (2 * pi - totalGap) / count;

    double startAngle = -pi / 2 + (gapAngle / 2);
    for (int i = 0; i < count; i++) {
      final isSeen = i < seenCount;
      final paint = Paint()
        ..color = isSeen ? seenColor : activeColor
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        arcLength,
        false,
        paint,
      );
      startAngle += arcLength + gapAngle;
    }
  }

  @override
  bool shouldRepaint(covariant SegmentedStatusPainter oldDelegate) {
    return oldDelegate.count != count ||
        oldDelegate.seenCount != seenCount ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.seenColor != seenColor;
  }
}

class StatusListScreen extends StatefulWidget {
  const StatusListScreen({super.key});

  @override
  State<StatusListScreen> createState() => _StatusListScreenState();
}

class _StatusListScreenState extends State<StatusListScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImageAndCreateStatus(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1280,
      );
      if (picked != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateMediaStatusScreen(file: File(picked.path)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access media: $e'), backgroundColor: AppTheme.callRed),
        );
      }
    }
  }

  Future<void> _pickVideoAndCreateStatus(ImageSource source) async {
    try {
      final picked = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60),
      );
      if (picked != null && mounted) {
        final f = File(picked.path);
        final size = await f.length();
        if (size > 50 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Video exceeds 50 MB limit. Please select a shorter or compressed video.'),
                backgroundColor: AppTheme.callRed,
              ),
            );
          }
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateMediaStatusScreen(file: f, type: 'video'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access video: $e'), backgroundColor: AppTheme.callRed),
        );
      }
    }
  }

  void _showMediaSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevatedColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.mint),
                  title: Text('Camera (Photo)', style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImageAndCreateStatus(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_rounded, color: Colors.orangeAccent),
                  title: Text('Record Video', style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickVideoAndCreateStatus(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded, color: AppTheme.mint),
                  title: Text('Photo Gallery', style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImageAndCreateStatus(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.video_library_rounded, color: Colors.pinkAccent),
                  title: Text('Video Gallery', style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickVideoAndCreateStatus(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, h:mm a').format(time);
  }

  Widget _buildStatusAvatar({
    required String? avatarUrl,
    required bool hasUnseen,
    required int count,
    int seenCount = 0,
    required BuildContext context,
    double radius = 26,
    bool isUploading = false,
    double uploadProgress = 0.0,
    bool isFailed = false,
  }) {
    final mint = AppTheme.mintColor(context);
    final isDark = AppTheme.isDarkMode(context);
    final seenColor = isDark ? Colors.white24 : Colors.black12;

    if (isUploading) {
      return SizedBox(
        width: (radius + 4) * 2,
        height: (radius + 4) * 2,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: (radius + 3) * 2,
              height: (radius + 3) * 2,
              child: CircularProgressIndicator(
                value: uploadProgress > 0 ? uploadProgress : null,
                strokeWidth: 2.8,
                color: mint,
                backgroundColor: seenColor,
              ),
            ),
            CircleAvatar(
              radius: radius,
              backgroundColor: AppTheme.surfaceColor(context),
              backgroundImage: MediaStorageService.getAvatarProvider(avatarUrl),
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? Icon(Icons.person_rounded, color: mint, size: radius * 0.9)
                  : null,
            ),
          ],
        ),
      );
    }

    if (count > 1) {
      return CustomPaint(
        painter: SegmentedStatusPainter(
          count: count,
          seenCount: seenCount,
          activeColor: mint,
          seenColor: seenColor,
          strokeWidth: 2.4,
        ),
        child: Container(
          padding: const EdgeInsets.all(4.0),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: AppTheme.surfaceColor(context),
            backgroundImage: MediaStorageService.getAvatarProvider(avatarUrl),
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? Icon(Icons.person_rounded, color: mint, size: radius * 0.9)
                : null,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: hasUnseen
              ? mint
              : seenColor,
          width: 2.2,
        ),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.surfaceColor(context),
        backgroundImage: MediaStorageService.getAvatarProvider(avatarUrl),
        child: (avatarUrl == null || avatarUrl.isEmpty)
            ? Icon(Icons.person_rounded, color: mint, size: radius * 0.9)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final myUid = user?.uid ?? '';
    final bg = AppTheme.bg(context);
    final surfaceElevated = AppTheme.surfaceElevatedColor(context);
    final textPrim = AppTheme.text(context);
    final textMuted = AppTheme.textMut(context);
    final border = AppTheme.borderColor(context);
    final mint = AppTheme.mintColor(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(
          'Updates',
          style: TextStyle(
            color: textPrim,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70), // Keep clear of mobile floating capsule
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pencil FAB (Text Status)
            SizedBox(
              width: 44,
              height: 44,
              child: FloatingActionButton(
                heroTag: 'fab_text_status',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateTextStatusScreen()),
                  );
                },
                backgroundColor: surfaceElevated,
                elevation: 3,
                child: Icon(Icons.edit_rounded, color: textPrim, size: 20),
              ),
            ),
            const SizedBox(height: 10),

            // Mic FAB (Voice / Audio Status)
            SizedBox(
              width: 44,
              height: 44,
              child: FloatingActionButton(
                heroTag: 'fab_audio_status',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateAudioStatusScreen()),
                  );
                },
                backgroundColor: surfaceElevated,
                elevation: 3,
                child: Icon(Icons.mic_rounded, color: mint, size: 21),
              ),
            ),
            const SizedBox(height: 12),

            // Camera FAB (Media Status)
            FloatingActionButton(
              heroTag: 'fab_media_status',
              onPressed: _showMediaSourceDialog,
              backgroundColor: mint,
              elevation: 4,
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 24),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<UserStatusGroup>>(
        stream: StatusService.streamActiveStatusGroups(myUid: myUid),
        builder: (context, snapshot) {
          final groups = snapshot.data ?? [];
          UserStatusGroup? myGroup;
          final List<UserStatusGroup> recentUpdates = [];
          final List<UserStatusGroup> viewedUpdates = [];

          for (final g in groups) {
            if (g.uid == myUid) {
              myGroup = g;
            } else if (g.hasUnseenBy(myUid)) {
              recentUpdates.add(g);
            } else {
              viewedUpdates.add(g);
            }
          }

          final hasMyStatus = myGroup != null && myGroup.items.isNotEmpty;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // 1. My Status Tile
              AnimatedBuilder(
                animation: StatusUploadQueue.instance,
                builder: (context, _) {
                  final uploadTask = StatusUploadQueue.instance.currentTask;
                  final isUploading = uploadTask != null && uploadTask.state == StatusUploadState.uploading;
                  final isFailed = uploadTask != null && uploadTask.state == StatusUploadState.failed;

                  String subtitleText;
                  Color subtitleColor = textMuted;

                  if (isUploading) {
                    final pct = (uploadTask.progress * 100).toInt();
                    subtitleText = pct > 0 ? 'Sending status update... ($pct%)' : 'Sending status update...';
                    subtitleColor = mint;
                  } else if (isFailed) {
                    subtitleText = "Couldn't send • Tap to retry";
                    subtitleColor = AppTheme.callRed;
                  } else if (hasMyStatus && myGroup != null) {
                    subtitleText = '${_formatTimeAgo(myGroup.lastUpdated)} • ${myGroup.latestItem?.viewers.length ?? 0} views';
                  } else {
                    subtitleText = 'Tap to add status update';
                  }

                  Widget? trailingWidget;
                  if (isUploading) {
                    trailingWidget = const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: AppTheme.mint),
                    );
                  } else if (isFailed) {
                    trailingWidget = IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: AppTheme.callRed),
                      tooltip: 'Retry upload',
                      onPressed: () => StatusUploadQueue.instance.retry(uploadTask.id),
                    );
                  } else if (hasMyStatus) {
                    trailingWidget = IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.mint),
                      tooltip: 'Add another update',
                      onPressed: _showMediaSourceDialog,
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: surfaceElevated.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isFailed
                            ? AppTheme.callRed.withValues(alpha: 0.6)
                            : border.withValues(alpha: 0.7),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: Stack(
                        children: [
                          _buildStatusAvatar(
                            avatarUrl: user?.photoURL,
                            hasUnseen: hasMyStatus || isUploading,
                            count: myGroup?.items.length ?? 0,
                            seenCount: 0,
                            context: context,
                            radius: 24,
                            isUploading: isUploading,
                            uploadProgress: uploadTask?.progress ?? 0.0,
                            isFailed: isFailed,
                          ),
                          if (!hasMyStatus && !isUploading && !isFailed)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: mint,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: bg, width: 2),
                                ),
                                child: const Icon(Icons.add_rounded, color: Colors.white, size: 14),
                              ),
                            ),
                          if (isFailed)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: AppTheme.callRed,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: bg, width: 2),
                                ),
                                child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 13),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        'My Status',
                        style: TextStyle(
                          color: textPrim,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        subtitleText,
                        style: TextStyle(color: subtitleColor, fontSize: 13),
                      ),
                      trailing: trailingWidget,
                      onTap: () {
                        if (isFailed) {
                          StatusUploadQueue.instance.retry(uploadTask.id);
                        } else if (hasMyStatus) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StoryViewerScreen(statusGroup: myGroup!),
                            ),
                          );
                        } else {
                          _showMediaSourceDialog();
                        }
                      },
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // 2. Recent Updates Section
              if (recentUpdates.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'RECENT UPDATES',
                    style: TextStyle(
                      color: mint,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: surfaceElevated.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border.withValues(alpha: 0.6)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: recentUpdates.length,
                    separatorBuilder: (_, __) => Divider(color: border.withValues(alpha: 0.4), height: 1),
                    itemBuilder: (context, idx) {
                      final group = recentUpdates[idx];
                      return ListTile(
                        leading: _buildStatusAvatar(
                          avatarUrl: group.userAvatar,
                          hasUnseen: true,
                          count: group.items.length,
                          seenCount: group.seenCountBy(myUid),
                          context: context,
                        ),
                        title: Text(
                          group.userName,
                          style: TextStyle(color: textPrim, fontWeight: FontWeight.bold, fontSize: 15.5),
                        ),
                        subtitle: Text(
                          _formatTimeAgo(group.lastUpdated),
                          style: TextStyle(color: textMuted, fontSize: 13),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StoryViewerScreen(statusGroup: group),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // 3. Viewed Updates Section
              if (viewedUpdates.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'VIEWED UPDATES',
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: surfaceElevated.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border.withValues(alpha: 0.6)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: viewedUpdates.length,
                    separatorBuilder: (_, __) => Divider(color: border.withValues(alpha: 0.4), height: 1),
                    itemBuilder: (context, idx) {
                      final group = viewedUpdates[idx];
                      return ListTile(
                        leading: _buildStatusAvatar(
                          avatarUrl: group.userAvatar,
                          hasUnseen: false,
                          count: group.items.length,
                          seenCount: group.seenCountBy(myUid),
                          context: context,
                        ),
                        title: Text(
                          group.userName,
                          style: TextStyle(color: textPrim, fontWeight: FontWeight.w600, fontSize: 15.5),
                        ),
                        subtitle: Text(
                          _formatTimeAgo(group.lastUpdated),
                          style: TextStyle(color: textMuted, fontSize: 13),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StoryViewerScreen(statusGroup: group),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],

              // 4. Empty State
              if (recentUpdates.isEmpty && viewedUpdates.isEmpty && !hasMyStatus)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 56, color: textMuted.withValues(alpha: 0.4)),
                      const SizedBox(height: 14),
                      Text(
                        'No Status Updates Yet',
                        style: TextStyle(color: textPrim, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Share a 24-hour update with your contacts using the camera or pencil buttons below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textMuted, fontSize: 13.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

              // Bottom padding for scroll clear
              const SizedBox(height: 100),
            ],
          );
        },
      ),
    );
  }
}
