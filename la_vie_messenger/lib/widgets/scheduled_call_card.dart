import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/active_call_manager.dart';
import '../screens/call_screens.dart';

class ScheduledCallCard extends StatefulWidget {
  final Map<String, dynamic> messageData;
  final String currentUserId;
  final bool isMe;

  const ScheduledCallCard({
    super.key,
    required this.messageData,
    required this.currentUserId,
    required this.isMe,
  });

  @override
  State<ScheduledCallCard> createState() => _ScheduledCallCardState();
}

class _ScheduledCallCardState extends State<ScheduledCallCard> {
  bool _isActionLoading = false;

  Map<String, dynamic> get _callInfo {
    final sched = widget.messageData['scheduledCall'];
    if (sched is Map<String, dynamic>) return sched;
    return widget.messageData;
  }

  String get _callId => _callInfo['callId'] ?? '';
  String get _roomName => _callInfo['roomName'] ?? 'call_$_callId';
  String get _topic => _callInfo['topic'] ?? 'Scheduled Call';
  bool get _isVideo => _callInfo['isVideo'] == true || _callInfo['isVideo'] == 'true';
  String get _callerId => _callInfo['callerId'] ?? '';
  String get _callerName => _callInfo['callerName'] ?? 'Host';
  String get _status => _callInfo['status'] ?? 'scheduled';
  int get _reminderMinutes => _callInfo['reminderMinutes'] is int ? _callInfo['reminderMinutes'] : 10;

  DateTime? get _scheduledDateTime {
    final raw = _callInfo['scheduledTime'];
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  bool get _isCaller => widget.currentUserId == _callerId;

  bool get _canJoin {
    if (_status == 'cancelled' || _status == 'ended') return false;
    final sched = _scheduledDateTime;
    if (sched == null) return true;
    final now = DateTime.now();
    // Allow join starting 15 minutes before scheduled time until 4 hours after
    return now.isAfter(sched.subtract(const Duration(minutes: 15))) &&
        now.isBefore(sched.add(const Duration(hours: 4)));
  }

  String _formatRelativeTime(DateTime sched) {
    final now = DateTime.now();
    final diff = sched.difference(now);

    if (diff.isNegative) {
      if (diff.inHours.abs() < 1) {
        return "Started ${diff.inMinutes.abs()}m ago";
      } else {
        return "Scheduled earlier";
      }
    }

    if (diff.inMinutes < 60) {
      return "Starts in ${diff.inMinutes} mins";
    } else if (diff.inHours < 24) {
      return "Starts in ${diff.inHours}h ${diff.inMinutes % 60}m";
    } else {
      return DateFormat('EEE, MMM d • h:mm a').format(sched);
    }
  }

  Future<void> _addToCalendar() async {
    final sched = _scheduledDateTime;
    if (sched == null) return;

    final endTime = sched.add(const Duration(minutes: 45));

    // 1. Try Native Android Intent
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.INSERT',
          data: 'content://com.android.calendar/events',
          arguments: <String, dynamic>{
            'title': 'LiChat: $_topic',
            'description': 'LiChat ${_isVideo ? "Video" : "Voice"} Call with $_callerName\nJoin via LiChat App.',
            'beginTime': sched.millisecondsSinceEpoch,
            'endTime': endTime.millisecondsSinceEpoch,
            'hasAlarm': 1,
          },
        );
        await intent.launch();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Added to device calendar 📅")),
          );
        }
        return;
      } catch (e) {
        debugPrint("Android calendar intent error: $e");
      }
    }

    // 2. Fallback: Google Calendar Web URL
    try {
      final startTimeStr = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(sched.toUtc());
      final endTimeStr = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(endTime.toUtc());
      final gcalUrl = Uri.parse(
        "https://calendar.google.com/calendar/render?action=TEMPLATE"
        "&text=${Uri.encodeComponent('LiChat: $_topic')}"
        "&dates=$startTimeStr/$endTimeStr"
        "&details=${Uri.encodeComponent('Scheduled LiChat ${_isVideo ? "Video" : "Voice"} Call')}",
      );
      if (await canLaunchUrl(gcalUrl)) {
        await launchUrl(gcalUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("GCal web launch error: $e");
    }
  }

  Future<void> _joinCall() async {
    if (_callId.isEmpty) return;

    setState(() => _isActionLoading = true);
    try {
      await ActiveCallManager.instance.connect(
        callId: _callId,
        roomName: _roomName,
        isVideo: _isVideo,
        peerName: _topic,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveCallScreen(
              callId: _callId,
              roomName: _roomName,
              isVideo: _isVideo,
              peerName: _topic,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error connecting to scheduled call: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not join call: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _cancelCall() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text("Cancel Scheduled Call?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Are you sure you want to cancel this scheduled call? All participants will be notified.",
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Keep", style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("Cancel Call", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isActionLoading = true);
    try {
      await http.post(
        Uri.parse('https://la-vie.lifechangerstouch.org/api/lichat/call/cancel'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'callId': _callId,
          'userId': widget.currentUserId,
        }),
      );

      // Local state update
      setState(() {
        _callInfo['status'] = 'cancelled';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Scheduled call cancelled")),
        );
      }
    } catch (e) {
      debugPrint("Error cancelling call: $e");
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sched = _scheduledDateTime;
    final isCancelled = _status == 'cancelled';
    final isEnded = _status == 'ended';

    Color cardBorderColor = AppTheme.border;
    Color statusBadgeColor = AppTheme.primary;
    String statusText = "Upcoming";

    if (isCancelled) {
      statusBadgeColor = Colors.redAccent;
      statusText = "Cancelled";
      cardBorderColor = Colors.redAccent.withValues(alpha: 0.3);
    } else if (isEnded) {
      statusBadgeColor = Colors.grey;
      statusText = "Ended";
    } else if (_canJoin) {
      statusBadgeColor = Colors.greenAccent;
      statusText = "Ready to Join";
      cardBorderColor = Colors.greenAccent.withValues(alpha: 0.4);
    }

    return Container(
      width: 290,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.35),
                    AppTheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      color: AppTheme.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isVideo ? "Scheduled Video Call" : "Scheduled Voice Call",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          "by $_callerName",
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBadgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: statusBadgeColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusBadgeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Topic & Time Body
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _topic,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (sched != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, color: AppTheme.primary, size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            DateFormat('EEE, MMM d, yyyy • h:mm a').format(sched),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.notifications_active_rounded, color: Colors.amberAccent, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '${_formatRelativeTime(sched)}${_reminderMinutes > 0 ? " • ${_reminderMinutes}m reminder" : ""}',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Action Buttons
                  Row(
                    children: [
                      // Add to calendar button
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _addToCalendar,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event_available_rounded, size: 15, color: Colors.white70),
                              SizedBox(width: 4),
                              Text("Calendar", style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Join Call Button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_canJoin && !_isActionLoading) ? _joinCall : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _canJoin ? Colors.greenAccent.shade700 : AppTheme.background,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: _isActionLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _canJoin ? Icons.call_rounded : Icons.lock_clock_rounded,
                                      size: 15,
                                      color: _canJoin ? Colors.white : Colors.white38,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _canJoin ? "Join" : "Pending",
                                      style: TextStyle(
                                        color: _canJoin ? Colors.white : Colors.white38,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),

                  // Cancel Call for Creator
                  if (_isCaller && !isCancelled && !isEnded) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: _cancelCall,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          "Cancel Scheduled Call",
                          style: TextStyle(color: Colors.redAccent, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
