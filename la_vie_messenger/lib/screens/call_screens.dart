import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/call_signaling_service.dart';
import '../services/contact_service.dart';
import '../services/ringtone_service.dart';
import '../services/active_call_manager.dart';
import '../services/media_storage_service.dart';

// ==========================================
// 1. OUTGOING CALL SCREEN
// ==========================================
class OutgoingCallScreen extends StatefulWidget {
  final String callId;
  final String peerName;
  final String? peerAvatar;
  final bool isVideo;

  const OutgoingCallScreen({
    Key? key,
    required this.callId,
    required this.peerName,
    this.peerAvatar,
    required this.isVideo,
  }) : super(key: key);

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;
  Timer? _timeoutTimer;
  Timer? _connectingTimer;
  String _statusText = 'Calling...';
  bool _isPopped = false;

  void _safePop() {
    if (_isPopped) return;
    _isPopped = true;
    _connectingTimer?.cancel();
    _connectingTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _callSubscription?.cancel();
    _callSubscription = null;
    RingtoneService.instance.stop();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      CallSignalingService.getOrFetchToken(
        roomName: 'call_${widget.callId}',
        userId: user.uid,
        userName: user.displayName ?? 'User',
      );
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Start outgoing dial tone for the caller
    RingtoneService.instance.startOutgoingRing();

    _connectingTimer = Timer(const Duration(seconds: 22), () {
      if (mounted && _statusText == 'Calling...' && !_isPopped) {
        CallSignalingService.markOffline(widget.callId);
        RingtoneService.instance.stop();
        setState(() => _statusText = 'User is Offline or Unavailable');
        Future.delayed(const Duration(milliseconds: 2000), () {
          _safePop();
        });
      }
    });

    _timeoutTimer = Timer(const Duration(seconds: 45), () {
      if (_isPopped) return;
      CallSignalingService.markMissed(widget.callId);
      RingtoneService.instance.stop();
      if (mounted) {
        setState(() => _statusText = 'No Answer');
        Future.delayed(const Duration(seconds: 2), () {
          _safePop();
        });
      }
    });

    _callSubscription = CallSignalingService.streamCall(widget.callId).listen((snapshot) async {
      if (!snapshot.exists || _isPopped) return;
      final data = snapshot.data();
      if (data == null) return;
      final status = data['status'] as String?;

      if (status == 'ringing') {
        _connectingTimer?.cancel();
        _connectingTimer = null;
        if (mounted && _statusText != 'Ringing...') {
          setState(() => _statusText = 'Ringing...');
        }
      } else if (status == 'offline') {
        _connectingTimer?.cancel();
        _timeoutTimer?.cancel();
        await RingtoneService.instance.stop();
        if (mounted) {
          setState(() => _statusText = 'User is currently Offline');
          Future.delayed(const Duration(milliseconds: 2000), () {
            _safePop();
          });
        }
      } else if (status == 'accepted') {
        _connectingTimer?.cancel();
        _connectingTimer = null;
        _timeoutTimer?.cancel();
        _isPopped = true;
        _callSubscription?.cancel();
        await RingtoneService.instance.stop();
        await Future.delayed(const Duration(milliseconds: 150));
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ActiveCallScreen(
                callId: widget.callId,
                roomName: data['roomName'] ?? 'call_${widget.callId}',
                isVideo: widget.isVideo,
                peerName: widget.peerName,
              ),
            ),
          );
        }
      } else if (status == 'declined' || status == 'ended') {
        _connectingTimer?.cancel();
        _timeoutTimer?.cancel();
        RingtoneService.instance.stop();
        if (mounted) {
          setState(() => _statusText = status == 'declined' ? 'Call Declined' : 'Call Ended');
          Future.delayed(const Duration(milliseconds: 500), () {
            _safePop();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _isPopped = true;
    RingtoneService.instance.stop();
    _pulseController.dispose();
    _callSubscription?.cancel();
    _connectingTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  bool _isMuted = false;

  void _cancelCall() {
    CallSignalingService.endCall(widget.callId);
    _safePop();
  }

  Widget _buildDockActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isActive = false,
    Color? activeColor,
    Color? iconColor,
  }) {
    final mint = AppTheme.mint;
    final color = activeColor ?? mint;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? color.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: isActive ? color.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.12),
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            color: iconColor ?? (isActive ? color : Colors.white),
            size: 22,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mint = AppTheme.mint;

    return Scaffold(
      backgroundColor: const Color(0xFF090714),
      body: Stack(
        children: [
          // 1. Atmospheric Ambient Radial Background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.25),
                  radius: 1.3,
                  colors: [
                    Color(0xFF261D4C),
                    Color(0xFF140F2D),
                    Color(0xFF0A0717),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // 2. Top Window Controls & End-to-End Encryption Banner
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 28),
                        tooltip: 'Minimize Call',
                        onPressed: _cancelCall,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded, size: 13, color: mint),
                            const SizedBox(width: 6),
                            const Text(
                              'End-to-End Encrypted',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48), // Balancing width for centered banner
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                // 3. Caller Details (Name & Status Badge)
                Text(
                  widget.peerName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: mint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: mint.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isVideo ? Icons.videocam_rounded : Icons.phone_in_talk_rounded,
                        size: 14,
                        color: mint,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.isVideo ? 'LiChat Video Call • $_statusText' : 'LiChat Voice Call • $_statusText',
                        style: TextStyle(color: mint, fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // 4. Center Caller Avatar with Concentric Pulse Waves
                Center(
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final val = _pulseController.value;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer Pulse Wave
                          Container(
                            width: 170 + (65 * val),
                            height: 170 + (65 * val),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: mint.withValues(alpha: 0.25 * (1.0 - val)),
                                width: 2,
                              ),
                            ),
                          ),
                          // Inner Pulse Glow
                          Container(
                            width: 155 + (35 * val),
                            height: 155 + (35 * val),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: mint.withValues(alpha: 0.45 * (1.0 - val)),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: mint.withValues(alpha: 0.22 * (1.0 - val)),
                                  blurRadius: 28 * val,
                                  spreadRadius: 10 * val,
                                ),
                              ],
                            ),
                          ),
                          // Main Avatar Circle
                          Container(
                            width: 146,
                            height: 146,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: mint.withValues(alpha: 0.85), width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 70,
                              backgroundColor: const Color(0xFF1E1A36),
                              backgroundImage: MediaStorageService.getAvatarProvider(widget.peerAvatar),
                              child: (widget.peerAvatar == null || widget.peerAvatar!.isEmpty)
                                  ? Text(
                                      widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : 'U',
                                      style: TextStyle(color: mint, fontSize: 52, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const Spacer(flex: 3),

                // 5. Desktop-Grade Floating Call Control Dock
                Container(
                  constraints: const BoxConstraints(maxWidth: 380),
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16122C).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Mic Mute Toggle
                      _buildDockActionButton(
                        icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        tooltip: _isMuted ? 'Unmute Mic' : 'Mute Mic',
                        isActive: _isMuted,
                        activeColor: Colors.redAccent,
                        onTap: () {
                          setState(() => _isMuted = !_isMuted);
                        },
                      ),

                      // Camera / Video Mode
                      _buildDockActionButton(
                        icon: widget.isVideo ? Icons.videocam_rounded : Icons.videocam_outlined,
                        tooltip: widget.isVideo ? 'Video Enabled' : 'Voice Mode',
                        isActive: widget.isVideo,
                        onTap: () {},
                      ),

                      // Audio / Speaker Selector
                      _buildDockActionButton(
                        icon: Icons.volume_up_rounded,
                        tooltip: 'Speaker Output',
                        onTap: () {},
                      ),

                      // End Call / Cancel Button
                      Tooltip(
                        message: 'Cancel Call',
                        child: GestureDetector(
                          onTap: _cancelCall,
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: AppTheme.callRed,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.callRed.withValues(alpha: 0.55),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. INCOMING CALL FULL-SCREEN & DIALOG
// ==========================================
class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String callerName;
  final String? callerAvatar;
  final bool isVideo;
  final String? roomName;
  final bool isGroup;
  final String? groupName;

  const IncomingCallScreen({
    Key? key,
    required this.callId,
    required this.callerName,
    this.callerAvatar,
    required this.isVideo,
    this.roomName,
    this.isGroup = false,
    this.groupName,
  }) : super(key: key);

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  bool _isActionTaken = false;

  @override
  void initState() {
    super.initState();
    CallSignalingService.markRinging(widget.callId);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    final user = FirebaseAuth.instance.currentUser;
    final targetRoom = widget.roomName ?? 'call_${widget.callId}';
    if (user != null) {
      CallSignalingService.getOrFetchToken(
        roomName: targetRoom,
        userId: user.uid,
        userName: user.displayName ?? 'User',
      );
    }

    RingtoneService.instance.startIncomingRing();

    _callSub = CallSignalingService.streamCall(widget.callId).listen((snap) {
      if (!snap.exists) return;
      final status = snap.data()?['status'];
      if (status == 'ended' || status == 'missed' || status == 'declined') {
        _finishAndClose();
      }
    });
  }

  void _finishAndClose() {
    if (_isActionTaken) return;
    _isActionTaken = true;
    RingtoneService.instance.stop();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    RingtoneService.instance.stop();
    _pulseController.dispose();
    _callSub?.cancel();
    super.dispose();
  }

  void _accept() async {
    if (_isActionTaken) return;
    _isActionTaken = true;
    await RingtoneService.instance.stop();
    await Future.delayed(const Duration(milliseconds: 150));
    RingtoneService.instance.triggerHapticPulse(durationMs: 50);
    await CallSignalingService.acceptCall(widget.callId);
    final targetRoom = widget.roomName ?? 'call_${widget.callId}';
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ActiveCallScreen(
            callId: widget.callId,
            roomName: targetRoom,
            isVideo: widget.isVideo,
            peerName: widget.callerName,
          ),
        ),
      );
    }
  }

  void _decline() async {
    if (_isActionTaken) return;
    _isActionTaken = true;
    RingtoneService.instance.stop();
    RingtoneService.instance.triggerHapticPulse(durationMs: 35);
    await CallSignalingService.declineCall(widget.callId);
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mint = AppTheme.mint;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0A17),
      body: Stack(
        children: [
          // Background Atmospheric Radial Ambient Glow
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.35),
                  radius: 1.1,
                  colors: [
                    Color(0xFF261A4D),
                    Color(0xFF130E26),
                    Color(0xFF0C0A17),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 36),

                // Call Type Pill Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: (widget.isGroup ? AppTheme.primaryAccent(context) : mint).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: (widget.isGroup ? AppTheme.primaryAccent(context) : mint).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isGroup
                            ? Icons.groups_rounded
                            : (widget.isVideo ? Icons.videocam_rounded : Icons.phone_in_talk_rounded),
                        color: widget.isGroup ? AppTheme.primaryAccent(context) : mint,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.isGroup
                            ? (widget.isVideo ? 'LiChat Group Video Call 👥' : 'LiChat Group Voice Call 👥')
                            : (widget.isVideo ? 'LiChat HD Video Call' : 'LiChat HD Voice Call'),
                        style: TextStyle(
                          color: widget.isGroup ? AppTheme.primaryAccent(context) : mint,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Main Title (Group Name if group call, or Caller Name if 1-on-1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    (widget.isGroup && widget.groupName != null && widget.groupName!.isNotEmpty)
                        ? widget.groupName!
                        : widget.callerName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Status Subtitle (Attribution to caller if group call)
                Text(
                  (widget.isGroup && widget.groupName != null && widget.groupName!.isNotEmpty)
                      ? '${widget.callerName} is calling the group...'
                      : 'Incoming Call...',
                  style: TextStyle(
                    color: widget.isGroup ? mint : const Color(0xFFB3ABD0),
                    fontSize: 15,
                    fontWeight: widget.isGroup ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),

                const Spacer(),

                // Central Caller Avatar with Breathing Pulse Waves
                Center(
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final val = _pulseController.value;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulse Ring 2 (Outer)
                          Container(
                            width: 170 + (70 * val),
                            height: 170 + (70 * val),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: mint.withValues(alpha: 0.25 * (1.0 - val)),
                                width: 2,
                              ),
                            ),
                          ),
                          // Pulse Ring 1 (Inner)
                          Container(
                            width: 150 + (40 * val),
                            height: 150 + (40 * val),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: mint.withValues(alpha: 0.45 * (1.0 - val)),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: mint.withValues(alpha: 0.25 * (1.0 - val)),
                                  blurRadius: 30 * val,
                                  spreadRadius: 10 * val,
                                ),
                              ],
                            ),
                          ),
                          // Main Avatar Circle
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: mint.withValues(alpha: 0.8), width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 68,
                              backgroundColor: const Color(0xFF1E1A36),
                              backgroundImage: MediaStorageService.getAvatarProvider(widget.callerAvatar),
                              child: (widget.callerAvatar == null || widget.callerAvatar!.isEmpty)
                                  ? Text(
                                      widget.callerName.isNotEmpty ? widget.callerName[0].toUpperCase() : 'U',
                                      style: TextStyle(color: mint, fontSize: 52, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const Spacer(),

                // Bottom Call Controls (Decline & Accept)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 1. Decline Action Button
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: _decline,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: AppTheme.callRed,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.callRed.withValues(alpha: 0.5),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 34),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Decline',
                            style: TextStyle(
                              color: Color(0xFFB3ABD0),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),

                      // 2. Accept Action Button
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: _accept,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: AppTheme.callGreen,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.callGreen.withValues(alpha: 0.55),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Icon(
                                widget.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Accept',
                            style: TextStyle(
                              color: Color(0xFFB3ABD0),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Backwards compatibility wrapper for IncomingCallDialog
class IncomingCallDialog extends StatelessWidget {
  final String callId;
  final String callerName;
  final String? callerAvatar;
  final bool isVideo;
  final String? roomName;

  const IncomingCallDialog({
    Key? key,
    required this.callId,
    required this.callerName,
    this.callerAvatar,
    required this.isVideo,
    this.roomName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IncomingCallScreen(
      callId: callId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      isVideo: isVideo,
      roomName: roomName,
    );
  }
}

// ==========================================
// 3. ACTIVE CALL SCREEN (MULTI-CALL GRID & PIP)
// ==========================================
class ActiveCallScreen extends StatefulWidget {
  final String callId;
  final String roomName;
  final bool isVideo;
  final String peerName;

  const ActiveCallScreen({
    Key? key,
    required this.callId,
    required this.roomName,
    required this.isVideo,
    required this.peerName,
  }) : super(key: key);

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _CallTileData {
  final String id;
  final String name;
  final VideoTrack? track;
  final bool isLocal;
  final bool isMuted;
  final ConnectionQuality connectionQuality;

  _CallTileData({
    required this.id,
    required this.name,
    this.track,
    this.isLocal = false,
    this.isMuted = false,
    this.connectionQuality = ConnectionQuality.excellent,
  });
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  final ActiveCallManager _callManager = ActiveCallManager.instance;
  bool _callEverStarted = false;
  bool _isEnding = false;
  int _unreadChatCount = 0;
  bool _isChatSheetOpen = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _inCallChatSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _videoUpgradeSub;
  bool _showingUpgradePrompt = false;

  @override
  void initState() {
    super.initState();
    _callManager.addListener(_onManagerUpdate);

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    _inCallChatSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .collection('messages')
        .snapshots()
        .listen((snap) {
      if (!_isChatSheetOpen && snap.docChanges.isNotEmpty) {
        for (final change in snap.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data != null && data['senderId'] != myUid && mounted) {
              setState(() => _unreadChatCount++);
            }
          }
        }
      }
    });

    // Listen for mid-call video upgrade requests (WhatsApp-style switch from audio to video)
    _videoUpgradeSub = CallSignalingService.streamCall(widget.callId).listen((doc) {
      if (!doc.exists || !mounted) return;
      final data = doc.data();
      if (data == null) return;
      final upgrade = data['videoUpgrade'] as Map<String, dynamic>?;
      if (upgrade == null) return;

      final status = upgrade['status'] as String?;
      final requesterId = upgrade['requesterId'] as String?;
      final requesterName = upgrade['requesterName'] as String? ?? 'Peer';

      if (status == 'pending' && requesterId != myUid && !_showingUpgradePrompt) {
        _showVideoUpgradePrompt(requesterName);
      } else if (status == 'accepted' && requesterId == myUid) {
        _callManager.enableVideo();
        CallSignalingService.clearVideoUpgrade(widget.callId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$requesterName accepted the video call request!'),
            backgroundColor: AppTheme.mintDark,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (status == 'declined' && requesterId == myUid) {
        CallSignalingService.clearVideoUpgrade(widget.callId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$requesterName declined to switch to video'),
            backgroundColor: Colors.redAccent.shade700,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    if (_callManager.hasActiveCall && _callManager.callId == widget.callId) {
      // Already connected to this exact call (e.g. returning from minimised state)
      _callEverStarted = true;
      _callManager.unminimize();
    } else if (!_callManager.hasActiveCall || _callManager.callId != widget.callId) {
      _callManager.connect(
        callId: widget.callId,
        roomName: widget.roomName,
        isVideo: widget.isVideo,
        peerName: widget.peerName,
      );
    }
  }

  @override
  void dispose() {
    _videoUpgradeSub?.cancel();
    _inCallChatSub?.cancel();
    _callManager.removeListener(_onManagerUpdate);
    super.dispose();
  }

  void _onManagerUpdate() {
    if (!mounted || _isEnding) return;
    if (_callManager.hasActiveCall || _callManager.isConnecting) {
      _callEverStarted = true;
    } else if (_callEverStarted &&
        !_callManager.hasActiveCall &&
        !_callManager.isConnecting &&
        _callManager.errorMessage == null) {
      // Auto-save recording if ready before popping
      final recFile = _callManager.recordingFileName;
      final recUrl = _callManager.recordingUrl;
      final cId = _callManager.callId;
      if (recFile != null && recUrl != null) {
        MediaStorageService.saveCallRecordingToPhone(
          remoteUrl: recUrl,
          fileName: recFile,
          callId: cId,
        );
      }

      // Remote call has ended — pop immediately to cleanly restore the desktop layout
      _isEnding = true;
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }
    if (mounted) setState(() {});
  }

  void _minimizeCall() {
    if (_isEnding) return;
    _isEnding = true;
    _callManager.minimize();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
  }

  void _endCall() {
    if (_isEnding) return;
    _isEnding = true;
    final recFile = _callManager.recordingFileName;
    final recUrl = _callManager.recordingUrl;
    final cId = _callManager.callId;

    // Pop call screen immediately so the app transitions cleanly back to desktop UI
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }

    _callManager.endCall().then((_) {
      if (recFile != null && recUrl != null) {
        MediaStorageService.saveCallRecordingToPhone(
          remoteUrl: recUrl,
          fileName: recFile,
          callId: cId,
        );
      }
    });
  }

  void _showVideoUpgradePrompt(String requesterName) {
    _showingUpgradePrompt = true;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: const Color(0xFF141126),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppTheme.mint.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.videocam_rounded, color: AppTheme.mint, size: 30),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Switch to video call?',
                  style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '$requesterName is requesting to switch to a video call. Your camera will turn on once accepted.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          CallSignalingService.respondVideoUpgrade(
                            callId: widget.callId,
                            accept: false,
                          );
                        },
                        child: const Text('Don\'t switch', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.mint,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          CallSignalingService.respondVideoUpgrade(
                            callId: widget.callId,
                            accept: true,
                          );
                          _callManager.enableVideo();
                        },
                        child: const Text('Switch', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      _showingUpgradePrompt = false;
    });
  }

  void _showAudioOutputSelectorSheet() {
    _callManager.refreshAvailableAudioDevices();
    final current = _callManager.currentAudioOutput;
    final mint = AppTheme.mint;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141126),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: mint.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.volume_up_rounded, color: mint, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Audio Routing',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Select speaker, earpiece, or wireless headset',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildAudioRouteOption(
                  title: 'Loudspeaker',
                  subtitle: 'Hands-free speakerphone',
                  icon: Icons.volume_up_rounded,
                  isSelected: current == AudioOutputDevice.speaker,
                  onTap: () {
                    _callManager.setAudioOutput(AudioOutputDevice.speaker);
                    RingtoneService.instance.triggerHapticPulse(durationMs: 30);
                    Navigator.pop(sheetCtx);
                  },
                ),
                const SizedBox(height: 10),
                _buildAudioRouteOption(
                  title: 'Phone Earpiece',
                  subtitle: 'Private audio held to ear',
                  icon: Icons.phone_iphone_rounded,
                  isSelected: current == AudioOutputDevice.earpiece,
                  onTap: () {
                    _callManager.setAudioOutput(AudioOutputDevice.earpiece);
                    RingtoneService.instance.triggerHapticPulse(durationMs: 30);
                    Navigator.pop(sheetCtx);
                  },
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (context) {
                    Map<String, dynamic>? btDevice;
                    for (final d in _callManager.availableAudioDevices) {
                      if (d['type'] == 'bluetooth') {
                        btDevice = d;
                        break;
                      }
                    }
                    final btName = btDevice?['name'] as String? ?? 'Bluetooth Headset';
                    final isConnected = btDevice != null && btDevice['available'] == true;

                    return _buildAudioRouteOption(
                      title: btName,
                      subtitle: isConnected ? 'Connected wireless device' : 'Bluetooth or wired earphones',
                      icon: Icons.bluetooth_audio_rounded,
                      isSelected: current == AudioOutputDevice.bluetooth,
                      badgeText: isConnected ? 'Connected' : null,
                      onTap: () {
                        _callManager.setAudioOutput(AudioOutputDevice.bluetooth);
                        RingtoneService.instance.triggerHapticPulse(durationMs: 30);
                        Navigator.pop(sheetCtx);
                      },
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAudioRouteOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    String? badgeText,
  }) {
    final mint = AppTheme.mint;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? mint.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? mint.withValues(alpha: 0.6) : Colors.white10,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? mint.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? mint : Colors.white70,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (badgeText != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: mint.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeText,
                            style: const TextStyle(color: AppTheme.mint, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppTheme.mint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 14, color: Colors.black),
              ),
          ],
        ),
      ),
    );
  }

  void _showNetworkHealthSheet() {
    final room = _callManager.room;
    final localQuality = _callManager.localConnectionQuality;
    final isReconnecting = _callManager.isReconnecting;
    final mint = AppTheme.mint;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141126),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
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
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (isReconnecting || localQuality == ConnectionQuality.poor)
                                ? Colors.redAccent.withValues(alpha: 0.15)
                                : mint.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isReconnecting
                                ? Icons.sync_problem_rounded
                                : Icons.network_check_rounded,
                            color: (isReconnecting || localQuality == ConnectionQuality.poor)
                                ? Colors.redAccent
                                : mint,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Call Network Diagnostics',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isReconnecting
                                  ? 'Reconnecting to LiveKit server...'
                                  : 'Real-time WebRTC audio & video quality',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                      onPressed: () => Navigator.pop(sheetCtx),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      _buildDiagRow(
                        label: 'Your Uplink (Mic & Camera)',
                        quality: localQuality,
                        isReconnecting: isReconnecting,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(color: Colors.white10, height: 1),
                      ),
                      if (room != null && room.remoteParticipants.isNotEmpty)
                        ...room.remoteParticipants.values.map((p) {
                          final name = p.name.isNotEmpty ? p.name : (p.identity.isNotEmpty ? p.identity : 'Peer');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _buildDiagRow(
                              label: '$name (Downlink)',
                              quality: p.connectionQuality,
                              isReconnecting: false,
                            ),
                          );
                        })
                      else
                        _buildDiagRow(
                          label: 'Remote Peer Downlink',
                          quality: ConnectionQuality.good,
                          isReconnecting: false,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Data Saver Mode Switch (WhatsApp style Low Data Usage for Calls)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: StatefulBuilder(
                    builder: (context, setSheetState) {
                      return Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _callManager.isDataSaver
                                  ? mint.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.06),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.data_saver_on_rounded,
                              color: _callManager.isDataSaver ? mint : Colors.white60,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Low Data Usage',
                                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _callManager.isDataSaver
                                      ? 'Active: Conserving cellular data & bandwidth'
                                      : 'Use less data for audio and video calls',
                                  style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _callManager.isDataSaver,
                            activeColor: mint,
                            onChanged: (val) {
                              _callManager.toggleDataSaver();
                              setSheetState(() {});
                              RingtoneService.instance.triggerHapticPulse(durationMs: 30);
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1633),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: mint.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tips_and_updates_outlined, color: mint, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.isVideo && !_callManager.isVideoOff
                              ? 'Tip: If connection is poor, turning video off saves ~80% network data.'
                              : 'Tip: Audio stream uses adaptive Opus Speech encoding with auto-gain.',
                          style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDiagRow({
    required String label,
    required ConnectionQuality quality,
    required bool isReconnecting,
  }) {
    Color statusColor;
    String statusText;
    int barCount;

    if (isReconnecting) {
      statusColor = Colors.amberAccent;
      statusText = 'Reconnecting';
      barCount = 1;
    } else {
      switch (quality) {
        case ConnectionQuality.excellent:
          statusColor = AppTheme.mint;
          statusText = 'Excellent (HD)';
          barCount = 4;
          break;
        case ConnectionQuality.good:
          statusColor = const Color(0xFF4ADE80);
          statusText = 'Good';
          barCount = 3;
          break;
        case ConnectionQuality.poor:
          statusColor = Colors.orangeAccent;
          statusText = 'Poor Connection';
          barCount = 2;
          break;
        case ConnectionQuality.lost:
          statusColor = Colors.redAccent;
          statusText = 'Signal Lost';
          barCount = 0;
          break;
        default:
          statusColor = AppTheme.mint;
          statusText = 'Healthy';
          barCount = 3;
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(4, (i) {
                final height = 5.0 + (i * 3.0);
                final isActive = i < barCount;
                return Container(
                  width: 3,
                  height: height,
                  margin: const EdgeInsets.symmetric(horizontal: 1.2),
                  decoration: BoxDecoration(
                    color: isActive ? statusColor : Colors.white24,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                );
              }),
            ),
            const SizedBox(width: 8),
            Text(
              statusText,
              style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNetworkQualityBadge() {
    final localQuality = _callManager.localConnectionQuality;
    final isReconnecting = _callManager.isReconnecting;

    Color badgeColor;
    String label;
    IconData icon;

    if (isReconnecting) {
      badgeColor = Colors.amberAccent;
      label = 'Reconnecting';
      icon = Icons.sync;
    } else {
      switch (localQuality) {
        case ConnectionQuality.excellent:
          badgeColor = AppTheme.mint;
          label = 'HD';
          icon = Icons.wifi_rounded;
          break;
        case ConnectionQuality.good:
          badgeColor = const Color(0xFF4ADE80);
          label = 'Good';
          icon = Icons.wifi_rounded;
          break;
        case ConnectionQuality.poor:
          badgeColor = Colors.orangeAccent;
          label = 'Weak';
          icon = Icons.network_check_rounded;
          break;
        case ConnectionQuality.lost:
          badgeColor = Colors.redAccent;
          label = 'Lost';
          icon = Icons.wifi_off_rounded;
          break;
        default:
          badgeColor = AppTheme.mint;
          label = 'HD';
          icon = Icons.wifi_rounded;
      }
    }

    return GestureDetector(
      onTap: _showNetworkHealthSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: badgeColor, size: 12),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: badgeColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddParticipantSheet() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.person_add_rounded, color: AppTheme.mint, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Add Participant to Call',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.border),
              SizedBox(
                height: 280,
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: ContactService.streamContacts(user.uid),
                  builder: (context, snap) {
                    final contacts = snap.data ?? [];
                    if (contacts.isEmpty) {
                      return const Center(
                        child: Text('No paired contacts available to add', style: TextStyle(color: AppTheme.textMuted)),
                      );
                    }

                    return ListView.builder(
                      itemCount: contacts.length,
                      itemBuilder: (context, idx) {
                        final c = contacts[idx];
                        final name = c['name'] ?? 'Contact';
                        final uid = c['uid'] ?? '';
                        final avatar = c['avatar'] as String?;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.surfaceElevated,
                            backgroundImage: MediaStorageService.getAvatarProvider(avatar),
                            child: (avatar == null || avatar.isEmpty)
                                ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: AppTheme.mint))
                                : null,
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          trailing: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.mint,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.add_call, size: 14),
                            label: const Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              Navigator.pop(sheetCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Inviting $name to the call...'),
                                  backgroundColor: AppTheme.mintDark,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                              await CallSignalingService.inviteToActiveCall(
                                roomName: widget.roomName,
                                inviterId: user.uid,
                                inviterName: user.displayName ?? 'User',
                                inviterAvatar: user.photoURL,
                                contactUid: uid,
                                contactName: name,
                                contactAvatar: avatar,
                                isVideo: widget.isVideo,
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showInCallChatSheet() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final textController = TextEditingController();

    setState(() {
      _isChatSheetOpen = true;
      _unreadChatCount = 0;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141124),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(sheetCtx).size.height * 0.65,
            child: Column(
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.mint, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'In-Call Messages',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12),

                // Message List Stream
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('calls')
                        .doc(widget.callId)
                        .collection('messages')
                        .orderBy('createdAt', descending: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: AppTheme.mint));
                      }
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mark_chat_read_outlined,
                                  size: 40, color: Colors.white.withValues(alpha: 0.3)),
                              const SizedBox(height: 8),
                              const Text(
                                'No messages yet in this call',
                                style: TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: docs.length,
                        itemBuilder: (context, idx) {
                          final msg = docs[idx].data();
                          final isMe = msg['senderId'] == user.uid;
                          final senderName = msg['senderName'] ?? 'User';
                          final text = msg['text'] ?? '';
                          final created = (msg['createdAt'] as Timestamp?)?.toDate();
                          final timeStr = created != null ? DateFormat('h:mm a').format(created) : '';

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? AppTheme.bubbleMe
                                    : const Color(0xFF231E3D),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  if (!isMe)
                                    Text(
                                      senderName,
                                      style: const TextStyle(
                                        color: AppTheme.mint,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  Text(
                                    text,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                // Text input row
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: TextField(
                            controller: textController,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            cursorColor: AppTheme.mint,
                            decoration: const InputDecoration(
                              hintText: 'Type message in call...',
                              hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (val) {
                              _sendInCallMessage(val.trim(), textController);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: AppTheme.mint,
                        child: IconButton(
                          icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                          onPressed: () {
                            _sendInCallMessage(textController.text.trim(), textController);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) {
        setState(() => _isChatSheetOpen = false);
      }
    });
  }

  void _sendInCallMessage(String text, TextEditingController controller) async {
    if (text.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    controller.clear();

    await FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .collection('messages')
        .add({
      'senderId': user.uid,
      'senderName': user.displayName ?? 'User',
      'senderAvatar': user.photoURL ?? '',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Builds non-overlapping video grid for all participants
  Widget _buildNonOverlappingGrid(List<_CallTileData> tiles) {
    if (tiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 54,
              backgroundColor: AppTheme.surfaceElevated,
              child: Text(
                widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : 'U',
                style: const TextStyle(color: AppTheme.mint, fontSize: 38, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.peerName,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _callManager.errorMessage != null
                  ? 'Connection notice: ${_callManager.errorMessage}'
                  : (_callManager.isConnecting
                      ? 'Connecting LiveKit stream...'
                      : '${_callManager.formattedDuration} • Connected'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _callManager.errorMessage != null ? Colors.orangeAccent : AppTheme.mint,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (tiles.length == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: _buildTile(tiles[0]),
      );
    }

    if (tiles.length == 2) {
      return Column(
        children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _buildTile(tiles[0]))),
          Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _buildTile(tiles[1]))),
        ],
      );
    }

    if (tiles.length == 3) {
      return Column(
        children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _buildTile(tiles[0]))),
          Expanded(
            child: Row(
              children: [
                Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _buildTile(tiles[1]))),
                Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _buildTile(tiles[2]))),
              ],
            ),
          ),
        ],
      );
    }

    if (tiles.length == 4) {
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _buildTile(tiles[0]))),
                Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _buildTile(tiles[1]))),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _buildTile(tiles[2]))),
                Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _buildTile(tiles[3]))),
              ],
            ),
          ),
        ],
      );
    }

    // 5+ Participants: 2-column scrollable grid
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, idx) => _buildTile(tiles[idx]),
    );
  }

  Widget _buildTile(_CallTileData tile) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (tile.track != null && !tile.track!.isDisposed)
            Transform.scale(
              scaleX: (tile.isLocal && _callManager.isFrontCamera) ? -1 : 1,
              child: VideoTrackRenderer(
                tile.track!,
                key: ValueKey('track_${tile.id}_${tile.track?.sid ?? tile.track.hashCode}'),
                fit: VideoViewFit.cover,
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.surfaceElevated, Color(0xFF0C2420)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: AppTheme.mint.withValues(alpha: 0.2),
                      child: Text(
                        tile.name.isNotEmpty ? tile.name[0].toUpperCase() : 'U',
                        style: const TextStyle(color: AppTheme.mint, fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

          // Network Quality Indicator
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                tile.connectionQuality == ConnectionQuality.poor
                    ? Icons.network_check_rounded
                    : Icons.wifi_rounded,
                size: 13,
                color: tile.connectionQuality == ConnectionQuality.poor
                    ? Colors.redAccent
                    : (tile.connectionQuality == ConnectionQuality.good
                        ? Colors.amberAccent
                        : AppTheme.callGreen),
              ),
            ),
          ),

          // Name & Mute status badge
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tile.isMuted) ...[
                    const Icon(Icons.mic_off_rounded, color: Colors.redAccent, size: 12),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    tile.isLocal ? 'You' : tile.name,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),

          // Flip camera button for local frame
          if (tile.isLocal && tile.track != null)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: _callManager.switchCamera,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.flip_camera_ios_rounded, color: AppTheme.mint, size: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isEnding || !_callManager.hasActiveCall) {
      return const Scaffold(
        backgroundColor: Color(0xFF090714),
        body: SizedBox.shrink(),
      );
    }

    final room = _callManager.room;
    final remoteParticipants = room?.remoteParticipants.values.toList() ?? [];

    // Collect all participant tiles
    final List<_CallTileData> tiles = [];

    // 1. Remote participants
    for (final p in remoteParticipants) {
      final pName = p.name.isNotEmpty ? p.name : (p.identity.isNotEmpty ? p.identity : 'User');
      VideoTrack? pTrack;
      VideoTrack? pScreenTrack;

      for (final pub in p.videoTrackPublications) {
        if (pub.track != null && !pub.muted) {
          if (pub.source == TrackSource.screenShareVideo) {
            pScreenTrack = pub.track as VideoTrack?;
          } else {
            pTrack = pub.track as VideoTrack?;
          }
        }
      }

      tiles.add(_CallTileData(
        id: p.identity,
        name: pName,
        track: pTrack,
        isMuted: p.audioTrackPublications.any((pub) => pub.muted),
        connectionQuality: p.connectionQuality,
      ));

      if (pScreenTrack != null) {
        tiles.insert(0, _CallTileData(
          id: '${p.identity}_screen',
          name: "$pName (Screen)",
          track: pScreenTrack,
          isMuted: false,
          connectionQuality: p.connectionQuality,
        ));
      }
    }

    // 2. Local participant
    final localTrack = _callManager.getLocalVideoTrack();
    final localUser = FirebaseAuth.instance.currentUser;
    final localName = localUser?.displayName ?? 'You';

    if (localTrack != null || !_callManager.isVideoOff) {
      tiles.add(_CallTileData(
        id: 'local',
        name: localName,
        track: localTrack,
        isLocal: true,
        isMuted: _callManager.isMuted,
        connectionQuality: room?.localParticipant?.connectionQuality ?? ConnectionQuality.excellent,
      ));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isEnding) {
          _minimizeCall();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Stack(
            children: [
              // 1. MAIN NON-OVERLAPPING VIDEO GRID
              Positioned.fill(
                top: 60,
                bottom: 95,
                child: _buildNonOverlappingGrid(tiles),
              ),

              // 2. TOP APP BAR / HEADER (Back to minimize, Encryption & PiP button)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Minimize / Back button
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
                        tooltip: 'Minimize call',
                        onPressed: _minimizeCall,
                      ),

                      // Call Header Badge & Recording Indicator
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_outline, color: AppTheme.mint, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  '${remoteParticipants.length + 1} in Call • ${_callManager.formattedDuration}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildNetworkQualityBadge(),
                          if (_callManager.isRecording) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.redAccent, width: 1.2),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 10),
                                  SizedBox(width: 4),
                                  Text(
                                    'REC',
                                    style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),

                      // Picture-in-Picture trigger (only for video calls)
                      if (widget.isVideo && !_callManager.isVideoOff)
                        IconButton(
                          icon: const Icon(Icons.picture_in_picture_alt_rounded, color: AppTheme.mint, size: 22),
                          tooltip: 'Picture in Picture',
                          onPressed: () {
                            _callManager.enterNativePip();
                            _minimizeCall();
                          },
                        )
                      else
                        const SizedBox(width: 48), // Balance space with minimize icon
                    ],
                  ),
                ),
              ),

              // Unstable Connection Notification Banner
              if (_callManager.isReconnecting ||
                  _callManager.localConnectionQuality == ConnectionQuality.poor ||
                  _callManager.localConnectionQuality == ConnectionQuality.lost)
                Positioned(
                  top: 64,
                  left: 20,
                  right: 20,
                  child: GestureDetector(
                    onTap: _showNetworkHealthSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1428).withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _callManager.isReconnecting ? Colors.amberAccent : Colors.orangeAccent,
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _callManager.isReconnecting
                                ? Icons.sync_problem_rounded
                                : Icons.warning_amber_rounded,
                            color: _callManager.isReconnecting ? Colors.amberAccent : Colors.orangeAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _callManager.isReconnecting
                                  ? 'Reconnecting to call server... Please wait.'
                                  : 'Network unstable. Prioritizing voice clarity.',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),

              // 3. MODERN TWO-TIER IN-CALL CONTROL SUITE
              Positioned(
                bottom: 14,
                left: 12,
                right: 12,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // TIER 1: Secondary Quick Actions Pill
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16122C).withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // In-Call Chat
                              _buildCallToolChip(
                                icon: Badge(
                                  isLabelVisible: _unreadChatCount > 0,
                                  label: Text('$_unreadChatCount'),
                                  backgroundColor: AppTheme.mint,
                                  child: const Icon(Icons.chat_bubble_outline_rounded, size: 17, color: AppTheme.mint),
                                ),
                                label: 'Chat',
                                onTap: _showInCallChatSheet,
                              ),
                              const SizedBox(width: 8),

                              // Screen Share
                              _buildCallToolChip(
                                icon: Icon(
                                  _callManager.isScreenSharing
                                      ? Icons.stop_screen_share_rounded
                                      : Icons.screen_share_rounded,
                                  size: 17,
                                  color: _callManager.isScreenSharing ? Colors.amberAccent : AppTheme.mint,
                                ),
                                label: _callManager.isScreenSharing ? 'Stop Share' : 'Share',
                                isActive: _callManager.isScreenSharing,
                                activeColor: Colors.amberAccent,
                                onTap: _callManager.toggleScreenShare,
                              ),
                              const SizedBox(width: 8),

                              // Record Call
                              _buildCallToolChip(
                                icon: _callManager.isRecordingStarting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                                      )
                                    : Icon(
                                        _callManager.isRecording
                                            ? Icons.stop_circle_rounded
                                            : Icons.fiber_manual_record_rounded,
                                        size: 17,
                                        color: _callManager.isRecording ? Colors.redAccent : Colors.white70,
                                      ),
                                label: _callManager.isRecording ? 'Stop Rec' : 'Record',
                                isActive: _callManager.isRecording,
                                activeColor: Colors.redAccent,
                                onTap: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  final wasRecording = _callManager.isRecording;
                                  await _callManager.toggleRecording();
                                  if (mounted) {
                                    messenger.hideCurrentSnackBar();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          wasRecording
                                              ? 'Recording stopped. Video will save to your device.'
                                              : 'Call recording started! Video is being captured.',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        duration: const Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                        backgroundColor: wasRecording ? const Color(0xFF1E1A36) : Colors.redAccent.shade700,
                                      ),
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),

                              // Add Participant
                              _buildCallToolChip(
                                icon: const Icon(Icons.person_add_alt_1_rounded, size: 17, color: AppTheme.mint),
                                label: '+ Member',
                                onTap: _showAddParticipantSheet,
                              ),

                              // Flip Camera (only if video camera is on)
                              if (!_callManager.isVideoOff) ...[
                                const SizedBox(width: 8),
                                _buildCallToolChip(
                                  icon: const Icon(Icons.cameraswitch_rounded, size: 17, color: AppTheme.mint),
                                  label: 'Flip',
                                  onTap: _callManager.switchCamera,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // TIER 2: Primary Control Capsule
                      Container(
                        constraints: const BoxConstraints(maxWidth: 390),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceElevated.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(38),
                          border: Border.all(color: AppTheme.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.55),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            // 1. Microphone Mute Toggle
                            _buildPrimaryCallActionButton(
                              icon: Icon(
                                _callManager.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                color: _callManager.isMuted ? Colors.white : AppTheme.mint,
                                size: 24,
                              ),
                              tooltip: _callManager.isMuted ? 'Unmute Mic' : 'Mute Mic',
                              isActive: _callManager.isMuted,
                              activeColor: Colors.redAccent,
                              inactiveColor: AppTheme.mint.withValues(alpha: 0.15),
                              onTap: _callManager.toggleMute,
                            ),

                            // 2. Video Camera Toggle
                            _buildPrimaryCallActionButton(
                              icon: Icon(
                                _callManager.isVideoOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                                color: _callManager.isVideoOff ? Colors.white54 : AppTheme.mint,
                                size: 24,
                              ),
                              tooltip: _callManager.isVideoOff ? 'Turn Video On' : 'Turn Video Off',
                              isActive: !_callManager.isVideoOff,
                              activeColor: AppTheme.mint.withValues(alpha: 0.22),
                              inactiveColor: Colors.white.withValues(alpha: 0.08),
                              onTap: () {
                                if (!_callManager.isVideo) {
                                  // In an audio call: request remote peer to switch to video (WhatsApp style)
                                  final myUid = FirebaseAuth.instance.currentUser?.uid;
                                  final myName = FirebaseAuth.instance.currentUser?.displayName ?? 'User';
                                  if (myUid != null) {
                                    CallSignalingService.requestVideoUpgrade(
                                      callId: widget.callId,
                                      requesterId: myUid,
                                      requesterName: myName,
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Requesting ${widget.peerName} to switch to video...'),
                                        backgroundColor: AppTheme.mintDark,
                                        duration: const Duration(seconds: 3),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } else {
                                  _callManager.toggleVideo();
                                }
                              },
                            ),

                            // 3. Audio Route Switcher (Speaker, Earpiece, Bluetooth)
                            _buildPrimaryCallActionButton(
                              icon: Icon(
                                _callManager.isSpeakerOn
                                    ? Icons.volume_up_rounded
                                    : (_callManager.currentAudioOutput == AudioOutputDevice.bluetooth
                                        ? Icons.bluetooth_audio_rounded
                                        : Icons.phone_iphone_rounded),
                                color: _callManager.isSpeakerOn ? AppTheme.mint : Colors.white,
                                size: 24,
                              ),
                              tooltip: 'Audio Output (${_callManager.currentAudioOutput.name})',
                              isActive: _callManager.isSpeakerOn || _callManager.currentAudioOutput == AudioOutputDevice.bluetooth,
                              activeColor: AppTheme.mint.withValues(alpha: 0.22),
                              inactiveColor: Colors.white.withValues(alpha: 0.08),
                              onTap: _showAudioOutputSelectorSheet,
                            ),

                            // 4. End Call Button (Prominent circular red button, always visible & accessible)
                            Tooltip(
                              message: 'End Call',
                              child: GestureDetector(
                                onTap: _endCall,
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: AppTheme.callRed,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.callRed.withValues(alpha: 0.45),
                                        blurRadius: 14,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.call_end_rounded, color: Colors.white, size: 26),
                                  ),
                                ),
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildPrimaryCallActionButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool isActive = false,
    Color? activeColor,
    Color? inactiveColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: isActive
                ? (activeColor ?? AppTheme.mint.withValues(alpha: 0.2))
                : (inactiveColor ?? Colors.white.withValues(alpha: 0.08)),
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive
                  ? (activeColor?.withValues(alpha: 0.4) ?? AppTheme.mint.withValues(alpha: 0.4))
                  : Colors.white.withValues(alpha: 0.12),
              width: 1.2,
            ),
          ),
          child: Center(child: icon),
        ),
      ),
    );
  }

  Widget _buildCallToolChip({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    Color? activeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? (activeColor?.withValues(alpha: 0.22) ?? AppTheme.mint.withValues(alpha: 0.22))
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? (activeColor ?? AppTheme.mint)
                : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isActive ? (activeColor ?? AppTheme.mint) : Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
