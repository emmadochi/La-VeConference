import 'dart:ui';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/meeting.dart';
import '../services/notification_service.dart';
import 'video_room_screen.dart';
import 'pre_join_dialog.dart';
import 'notifications_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _inlineCodeController = TextEditingController();
  bool _showWhatsNewBanner = true;

  @override
  void dispose() {
    _inlineCodeController.dispose();
    super.dispose();
  }

  String _generateRoomCode() {
    return 'la-vie-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
  }

  String _generateE2EEKey() {
    final math.Random random = math.Random.secure();
    final List<int> values = List<int>.generate(16, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  Future<bool> _createGoogleCalendarEvent(String title, DateTime startTime, String roomId, String e2eeKey) async {
    try {
      final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account == null) return false;
      final auth = account.authentication;
      final token = auth.idToken ?? (await account.authorizationClient.authorizationForScopes([
        'https://www.googleapis.com/auth/calendar.events',
      ]))?.accessToken;
      
      if (token == null) return false;

      final endTime = startTime.add(const Duration(hours: 1));
      final meetingLink = 'https://la-vie.lifechangerstouch.org/?room=$roomId#$e2eeKey';

      final response = await http.post(
        Uri.parse('https://www.googleapis.com/calendar/v3/calendars/primary/events'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'summary': title,
          'description': 'Join La-Vie Conference:\n$meetingLink\n\nThis meeting is End-to-End Encrypted.',
          'start': {
            'dateTime': startTime.toUtc().toIso8601String(),
          },
          'end': {
            'dateTime': endTime.toUtc().toIso8601String(),
          },
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Calendar error: $e');
      return false;
    }
  }

  void _joinInlineMeeting([String? explicitCode]) async {
    String code = (explicitCode ?? _inlineCodeController.text).trim();
    if (code.contains('/')) {
      code = code.split('/').last;
    }
    if (code.contains('?')) {
      code = code.split('?').first;
    }
    if (code.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Premium User';

    final prefs = await showPreJoinDialog(context);
    if (prefs == null || !mounted) return;

    bool isHost = false;
    String? meetingTitle;
    if (user != null) {
      try {
        final docDirect = await FirebaseFirestore.instance.collection('meetings').doc(code).get();
        if (docDirect.exists && docDirect.data() != null) {
          final data = docDirect.data()!;
          isHost = data['hostId'] == user.uid;
          meetingTitle = data['title'] as String?;
        } else {
          final query = await FirebaseFirestore.instance.collection('meetings').where('roomId', isEqualTo: code).limit(1).get();
          if (query.docs.isNotEmpty) {
            final data = query.docs.first.data();
            isHost = data['hostId'] == user.uid;
            meetingTitle = data['title'] as String?;
          }
        }
      } catch (e) {
        debugPrint('Failed to check host status: $e');
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoRoomScreen(
          roomName: code,
          meetingTitle: meetingTitle,
          participantName: displayName,
          initialAudioOn: prefs['audio'] ?? true,
          initialVideoOn: prefs['video'] ?? true,
          isHost: isHost,
        ),
      ),
    );
  }

  void _startNewMeeting() async {
    final roomId = _generateRoomCode();
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Premium User';
    final defaultTitle = "$displayName's Meeting";
    
    final prefs = await showPreJoinDialog(context, isCreating: true, defaultMeetingTitle: defaultTitle);
    if (prefs == null) return;

    final meetingTitle = (prefs['title'] is String && (prefs['title'] as String).trim().isNotEmpty)
        ? (prefs['title'] as String).trim()
        : defaultTitle;

    try {
      final e2eeKey = _generateE2EEKey();
      final sp = await SharedPreferences.getInstance();
      await sp.setString('e2ee_$roomId', e2eeKey);

      final meeting = Meeting(
        id: roomId,
        title: meetingTitle,
        roomId: roomId,
        hostId: user?.uid ?? '',
        scheduledTime: DateTime.now(),
      );
      await FirebaseFirestore.instance.collection('meetings').doc(roomId).set(meeting.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to save instant meeting to Firestore: $e');
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoRoomScreen(
          roomName: roomId,
          meetingTitle: meetingTitle,
          participantName: displayName,
          initialAudioOn: prefs['audio'] ?? true,
          initialVideoOn: prefs['video'] ?? true,
          isHost: true,
        ),
      ),
    );
  }

  // ==========================================
  // NEW MEETING OPTIONS BOTTOM SHEET
  // ==========================================
  void _showNewMeetingOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.96),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.video_call, color: Color(0xFF00E5FF), size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'New Meeting',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Option 1: Start Instant Meeting
                  _buildMeetingOptionTile(
                    icon: Icons.flash_on,
                    iconColor: const Color(0xFF00E5FF),
                    title: 'Start an instant meeting',
                    subtitle: 'Launch a room immediately and enter the stage',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _startNewMeeting();
                    },
                  ),
                  const SizedBox(height: 12),

                  // Option 2: Schedule in Calendar
                  _buildMeetingOptionTile(
                    icon: Icons.calendar_today_outlined,
                    iconColor: const Color(0xFF5C00FF),
                    title: 'Schedule in calendar',
                    subtitle: 'Plan ahead with title, date & 15-min start alerts',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showScheduleMeetingDialog();
                    },
                  ),
                  const SizedBox(height: 12),

                  // Option 3: Get Meeting Link to Share
                  _buildMeetingOptionTile(
                    icon: Icons.link,
                    iconColor: const Color(0xFF00FFA3),
                    title: 'Get a meeting link to share',
                    subtitle: 'Create a room link to copy and share for later',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _createMeetingLinkForLater();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMeetingOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // SCHEDULE MEETING DIALOG
  // ==========================================
  void _showScheduleMeetingDialog() {
    final TextEditingController titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.96),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF5C00FF).withOpacity(0.4), width: 1.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF5C00FF).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.event_available, color: Color(0xFF00E5FF), size: 36),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Schedule Meeting',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: titleController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Meeting Title (e.g. Sunday Service)',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final DateTime? pickedDate = await showDatePicker(
                                    context: context,
                                    initialDate: selectedDate,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime(2101),
                                  );
                                  if (pickedDate != null) {
                                    setDialogState(() => selectedDate = pickedDate);
                                  }
                                },
                                icon: const Icon(Icons.calendar_today, size: 16),
                                label: Text(DateFormat('MMM d, yyyy').format(selectedDate), style: const TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(0.08),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final TimeOfDay? pickedTime = await showTimePicker(
                                    context: context,
                                    initialTime: selectedTime,
                                  );
                                  if (pickedTime != null) {
                                    setDialogState(() => selectedTime = pickedTime);
                                  }
                                },
                                icon: const Icon(Icons.access_time, size: 16),
                                label: Text(selectedTime.format(context), style: const TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(0.08),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(dialogCtx),
                                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final title = titleController.text.trim();
                                  if (title.isEmpty) return;

                                  final scheduledDateTime = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    selectedTime.hour,
                                    selectedTime.minute,
                                  );

                                  final roomId = _generateRoomCode();
                                  final e2eeKey = _generateE2EEKey();
                                  
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setString('e2ee_$roomId', e2eeKey);

                                  final hostId = FirebaseAuth.instance.currentUser?.uid ?? '';

                                  final meeting = Meeting(
                                    id: roomId,
                                    title: title,
                                    roomId: roomId,
                                    hostId: hostId,
                                    scheduledTime: scheduledDateTime,
                                  );

                                  await FirebaseFirestore.instance.collection('meetings').doc(roomId).set(meeting.toFirestore(), SetOptions(merge: true));

                                  final notificationId = roomId.hashCode;
                                  NotificationService().showImmediateNotification(
                                    id: notificationId,
                                    title: 'Meeting Scheduled',
                                    body: '$title is set for ${DateFormat('MMM d, h:mm a').format(scheduledDateTime)}',
                                  );

                                  final reminderTime = scheduledDateTime.subtract(const Duration(minutes: 15));
                                  NotificationService().scheduleMeetingReminder(
                                    id: notificationId + 1,
                                    title: 'Upcoming Meeting: $title',
                                    body: 'Starts in 15 minutes',
                                    scheduledDate: reminderTime,
                                  );

                                  final success = await _createGoogleCalendarEvent(title, scheduledDateTime, roomId, e2eeKey);
                                  
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: const Color(0xFF00FFA3),
                                        content: Text(
                                          success ? '🎉 Meeting scheduled & synced to Google Calendar!' : '🎉 Meeting scheduled successfully!',
                                          style: const TextStyle(color: Color(0xFF070B19), fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    );
                                  }

                                  Navigator.pop(dialogCtx);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E5FF),
                                  foregroundColor: const Color(0xFF070B19),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: const Text('Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // CREATE LINK FOR LATER DIALOG
  // ==========================================
  void _createMeetingLinkForLater() async {
    final roomId = _generateRoomCode();
    final e2eeKey = _generateE2EEKey();
    final hostId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Premium User';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('e2ee_$roomId', e2eeKey);

    final meeting = Meeting(
      id: roomId,
      title: '$displayName\'s Meeting',
      roomId: roomId,
      hostId: hostId,
      scheduledTime: DateTime.now(),
    );
    await FirebaseFirestore.instance.collection('meetings').doc(roomId).set(meeting.toFirestore(), SetOptions(merge: true));

    final meetingLink = 'https://la-vie.lifechangerstouch.org/?room=$roomId#$e2eeKey';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withOpacity(0.96),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.35), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FFA3).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.link, color: Color(0xFF00FFA3), size: 28),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Here\'s your joining info',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Send this link to people you want to meet with. Be sure to save it so you can use it later, too.',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              meetingLink,
                              style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, color: Colors.white, size: 20),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: meetingLink));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Meeting link copied to clipboard!'),
                                  backgroundColor: Color(0xFF00FFA3),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            child: const Text('Done', style: TextStyle(color: Colors.white60)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Share.share('Join my La-Vie Meeting:\n$meetingLink\n\nRoom ID: $roomId');
                            },
                            icon: const Icon(Icons.share, size: 16),
                            label: const Text('Share Link', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00FFA3),
                              foregroundColor: const Color(0xFF070B19),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWhatsNewCard() {
    if (!_showWhatsNewBanner) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.stars, color: Color(0xFF00E5FF), size: 14),
                    SizedBox(width: 6),
                    Text(
                      "WHAT'S NEW",
                      style: TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => setState(() => _showWhatsNewBanner = false),
                child: const Icon(Icons.close, color: Colors.white54, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'vMix & OBS Studio Ingest Supported',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Broadcast high-definition studio video feeds directly into La-Vie conference rooms with sub-second WebRTC latency.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  void _showJoinMeetingDialog() {
    final TextEditingController _codeController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF070B19).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.meeting_room, color: Color(0xFF00E5FF), size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Join a Meeting',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the room code to join',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _codeController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'e.g. la-vie-123456',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white54, fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              String code = _codeController.text.trim();
                              // Simple URL extraction if user pastes full url
                              if (code.contains('/')) {
                                code = code.split('/').last;
                              }
                              if (code.contains('?')) {
                                code = code.split('?').first;
                              }
                              if (code.isNotEmpty) {
                                Navigator.pop(dialogContext);
                                final user = FirebaseAuth.instance.currentUser;
                                final displayName = user?.displayName ?? 'Premium User';
                                
                                final prefs = await showPreJoinDialog(context);
                                if (prefs == null) return;
                                
                                bool isHost = false;
                                String? meetingTitle;
                                if (user != null) {
                                  try {
                                    final docDirect = await FirebaseFirestore.instance.collection('meetings').doc(code).get();
                                    if (docDirect.exists && docDirect.data() != null) {
                                      final data = docDirect.data()!;
                                      isHost = data['hostId'] == user.uid;
                                      meetingTitle = data['title'] as String?;
                                    } else {
                                      final query = await FirebaseFirestore.instance.collection('meetings').where('roomId', isEqualTo: code).limit(1).get();
                                      if (query.docs.isNotEmpty) {
                                        final data = query.docs.first.data();
                                        isHost = data['hostId'] == user.uid;
                                        meetingTitle = data['title'] as String?;
                                      }
                                    }
                                  } catch (e) {
                                    debugPrint('Failed to check host status: $e');
                                  }
                                }
                                
                                if (!mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => VideoRoomScreen(
                                      roomName: code,
                                      meetingTitle: meetingTitle,
                                      participantName: displayName,
                                      initialAudioOn: prefs['audio'] ?? true,
                                      initialVideoOn: prefs['video'] ?? true,
                                      isHost: isHost,
                                    ),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E5FF),
                              foregroundColor: const Color(0xFF070B19),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            child: const Text('Join', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName;
    final greetingName = displayName != null && displayName.isNotEmpty ? displayName : 'User';
    final initial = greetingName.substring(0, 1).toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      body: Stack(
        children: [
          // Background Gradient Effects
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00E5FF).withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -150,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF5C00FF).withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Top Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/logoI.png',
                            width: 32,
                            height: 32,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'La-Vie',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                          );
                        },
                        borderRadius: BorderRadius.circular(50),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.notifications_none, color: Colors.white, size: 24),
                              Positioned(
                                top: -2,
                                right: 2,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF2E93),
                                    shape: BoxShape.circle,
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
                
                // Active Meeting Banner
                if (Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null)
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
                      final data = snapshot.data!.data() as Map<String, dynamic>?;
                      final activeRoom = data?['active_room'] as String?;
                      if (activeRoom == null || activeRoom.isEmpty) return const SizedBox.shrink();

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.videocam, color: Color(0xFF00E5FF)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Active Meeting in Progress', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  Text(activeRoom, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white70,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: const BorderSide(color: Colors.white54),
                                    ),
                                  ),
                                  onPressed: () async {
                                    final uid = FirebaseAuth.instance.currentUser?.uid;
                                    if (uid != null) {
                                      await FirebaseFirestore.instance.collection('users').doc(uid).update({'active_room': ''});
                                    }
                                  },
                                  child: const Text('Leave'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00E5FF),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () async {
                                    final prefs = await showPreJoinDialog(context);
                                    if (prefs == null || !mounted) return;

                                    final user = FirebaseAuth.instance.currentUser;
                                    bool isHost = false;
                                    String? meetingTitle;
                                    if (user != null) {
                                      try {
                                        final docDirect = await FirebaseFirestore.instance.collection('meetings').doc(activeRoom).get();
                                        if (docDirect.exists && docDirect.data() != null) {
                                          final data = docDirect.data()!;
                                          isHost = data['hostId'] == user.uid;
                                          meetingTitle = data['title'] as String?;
                                        } else {
                                          final query = await FirebaseFirestore.instance.collection('meetings').where('roomId', isEqualTo: activeRoom).limit(1).get();
                                          if (query.docs.isNotEmpty) {
                                            final data = query.docs.first.data();
                                            isHost = data['hostId'] == user.uid;
                                            meetingTitle = data['title'] as String?;
                                          }
                                        }
                                      } catch (e) {
                                        debugPrint('Failed to check host status for active room: $e');
                                      }
                                    }

                                    if (!mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => VideoRoomScreen(
                                          roomName: activeRoom,
                                          meetingTitle: meetingTitle,
                                          participantName: user?.displayName ?? 'User',
                                          initialAudioOn: prefs['audio'] ?? true,
                                          initialVideoOn: prefs['video'] ?? true,
                                          isHost: isHost,
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text('Rejoin'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                
                // Mobile Greeting & User Profile Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1E1E30),
                              border: Border.all(color: const Color(0xFF00E5FF), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF).withOpacity(0.4),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                )
                              ],
                            ),
                            child: Center(
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Good Morning,',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                greetingName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                        ),
                        child: const Text(
                          'PRO',
                          style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 8),

                // "What's New" Dismissible Marketing Card (Placed directly under Greeting Header)
                _buildWhatsNewCard(),

                const SizedBox(height: 12),

                // Mobile Quick Action Buttons (Stacked Vertically)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    children: [
                      // New Meeting Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _showNewMeetingOptionsSheet,
                          icon: const Icon(Icons.video_call, color: Colors.black, size: 22),
                          label: const Text(
                            'New meeting',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E5FF),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Join with Code Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _showJoinMeetingDialog,
                          icon: const Icon(Icons.keyboard_alt_outlined, color: Color(0xFF00E5FF), size: 22),
                          label: const Text(
                            'Join with code',
                            style: TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.5), width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            backgroundColor: Colors.white.withOpacity(0.04),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Upcoming & Active Meetings Card Container
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                        ),
                        child: Column(
                          children: [
                            
                            // Tabs Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'UPCOMING MEETINGS',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // StreamBuilder for Live Meetings
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('meetings')
                                  .where('hostId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                                  .orderBy('scheduledTime')
                                  .limit(3)
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (snapshot.hasError) {
                                  final errStr = snapshot.error.toString();
                                  if (errStr.contains('failed-precondition') || errStr.contains('requires an index')) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 16.0),
                                      child: Text(
                                        'Database index required. Please check your console logs for the Firebase index creation link.',
                                        style: TextStyle(color: Colors.amber, fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  }
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16.0),
                                    child: Text(
                                      'Error loading meetings. Please try again.',
                                      style: TextStyle(color: Colors.redAccent, fontSize: 13),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
                                }

                                final docs = snapshot.data?.docs ?? [];
                                if (docs.isEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    child: Text(
                                      'No upcoming meetings.',
                                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                                    ),
                                  );
                                }

                                return Column(
                                  children: docs.map((doc) {
                                    final meeting = Meeting.fromFirestore(doc);
                                    final formattedTime = DateFormat('MMM d, yyyy • h:mm a').format(meeting.scheduledTime);
                                    
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                meeting.title,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  Icon(Icons.access_time, color: Colors.white.withOpacity(0.5), size: 20),
                                                  const SizedBox(width: 8),
                                                  Icon(Icons.calendar_today, color: Colors.white.withOpacity(0.5), size: 20),
                                                ],
                                              )
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            formattedTime,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.7),
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Room ID: ${meeting.roomId}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.7),
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              GestureDetector(
                                                onTap: () => _showMeetingDetails(context, meeting),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: const Text(
                                                    'Details',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withOpacity(0.1),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(Icons.videocam, color: Colors.white, size: 20),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  GestureDetector(
                                                    onTap: () async {
                                                      final prefs = await showPreJoinDialog(context);
                                                      if (prefs == null) return;
                                                      if (!mounted) return;
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (context) => VideoRoomScreen(
                                                            roomName: meeting.roomId,
                                                            meetingTitle: meeting.title,
                                                            participantName: FirebaseAuth.instance.currentUser?.displayName ?? 'Premium User',
                                                            initialAudioOn: prefs['audio'] ?? true,
                                                            initialVideoOn: prefs['video'] ?? true,
                                                            isHost: meeting.hostId == FirebaseAuth.instance.currentUser?.uid,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: const BoxDecoration(
                                                        color: Color(0xFF00E5FF),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: const Icon(Icons.arrow_forward, color: Color(0xFF070B19), size: 20),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  }

  void _showMeetingDetails(BuildContext context, Meeting meeting) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF070B19).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Meeting Details',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      meeting.title,
                      style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('MMM d, yyyy • h:mm a').format(meeting.scheduledTime),
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Room ID', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                              Text(meeting.roomId, style: const TextStyle(color: Colors.white, fontSize: 16)),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, color: Color(0xFF00E5FF)),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: meeting.roomId));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room ID copied to clipboard')));
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: const Color(0xFF070B19),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
