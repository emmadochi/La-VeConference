import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../services/active_call_manager.dart';
import '../theme/app_theme.dart';

class FloatingCallOverlay extends StatefulWidget {
  const FloatingCallOverlay({super.key});

  @override
  State<FloatingCallOverlay> createState() => _FloatingCallOverlayState();
}

class _FloatingCallOverlayState extends State<FloatingCallOverlay> {
  Offset _position = const Offset(16, 100);
  double? _audioTop;

  @override
  void initState() {
    super.initState();
    ActiveCallManager.instance.addListener(_onCallStateChanged);
  }

  @override
  void dispose() {
    ActiveCallManager.instance.removeListener(_onCallStateChanged);
    super.dispose();
  }

  void _onCallStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final callManager = ActiveCallManager.instance;
    if (!callManager.hasActiveCall || !callManager.isMinimized) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.of(context).size;
    final remoteVideos = callManager.getRemoteVideoTracks();
    final localVideo = callManager.getLocalVideoTrack();
    final hasVideo = remoteVideos.isNotEmpty || localVideo != null;

    if (!hasVideo) {
      // Audio Call: Sleek top-docked active call banner / pill (movable so it never blocks chat)
      final topPadding = MediaQuery.of(context).padding.top;
      final defaultTop = topPadding + 6.0;
      final currentTop = (_audioTop ?? defaultTop).clamp(defaultTop, size.height - 120.0);

      return Positioned(
        top: currentTop,
        left: 12,
        right: 12,
        child: GestureDetector(
          onVerticalDragUpdate: (details) {
            setState(() {
              _audioTop = (_audioTop ?? defaultTop) + details.delta.dy;
            });
          },
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D2820), Color(0xFF14382C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppTheme.mint.withValues(alpha: 0.8), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                  BoxShadow(
                    color: AppTheme.mint.withValues(alpha: 0.18),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Tappable caller info to maximize call
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => callManager.maximize(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                color: AppTheme.mint,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.phone_in_talk_rounded, color: Colors.black, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    callManager.peerName.isNotEmpty ? callManager.peerName : 'LiChat Voice Call',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Tap to return • ${callManager.formattedDuration}',
                                    style: const TextStyle(color: AppTheme.mint, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Quick controls
                  IconButton(
                    iconSize: 19,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      callManager.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: callManager.isMuted ? Colors.redAccent : Colors.white70,
                    ),
                    onPressed: () => callManager.toggleMute(),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    iconSize: 19,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      callManager.isSpeakerOn ? Icons.volume_up_rounded : Icons.phone_android_rounded,
                      color: callManager.isSpeakerOn ? AppTheme.mint : Colors.white70,
                    ),
                    tooltip: callManager.isSpeakerOn ? 'Loudspeaker On' : 'Earpiece',
                    onPressed: () => callManager.toggleSpeaker(),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => callManager.endCall(),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: AppTheme.callRed,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Video Call: Floating draggable PiP window with active video feed
    // Constrain position within screen
    final currentX = _position.dx.clamp(10.0, size.width - 170.0);
    final currentY = _position.dy.clamp(40.0, size.height - 230.0);

    return Positioned(
      left: currentX,
      top: currentY,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        onTap: () => callManager.maximize(),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: 155,
            height: 210,
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.mint, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: AppTheme.mint.withValues(alpha: 0.2),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Remote Video feed or Local preview or Avatar
                  if (remoteVideos.isNotEmpty && !remoteVideos.first.isDisposed)
                    VideoTrackRenderer(
                      remoteVideos.first,
                      key: ValueKey('floating_remote_${remoteVideos.first.sid ?? remoteVideos.first.hashCode}'),
                      fit: VideoViewFit.cover,
                    )
                  else if (localVideo != null && !localVideo.isDisposed)
                    Transform.scale(
                      scaleX: callManager.isFrontCamera ? -1 : 1,
                      child: VideoTrackRenderer(
                        localVideo,
                        key: ValueKey('floating_local_${localVideo.sid ?? localVideo.hashCode}'),
                        fit: VideoViewFit.cover,
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTheme.surfaceElevated, Color(0xFF0C2420)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: AppTheme.mint.withValues(alpha: 0.2),
                            child: Text(
                              callManager.peerName.isNotEmpty ? callManager.peerName[0].toUpperCase() : 'U',
                              style: const TextStyle(color: AppTheme.mint, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            callManager.peerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            callManager.formattedDuration,
                            style: const TextStyle(color: AppTheme.mint, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),

                  // Mini Inset Local Video Preview when both remote and local are active
                  if (remoteVideos.isNotEmpty && localVideo != null)
                    Positioned(
                      top: 30,
                      right: 6,
                      width: 42,
                      height: 58,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.mint.withValues(alpha: 0.8), width: 1.2),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Transform.scale(
                            scaleX: callManager.isFrontCamera ? -1 : 1,
                            child: VideoTrackRenderer(
                              localVideo,
                              key: ValueKey('floating_mini_local_${localVideo.sid ?? localVideo.hashCode}'),
                              fit: VideoViewFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Top header: Expand icon & Timer badge
                  Positioned(
                    top: 6,
                    left: 6,
                    right: 6,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            callManager.formattedDuration,
                            style: const TextStyle(color: AppTheme.mint, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.fullscreen, color: Colors.white, size: 14),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Controls Capsule
                  Positioned(
                    bottom: 6,
                    left: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Mute toggle
                          GestureDetector(
                            onTap: () => callManager.toggleMute(),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: callManager.isMuted ? Colors.redAccent : Colors.white12,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                callManager.isMuted ? Icons.mic_off : Icons.mic,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),

                          // Speaker toggle
                          GestureDetector(
                            onTap: () => callManager.toggleSpeaker(),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: callManager.isSpeakerOn ? AppTheme.mint.withValues(alpha: 0.25) : Colors.white12,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                callManager.isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                                color: callManager.isSpeakerOn ? AppTheme.mint : Colors.white,
                                size: 14,
                              ),
                            ),
                          ),

                          // End Call
                          GestureDetector(
                            onTap: () => callManager.endCall(),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: AppTheme.callRed,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.call_end,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
