import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import '../screens/pre_join_dialog.dart';
import '../screens/video_room_screen.dart';
import '../services/calendar_helper.dart';
import '../services/notification_service.dart';

class UpcomingMeetingInviteSheet extends StatefulWidget {
  final String roomId;
  final String? e2eeKey;
  final String title;
  final String hostName;
  final String hostId;
  final DateTime scheduledTime;
  final int? existingReminderMinutes;
  final bool isPermanent;

  const UpcomingMeetingInviteSheet({
    super.key,
    required this.roomId,
    this.e2eeKey,
    required this.title,
    required this.hostName,
    required this.hostId,
    required this.scheduledTime,
    this.existingReminderMinutes,
    this.isPermanent = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String roomId,
    String? e2eeKey,
    required String title,
    required String hostName,
    required String hostId,
    required DateTime scheduledTime,
    int? existingReminderMinutes,
    bool isPermanent = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UpcomingMeetingInviteSheet(
        roomId: roomId,
        e2eeKey: e2eeKey,
        title: title,
        hostName: hostName,
        hostId: hostId,
        scheduledTime: scheduledTime,
        existingReminderMinutes: existingReminderMinutes,
        isPermanent: isPermanent,
      ),
    );
  }

  @override
  State<UpcomingMeetingInviteSheet> createState() => _UpcomingMeetingInviteSheetState();
}

class _UpcomingMeetingInviteSheetState extends State<UpcomingMeetingInviteSheet> {
  late int _selectedReminderMinutes;
  bool _isSavingReminder = false;
  bool _reminderSaved = false;
  bool _isOpeningCalendar = false;
  Timer? _countdownTimer;
  String _countdownText = '';

  static const List<Map<String, dynamic>> _reminderOptions = [
    {'label': 'At start', 'mins': 0},
    {'label': '10 min', 'mins': 10},
    {'label': '15 min', 'mins': 15},
    {'label': '30 min', 'mins': 30},
    {'label': '1 hour', 'mins': 60},
  ];

  @override
  void initState() {
    super.initState();
    _selectedReminderMinutes = widget.existingReminderMinutes ?? 15;
    _reminderSaved = widget.existingReminderMinutes != null;
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateCountdown();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    if (widget.isPermanent) {
      if (_countdownText != 'Permanent Room • Always Open') {
        setState(() => _countdownText = 'Permanent Room • Always Open');
      }
      return;
    }
    final diff = widget.scheduledTime.difference(DateTime.now());
    if (diff.isNegative || diff.inSeconds <= 0) {
      setState(() => _countdownText = 'Starting now!');
      return;
    }
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final mins = diff.inMinutes % 60;
    final secs = diff.inSeconds % 60;
    String formatted;
    if (days > 0) {
      formatted = 'Starts in ${days}d ${hours}h ${mins}m';
    } else if (hours > 0) {
      formatted = 'Starts in ${hours}h ${mins.toString().padLeft(2, '0')}m ${secs.toString().padLeft(2, '0')}s';
    } else {
      formatted = 'Starts in ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    if (_countdownText != formatted) {
      setState(() => _countdownText = formatted);
    }
  }

  Future<void> _setPushReminder() async {
    setState(() => _isSavingReminder = true);

    try {
      // Save E2EE key locally if came from invite link
      if (widget.e2eeKey != null && widget.e2eeKey!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('e2ee_${widget.roomId}', widget.e2eeKey!);
      }

      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (_) {}

      final ok = await ApiService.subscribeMeetingReminder(
        widget.roomId,
        reminderMinutes: _selectedReminderMinutes,
        fcmToken: fcmToken,
      );

      // Schedule local offline device alarm as guaranteed dual-delivery fallback
      final alarmId = '${widget.roomId}_invitee'.hashCode;
      await NotificationService().cancelNotification(alarmId);
      final targetTime = widget.scheduledTime.subtract(Duration(minutes: _selectedReminderMinutes));
      final leadLabel = _selectedReminderMinutes == 0
          ? 'now'
          : (_selectedReminderMinutes == 60 ? 'in 1 hour' : 'in $_selectedReminderMinutes minutes');

      if (targetTime.isAfter(DateTime.now())) {
        await NotificationService().scheduleMeetingReminder(
          id: alarmId,
          title: 'Upcoming Meeting: ${widget.title}',
          body: 'Starts $leadLabel • Tap to enter the meeting.',
          scheduledDate: targetTime,
          payload: 'open_room:${widget.roomId}${widget.e2eeKey != null && widget.e2eeKey!.isNotEmpty ? '#${widget.e2eeKey}' : ''}',
        );
      }

      if (mounted) {
        setState(() {
          _isSavingReminder = false;
          _reminderSaved = ok || targetTime.isAfter(DateTime.now());
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF00FFA3),
            content: Text(
              _selectedReminderMinutes == 0
                  ? 'Push reminder set for start time & saved to your Meetings!'
                  : 'Push reminder set for $_selectedReminderMinutes mins before & saved!',
              style: const TextStyle(color: Color(0xFF070B19), fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingReminder = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save reminder: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _addToGoogleCalendar() async {
    setState(() => _isOpeningCalendar = true);
    final status = await CalendarHelper.addMeetingToGoogleCalendar(
      title: widget.title,
      startTime: widget.scheduledTime,
      roomId: widget.roomId,
      e2eeKey: widget.e2eeKey,
      hostName: widget.hostName,
      reminderMinutes: _selectedReminderMinutes,
      allowInteractiveFallback: true,
    );
    if (!mounted) return;
    setState(() => _isOpeningCalendar = false);

    final msg = status == CalendarSyncStatus.addedViaApi
        ? 'Added directly to your Google Calendar!'
        : status == CalendarSyncStatus.openedTemplateIntent
            ? 'Opening Google Calendar to save event...'
            : 'Could not open Google Calendar on this device.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: status == CalendarSyncStatus.failed ? Colors.redAccent : const Color(0xFF00E5FF),
        content: Text(
          msg,
          style: TextStyle(
            color: status == CalendarSyncStatus.failed ? Colors.white : const Color(0xFF070B19),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _enterWaitingStageEarly() async {
    if (widget.e2eeKey != null && widget.e2eeKey!.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('e2ee_${widget.roomId}', widget.e2eeKey!);
    }
    if (!mounted) return;
    final prefs = await showPreJoinDialog(context);
    if (prefs == null || !mounted) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final fullRoom = (widget.e2eeKey != null && widget.e2eeKey!.isNotEmpty)
        ? '${widget.roomId}#${widget.e2eeKey}'
        : widget.roomId;

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoRoomScreen(
          roomName: fullRoom,
          meetingTitle: widget.title,
          participantName: FirebaseAuth.instance.currentUser?.displayName ?? 'Participant',
          initialAudioOn: prefs['audio'] ?? true,
          initialVideoOn: prefs['video'] ?? true,
          isHost: currentUid != null && currentUid == widget.hostId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('EEE, MMM d, yyyy • h:mm a').format(widget.scheduledTime);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 14, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.4), width: 1.5)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_available, color: Color(0xFF00E5FF), size: 15),
                      SizedBox(width: 6),
                      Text(
                        'UPCOMING MEETING INVITE',
                        style: TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Hosted by ${widget.hostName.isNotEmpty ? widget.hostName : "La-Vie Host"}',
                  style: const TextStyle(color: Colors.white60, fontSize: 13.5),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: widget.isPermanent ? const Color(0xFF00FFA3).withOpacity(0.08) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: widget.isPermanent ? const Color(0xFF00FFA3).withOpacity(0.3) : Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (!widget.isPermanent) ...[
                        Text(
                          formattedDate,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.isPermanent)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.all_inclusive_rounded, color: Color(0xFF00FFA3), size: 22),
                            ),
                          Text(
                            _countdownText,
                            style: const TextStyle(
                              color: Color(0xFF00FFA3),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!widget.isPermanent) ...[
                  const SizedBox(height: 18),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Push Notification Reminder Timing',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _reminderOptions.map((opt) {
                      final int mins = opt['mins'] as int;
                      final bool selected = _selectedReminderMinutes == mins;
                      return ChoiceChip(
                        label: Text(opt['label'] as String),
                        selected: selected,
                        onSelected: (_) => setState(() {
                          _selectedReminderMinutes = mins;
                          _reminderSaved = false;
                        }),
                        selectedColor: const Color(0xFF00E5FF),
                        backgroundColor: Colors.white.withOpacity(0.08),
                        labelStyle: TextStyle(
                          color: selected ? const Color(0xFF070B19) : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: selected ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.15),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSavingReminder ? null : _setPushReminder,
                      icon: _isSavingReminder
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF070B19)),
                            )
                          : Icon(_reminderSaved ? Icons.notifications_active : Icons.notifications_none_rounded),
                      label: Text(
                        _reminderSaved ? 'Push Reminder Active (Update)' : 'Set Push Notification Reminder',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _reminderSaved ? const Color(0xFF00FFA3) : const Color(0xFF00E5FF),
                        foregroundColor: const Color(0xFF070B19),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _enterWaitingStageEarly,
                    icon: const Icon(Icons.video_call_rounded, color: Colors.white, size: 22),
                    label: Text(
                      widget.isPermanent ? 'Enter Permanent Room Now' : 'Enter Meeting Room',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5C00FF),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isOpeningCalendar ? null : _addToGoogleCalendar,
                    icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
                    label: const Text(
                      'Add to Google Calendar',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withOpacity(0.25)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

