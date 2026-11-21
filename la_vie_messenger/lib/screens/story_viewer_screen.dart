import 'dart:async';
import 'dart:convert';
import 'dart:io' as dart_io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Source;
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:share_plus/share_plus.dart';
import '../models/status_model.dart';
import '../services/status_service.dart';
import '../services/chat_service.dart';
import '../services/media_storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/share_to_status_dialog.dart';

class _FlyingReaction {
  final String emoji;
  final double leftRatio;
  final AnimationController controller;

  _FlyingReaction({
    required this.emoji,
    required this.leftRatio,
    required this.controller,
  });
}

class StoryViewerScreen extends StatefulWidget {
  final UserStatusGroup statusGroup;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.statusGroup,
    this.initialIndex = 0,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> with TickerProviderStateMixin {
  late int _currentIndex;
  late AnimationController _animController;
  final TextEditingController _replyController = TextEditingController();
  bool _isPaused = false;
  bool _isDismissed = false;
  final String? _myUid = FirebaseAuth.instance.currentUser?.uid;
  final List<_FlyingReaction> _flyingReactions = [];
  final math.Random _random = math.Random();

  final List<String> _quickEmojis = ['❤️', '😂', '🔥', '👏', '😮', '😢'];

  StatusItem get _currentItem => widget.statusGroup.items[_currentIndex];
  bool get _isMyStatus => _myUid != null && widget.statusGroup.uid == _myUid;

  Duration _getDurationForCurrentItem() {
    if (_currentItem.type == 'audio' &&
        _currentItem.duration != null &&
        _currentItem.duration! > 0) {
      return Duration(seconds: _currentItem.duration!);
    }
    if (_currentItem.type == 'video') {
      return const Duration(seconds: 15);
    }
    return const Duration(seconds: 5);
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.statusGroup.items.length - 1);

    _animController = AnimationController(
      vsync: this,
      duration: _getDurationForCurrentItem(),
    );

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });

    _recordCurrentStatusViewed();
    if (_currentItem.type != 'video' && _currentItem.type != 'audio') {
      _animController.forward();
    }
  }

  @override
  void dispose() {
    _isDismissed = true;
    _animController.dispose();
    _replyController.dispose();
    for (final r in _flyingReactions) {
      r.controller.dispose();
    }
    super.dispose();
  }

  void _dismissViewer() {
    if (_isDismissed || !mounted) return;
    _isDismissed = true;
    try {
      _animController.stop();
    } catch (_) {}
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _recordCurrentStatusViewed() {
    if (_isMyStatus || _myUid == null) return;
    final item = _currentItem;
    if (!item.hasBeenViewedBy(_myUid)) {
      final user = FirebaseAuth.instance.currentUser;
      StatusService.markStatusViewed(
        statusId: item.id,
        viewerUid: _myUid,
        viewerName: user?.displayName ?? 'A Contact',
        viewerAvatar: user?.photoURL,
      );
    }
  }

  void _nextStory() {
    if (_isDismissed || !mounted) return;
    if (_currentIndex < widget.statusGroup.items.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _animController.duration = _getDurationForCurrentItem();
      _animController.reset();
      _recordCurrentStatusViewed();
      if (_currentItem.type != 'video' && _currentItem.type != 'audio') {
        _animController.forward();
      }
    } else {
      _dismissViewer();
    }
  }

  void _prevStory() {
    if (_isDismissed || !mounted) return;
    if (_animController.value > 0.3) {
      _animController.reset();
      if (_currentItem.type != 'video' && _currentItem.type != 'audio') {
        _animController.forward();
      }
    } else if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _animController.duration = _getDurationForCurrentItem();
      _animController.reset();
      _recordCurrentStatusViewed();
      if (_currentItem.type != 'video' && _currentItem.type != 'audio') {
        _animController.forward();
      }
    }
  }

  void _pauseTimer() {
    if (!_isPaused && !_isDismissed) {
      setState(() => _isPaused = true);
      _animController.stop();
    }
  }

  void _resumeTimer() {
    if (_isPaused && !_isDismissed) {
      setState(() => _isPaused = false);
      _animController.forward();
    }
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, h:mm a').format(time);
  }

  TextStyle _getTextStyle(StatusItem item) {
    const baseColor = Colors.white;
    const baseSize = 28.0;

    switch (item.fontStyle) {
      case 'serif':
        return GoogleFonts.playfairDisplay(
          color: baseColor,
          fontSize: baseSize,
          fontWeight: FontWeight.w600,
        );
      case 'script':
        return GoogleFonts.caveat(
          color: baseColor,
          fontSize: baseSize + 8,
          fontWeight: FontWeight.w700,
        );
      case 'mono':
        return GoogleFonts.spaceMono(
          color: baseColor,
          fontSize: baseSize - 4,
          fontWeight: FontWeight.w500,
        );
      case 'modern':
      default:
        return GoogleFonts.plusJakartaSans(
          color: baseColor,
          fontSize: baseSize,
          fontWeight: FontWeight.bold,
        );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Save / Download Status
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _saveCurrentStory() async {
    _pauseTimer();
    final item = _currentItem;

    try {
      if (item.type == 'text') {
        await Share.share(item.content, subject: 'LiChat Status');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloading status to device...'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );

        final ext = item.type == 'video'
            ? 'mp4'
            : (item.type == 'audio' ? 'm4a' : 'jpg');
        final targetFileName = 'status_${item.id}.$ext';

        final file = await MediaStorageService.downloadMediaToLocal(
          remoteUrl: item.content,
          category: 'StatusDownloads',
          targetFileName: targetFileName,
        );

        if (file != null && await file.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved to ${file.path.split(dart_io.Platform.pathSeparator).last}!'),
                backgroundColor: AppTheme.bubbleMe,
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Share',
                  textColor: Colors.white,
                  onPressed: () => Share.shareXFiles([XFile(file.path)]),
                ),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to download media.'),
                backgroundColor: AppTheme.callRed,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save status: $e'),
            backgroundColor: AppTheme.callRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _resumeTimer();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Quick Emoji Reactions
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _sendQuickReaction(String emoji) async {
    if (_myUid == null) return;

    // Trigger visual floating animation
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    final reaction = _FlyingReaction(
      emoji: emoji,
      leftRatio: 0.15 + (_random.nextDouble() * 0.70),
      controller: ctrl,
    );
    setState(() => _flyingReactions.add(reaction));
    ctrl.forward().then((_) {
      if (mounted) {
        setState(() => _flyingReactions.remove(reaction));
      }
      ctrl.dispose();
    });

    // Send direct message
    final user = FirebaseAuth.instance.currentUser;
    final peerUid = widget.statusGroup.uid;
    final chatId = ChatService.getConversationId(_myUid, peerUid);

    String replyPreviewText = '📷 Photo Status';
    if (_currentItem.type == 'text') {
      replyPreviewText = _currentItem.content.length > 50
          ? '${_currentItem.content.substring(0, 50)}...'
          : _currentItem.content;
    } else if (_currentItem.type == 'audio') {
      replyPreviewText = '🎤 Voice Status (${_currentItem.duration ?? 0}s)';
    } else if (_currentItem.type == 'video') {
      replyPreviewText = '🎥 Video Status';
    }

    await ChatService.sendMessage(
      chatId: chatId,
      senderId: _myUid,
      senderName: user?.displayName ?? 'Me',
      receiverId: peerUid,
      text: emoji,
      replyTo: {
        'id': _currentItem.id,
        'senderName': widget.statusGroup.userName,
        'text': replyPreviewText,
        'type': _currentItem.type,
      },
    );

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('Reaction sent to chat!'),
            ],
          ),
          backgroundColor: AppTheme.bubbleMe,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Viewers Sheet with Live Updates
  // ─────────────────────────────────────────────────────────────────────────
  void _showViewersSheet() {
    _pauseTimer();
    final statusId = _currentItem.id;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF19162C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('statuses').doc(statusId).snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data() ?? {};
              final viewerInfo = Map<String, dynamic>.from(data['viewerInfo'] ?? _currentItem.viewerInfo);
              final viewersList = viewerInfo.entries.toList();

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          const Icon(Icons.visibility_rounded, color: AppTheme.mint, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Viewed by ${viewersList.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),

                          // Save to device button
                          IconButton(
                            icon: const Icon(Icons.download_rounded, color: Colors.white70),
                            tooltip: 'Save to device',
                            onPressed: () {
                              Navigator.pop(ctx);
                              _saveCurrentStory();
                            },
                          ),

                          // Delete button
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.callRed),
                            tooltip: 'Delete Status',
                            onPressed: () async {
                              Navigator.pop(ctx);
                              _confirmDeleteStatus();
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12),
                    if (viewersList.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                        child: Center(
                          child: Text(
                            'No views yet. Share updates with your contacts!',
                            style: TextStyle(color: Colors.white54, fontSize: 14),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: viewersList.length,
                          itemBuilder: (context, idx) {
                            final v = viewersList[idx].value as Map<String, dynamic>;
                            final name = v['name'] as String? ?? 'Contact';
                            final avatar = v['avatar'] as String?;
                            final dynamic viewedRaw = v['viewedAt'];
                            final viewedAt = viewedRaw is Timestamp
                                ? viewedRaw.toDate()
                                : DateTime.now();

                            return ListTile(
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: AppTheme.surface,
                                backgroundImage: MediaStorageService.getAvatarProvider(avatar),
                                child: (avatar == null || avatar.isEmpty)
                                    ? const Icon(Icons.person_rounded, color: AppTheme.mint, size: 20)
                                    : null,
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              trailing: Text(
                                _formatTimeAgo(viewedAt),
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      _resumeTimer();
    });
  }

  Future<void> _confirmDeleteStatus() async {
    _pauseTimer();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this status?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This status update will be permanently deleted for all contacts.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.callRed),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteCurrentStatus();
    } else {
      _resumeTimer();
    }
  }

  Future<void> _deleteCurrentStatus() async {
    final statusId = _currentItem.id;
    await StatusService.deleteStatus(statusId);
    if (!mounted) return;

    if (widget.statusGroup.items.length <= 1) {
      _dismissViewer();
    } else {
      widget.statusGroup.items.removeAt(_currentIndex);
      if (_currentIndex >= widget.statusGroup.items.length) {
        _currentIndex = widget.statusGroup.items.length - 1;
      }
      setState(() {});
      _animController.duration = _getDurationForCurrentItem();
      _animController.reset();
      if (_currentItem.type != 'video' && _currentItem.type != 'audio') {
        _animController.forward();
      }
    }
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _myUid == null) return;

    final user = FirebaseAuth.instance.currentUser;
    final peerUid = widget.statusGroup.uid;
    final chatId = ChatService.getConversationId(_myUid, peerUid);

    _replyController.clear();
    Navigator.pop(context);

    await ChatService.sendMessage(
      chatId: chatId,
      senderId: _myUid,
      senderName: user?.displayName ?? 'Me',
      receiverId: peerUid,
      text: 'Replied to status: "$text"',
      replyTo: {
        'id': _currentItem.id,
        'senderName': widget.statusGroup.userName,
        'text': _currentItem.type == 'text'
            ? _currentItem.content
            : (_currentItem.type == 'audio'
                ? '🎤 Voice Status'
                : '📷 Photo Status'),
        'type': _currentItem.type,
      },
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reply sent!'),
          backgroundColor: AppTheme.bubbleMe,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentItem;
    final totalItems = widget.statusGroup.items.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => _pauseTimer(),
        onLongPressEnd: (_) => _resumeTimer(),
        child: Stack(
          children: [
            // 1. Main Slide Content Area
            Positioned.fill(
              child: item.type == 'text'
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: item.gradientColors.map((c) => Color(c)).toList(),
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      alignment: Alignment.center,
                      child: Text(
                        item.content,
                        textAlign: TextAlign.center,
                        style: _getTextStyle(item),
                      ),
                    )
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: _StatusMediaWidget(
                            key: ValueKey('${item.id}_${item.content.hashCode}'),
                            item: item,
                            isPaused: _isPaused,
                            onPause: _pauseTimer,
                            onResume: _resumeTimer,
                            onVideoReady: (dur) {
                              if (mounted && item == _currentItem) {
                                _animController.duration = dur;
                                if (!_isPaused) {
                                  _animController.forward(from: 0.0);
                                }
                              }
                            },
                            onVideoComplete: () {
                              if (mounted && item == _currentItem) {
                                _nextStory();
                              }
                            },
                            onAudioReady: (dur) {
                              if (mounted && item == _currentItem) {
                                _animController.duration = dur;
                                if (!_isPaused) {
                                  _animController.forward(from: 0.0);
                                }
                              }
                            },
                            onAudioComplete: () {
                              if (mounted && item == _currentItem) {
                                _nextStory();
                              }
                            },
                          ),
                        ),
                        if (item.caption != null && item.caption!.isNotEmpty)
                          Positioned(
                            bottom: _isMyStatus ? 70 : 120,
                            left: 20,
                            right: 20,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                item.caption!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),

            // 2. Navigation Hit-Boxes
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _prevStory,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _nextStory,
                    ),
                  ),
                ],
              ),
            ),

            // 3. Floating Reaction Flying Particles
            ..._flyingReactions.map((r) {
              return AnimatedBuilder(
                animation: r.controller,
                builder: (context, child) {
                  final progress = r.controller.value;
                  final bottom = 120.0 + (progress * 380.0);
                  final opacity = (1.0 - progress).clamp(0.0, 1.0);
                  final scale = 1.0 + (progress * 0.8);

                  return Positioned(
                    bottom: bottom,
                    left: MediaQuery.of(context).size.width * r.leftRatio,
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
                        child: Text(
                          r.emoji,
                          style: const TextStyle(fontSize: 34),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),

            // 4. Top Header Bar & Progress Indicators
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Segmented Progress Bars
                      Row(
                        children: List.generate(totalItems, (idx) {
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: AnimatedBuilder(
                                animation: _animController,
                                builder: (context, _) {
                                  double progress = 0.0;
                                  if (idx < _currentIndex) {
                                    progress = 1.0;
                                  } else if (idx == _currentIndex) {
                                    progress = _animController.value;
                                  }
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      backgroundColor: Colors.white.withValues(alpha: 0.35),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                      minHeight: 2.8,
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 12),

                      // User Info & Actions
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 19,
                            backgroundColor: AppTheme.surfaceElevated,
                            backgroundImage: MediaStorageService.getAvatarProvider(widget.statusGroup.userAvatar),
                            child: (widget.statusGroup.userAvatar == null || widget.statusGroup.userAvatar!.isEmpty)
                                ? const Icon(Icons.person_rounded, color: AppTheme.mint, size: 20)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isMyStatus ? 'My Status' : widget.statusGroup.userName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _formatTimeAgo(item.createdAt),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Save to Device icon
                          IconButton(
                            icon: const Icon(Icons.download_rounded, color: Colors.white, size: 22),
                            tooltip: 'Save to device',
                            onPressed: _saveCurrentStory,
                          ),

                          // Close button
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                            onPressed: _dismissViewer,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 5. Bottom Controls: Reply Bar + Quick Reactions OR Viewers Pill
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: SafeArea(
                child: _isMyStatus
                    ? Center(
                        child: InkWell(
                          onTap: _showViewersSheet,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.visibility_rounded, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  '${item.viewers.length} views',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white70, size: 18),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Quick Emoji Reaction Bar
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1A36).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: _quickEmojis.map((emoji) {
                                return GestureDetector(
                                  onTap: () => _sendQuickReaction(emoji),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    child: Text(
                                      emoji,
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          // Reply Bar + Reshare button
                          Row(
                            children: [
                              // Reshare status button
                              Tooltip(
                                message: 'Share to your Status',
                                child: GestureDetector(
                                  onTap: () {
                                    _pauseTimer();
                                    final shareData = <String, dynamic>{
                                      'type': item.type == 'text' ? 'text' : 'image',
                                      'text': item.type == 'text'
                                          ? item.content
                                          : (item.caption ?? ''),
                                      'mediaUrl': item.type != 'text' ? item.content : null,
                                    };
                                    ShareToStatusDialog.show(context, shareData)
                                        .then((_) => _resumeTimer());
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E1A36).withValues(alpha: 0.85),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                    ),
                                    child: const Icon(Icons.reply_all_rounded, color: Colors.white, size: 22),
                                  ),
                                ),
                              ),

                              // Text Reply Input
                              Expanded(
                                child: Container(
                                  height: 48,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E1A36).withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                  ),
                                  child: TextField(
                                    controller: _replyController,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    cursorColor: AppTheme.mint,
                                    onTap: _pauseTimer,
                                    onSubmitted: (_) => _sendReply(),
                                    decoration: InputDecoration(
                                      hintText: 'Reply to ${widget.statusGroup.userName}...',
                                      hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Send button
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: AppTheme.mint,
                                child: IconButton(
                                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                                  onPressed: _sendReply,
                                ),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Smart media renderer: handles data: URIs, https:// images, videos, and audio
// ─────────────────────────────────────────────────────────────────────────────
class _StatusMediaWidget extends StatefulWidget {
  final StatusItem item;
  final bool isPaused;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final void Function(Duration duration)? onVideoReady;
  final VoidCallback? onVideoComplete;
  final void Function(Duration duration)? onAudioReady;
  final VoidCallback? onAudioComplete;

  const _StatusMediaWidget({
    super.key,
    required this.item,
    this.isPaused = false,
    this.onPause,
    this.onResume,
    this.onVideoReady,
    this.onVideoComplete,
    this.onAudioReady,
    this.onAudioComplete,
  });

  @override
  State<_StatusMediaWidget> createState() => _StatusMediaWidgetState();
}

class _StatusMediaWidgetState extends State<_StatusMediaWidget>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoController;
  VoidCallback? _videoListener;
  AudioPlayer? _audioPlayer;
  AnimationController? _pulseController;
  bool _mediaReady = false;
  bool _mediaError = false;
  bool _isAudioPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.type == 'video') {
      _initVideo();
    } else if (widget.item.type == 'audio') {
      _initAudio();
    }
  }

  @override
  void didUpdateWidget(_StatusMediaWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused != oldWidget.isPaused) {
      if (widget.isPaused) {
        _videoController?.pause();
        _audioPlayer?.pause();
      } else {
        if (_mediaReady) {
          _videoController?.play();
          _audioPlayer?.resume();
        }
      }
    }
  }

  void _onVideoTick() {
    if (!mounted || _videoController == null) return;
    try {
      final ctrl = _videoController!;
      if (ctrl.value.isInitialized &&
          !ctrl.value.isPlaying &&
          ctrl.value.duration > Duration.zero &&
          ctrl.value.position >= ctrl.value.duration) {
        widget.onVideoComplete?.call();
      }
    } catch (_) {}
  }

  Future<void> _initVideo() async {
    try {
      final content = widget.item.content;
      VideoPlayerController controller;

      if (content.startsWith('data:')) {
        final comma = content.indexOf(',');
        if (comma == -1) {
          setState(() => _mediaError = true);
          return;
        }
        final bytes = base64Decode(content.substring(comma + 1));
        final dir = await MediaStorageService.getCategoryDirectory('StatusCache');
        final tmpFile = dart_io.File('${dir.path}/tmp_status_${widget.item.id}.mp4');
        await tmpFile.writeAsBytes(bytes);
        controller = VideoPlayerController.file(tmpFile);
      } else {
        // Fast local file check: if user posted it or previously cached it, play immediately with 0ms delay
        dart_io.File? localFile;
        try {
          final uri = Uri.tryParse(content);
          final rawFileName = uri != null && uri.pathSegments.isNotEmpty
              ? uri.pathSegments.last
              : 'status_${widget.item.id}.mp4';
          localFile = await MediaStorageService.findLocalFile(
            category: 'StatusDownloads',
            fileName: rawFileName,
          );
          if (localFile == null || !await localFile.exists()) {
            localFile = await MediaStorageService.findLocalFile(
              category: 'StatusDownloads',
              fileName: 'status_${widget.item.id}.mp4',
            );
          }
        } catch (_) {}

        if (localFile != null && await localFile.exists()) {
          controller = VideoPlayerController.file(localFile);
        } else {
          controller = VideoPlayerController.networkUrl(Uri.parse(content));
        }
      }

      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.setLooping(false);
      _videoListener = _onVideoTick;
      controller.addListener(_videoListener!);

      if (!widget.isPaused) {
        await controller.play();
      }
      if (!mounted) {
        controller.removeListener(_videoListener!);
        controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _mediaReady = true;
      });
      if (controller.value.duration > Duration.zero) {
        widget.onVideoReady?.call(controller.value.duration);
      }
    } catch (e) {
      debugPrint('Video init error: $e');
      if (mounted) setState(() => _mediaError = true);
    }
  }

  Future<void> _initAudio() async {
    try {
      _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat(reverse: true);

      _audioPlayer = AudioPlayer();
      _audioPlayer!.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() => _isAudioPlaying = state == PlayerState.playing);
        }
      });
      _audioPlayer!.onPlayerComplete.listen((_) {
        widget.onAudioComplete?.call();
      });
      _audioPlayer!.onDurationChanged.listen((dur) {
        if (dur > Duration.zero) {
          widget.onAudioReady?.call(dur);
        }
      });

      Source source = UrlSource(widget.item.content);
      try {
        final localAudio = await MediaStorageService.findLocalFile(
          category: 'StatusDownloads',
          fileName: 'status_${widget.item.id}.m4a',
        );
        if (localAudio != null && await localAudio.exists()) {
          source = DeviceFileSource(localAudio.path);
        }
      } catch (_) {}

      await _audioPlayer!.play(source);
      if (!mounted) return;
      setState(() {
        _mediaReady = true;
        _isAudioPlaying = true;
      });
      if (widget.item.duration != null && widget.item.duration! > 0) {
        widget.onAudioReady?.call(Duration(seconds: widget.item.duration!));
      }
    } catch (e) {
      debugPrint('Audio status play error: $e');
      if (mounted) setState(() => _mediaError = true);
    }
  }

  @override
  void dispose() {
    if (_videoController != null) {
      if (_videoListener != null) {
        _videoController!.removeListener(_videoListener!);
        _videoListener = null;
      }
      try {
        _videoController!.pause();
      } catch (_) {}
      _videoController!.dispose();
      _videoController = null;
    }
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _pulseController?.dispose();
    super.dispose();
  }

  Widget _buildAudio() {
    final colors = widget.item.gradientColors.map((c) => Color(c)).toList();
    final avatar = widget.item.userAvatar;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors.length >= 2 ? colors : [const Color(0xFF7C3AED), const Color(0xFF9333EA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing Avatar Card
            Stack(
              alignment: Alignment.center,
              children: [
                if (_pulseController != null && _isAudioPlaying)
                  AnimatedBuilder(
                    animation: _pulseController!,
                    builder: (context, child) {
                      return Container(
                        width: 140 + (_pulseController!.value * 35),
                        height: 140 + (_pulseController!.value * 35),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.15 * (1.0 - _pulseController!.value)),
                        ),
                      );
                    },
                  ),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor: Colors.white12,
                      backgroundImage: MediaStorageService.getAvatarProvider(avatar),
                      child: (avatar == null || avatar.isEmpty)
                          ? const Icon(Icons.mic_rounded, color: Colors.white, size: 48)
                          : null,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Play / Pause toggle
            IconButton(
              onPressed: () {
                if (_audioPlayer == null) return;
                if (_isAudioPlaying) {
                  _audioPlayer!.pause();
                  widget.onPause?.call();
                } else {
                  _audioPlayer!.resume();
                  widget.onResume?.call();
                }
              },
              icon: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: Icon(
                  _isAudioPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: colors.first,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isAudioPlaying ? 'Playing voice status...' : 'Paused',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    final content = widget.item.content;

    if (content.startsWith('data:')) {
      return FutureBuilder<Uint8List>(
        future: _decodeBase64Bytes(content),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _errorWidget('Could not decode image');
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.mint));
          }
          return Center(
            child: Image(
              image: MemoryImage(snapshot.data!),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _errorWidget('Failed to display image'),
            ),
          );
        },
      );
    }

    return Center(
      child: Image.network(
        content,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: AppTheme.mint,
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                      : null,
                ),
                const SizedBox(height: 12),
                const Text('Loading…', style: TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          );
        },
        errorBuilder: (_, error, __) {
          debugPrint('Image.network error: $error');
          return _errorWidget('Failed to load image');
        },
      ),
    );
  }

  static Future<Uint8List> _decodeBase64Bytes(String dataUri) async {
    final comma = dataUri.indexOf(',');
    if (comma == -1) throw Exception('Malformed data URI');
    return base64Decode(dataUri.substring(comma + 1));
  }

  Widget _buildVideo() {
    if (_mediaError) return _errorWidget('Failed to load video');

    final ctrl = _videoController;
    if (!_mediaReady || ctrl == null || !ctrl.value.isInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.mint),
            SizedBox(height: 12),
            Text('Loading video…', style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );
    }

    final double rawAr = ctrl.value.aspectRatio;
    final double safeAr = (rawAr.isFinite && rawAr > 0.0) ? rawAr : (9 / 16);

    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: safeAr,
            child: VideoPlayer(ctrl),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (!mounted || _videoController == null) return;
            setState(() {
              if (_videoController!.value.isPlaying) {
                _videoController!.pause();
              } else {
                _videoController!.play();
              }
            });
          },
          child: AnimatedOpacity(
            opacity: ctrl.value.isPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(16),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorWidget(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, color: Colors.white.withValues(alpha: 0.4), size: 64),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            'Pull down to dismiss',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.type == 'audio') return _buildAudio();
    if (widget.item.type == 'video') return _buildVideo();
    return _buildImage();
  }
}
