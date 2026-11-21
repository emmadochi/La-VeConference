import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/active_call_manager.dart';
import '../theme/app_theme.dart';

class ActiveCallTopBanner extends StatefulWidget {
  const ActiveCallTopBanner({super.key});

  @override
  State<ActiveCallTopBanner> createState() => _ActiveCallTopBannerState();
}

class _ActiveCallTopBannerState extends State<ActiveCallTopBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callManager = ActiveCallManager.instance;
    if (!callManager.hasActiveCall || !callManager.isMinimized) {
      return const SizedBox.shrink();
    }

    final topPadding = MediaQuery.of(context).padding.top;
    final isVideo = callManager.isVideo;

    return Positioned(
      top: math.max(topPadding + 4, 10),
      left: 12,
      right: 12,
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          onTap: () => callManager.maximize(),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0F2D24),
                  Color(0xFF143B2F),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppTheme.mint.withValues(alpha: 0.45),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
                BoxShadow(
                  color: AppTheme.mint.withValues(alpha: 0.15),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                // Pulsing Green Live Dot
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, _) {
                    return Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.mint.withValues(alpha: _pulseAnimation.value),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.mint.withValues(alpha: _pulseAnimation.value * 0.8),
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // Call type icon
                Icon(
                  isVideo ? Icons.videocam_rounded : Icons.phone_in_talk_rounded,
                  color: AppTheme.mint,
                  size: 18,
                ),
                const SizedBox(width: 8),

                // Name & Duration
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        callManager.peerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Text(
                        '${callManager.formattedDuration} • Tap to return',
                        style: TextStyle(
                          color: AppTheme.mint.withValues(alpha: 0.85),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Quick Speaker/Earpiece Switch
                GestureDetector(
                  onTap: () => callManager.toggleSpeaker(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: callManager.isSpeakerOn
                          ? AppTheme.mint.withValues(alpha: 0.2)
                          : Colors.white10,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      callManager.isSpeakerOn ? Icons.volume_up_rounded : Icons.phone_android_rounded,
                      color: callManager.isSpeakerOn ? AppTheme.mint : Colors.white70,
                      size: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Quick Mute Switch
                GestureDetector(
                  onTap: () => callManager.toggleMute(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: callManager.isMuted
                          ? Colors.redAccent.withValues(alpha: 0.25)
                          : Colors.white10,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      callManager.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: callManager.isMuted ? Colors.redAccent : Colors.white70,
                      size: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // End Call Button
                GestureDetector(
                  onTap: () => callManager.endCall(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppTheme.callRed,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call_end_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
