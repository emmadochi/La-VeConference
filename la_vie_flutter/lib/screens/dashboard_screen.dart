import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../api_service.dart';
import '../models/meeting.dart';
import '../services/calendar_helper.dart';
import '../widgets/schedule_meeting_dialog.dart';
import '../widgets/upcoming_meeting_invite_sheet.dart';
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
  String? _cachedAvatarUrl;

  @override
  void initState() {
    super.initState();
    _loadDashboardAvatar();
  }

  String? _normalizeAvatarUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('/')) {
      return '${ApiService.baseUrl}$trimmed';
    }
    return trimmed;
  }

  Future<void> _loadDashboardAvatar() async {
    final user = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;
    if (user == null) return;
    final authUrl = _normalizeAvatarUrl(user.photoURL);
    if (authUrl != null && mounted) {
      setState(() => _cachedAvatarUrl = authUrl);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = _normalizeAvatarUrl(prefs.getString('user_avatar_cache_${user.uid}'));
      if (cached != null && mounted) {
        setState(() => _cachedAvatarUrl = cached);
      }
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final fsUrl = _normalizeAvatarUrl((data['photoURL'] ?? data['avatar'])?.toString());
        if (fsUrl != null) {
          await prefs.setString('user_avatar_cache_${user.uid}', fsUrl);
          if (mounted) setState(() => _cachedAvatarUrl = fsUrl);
        }
      }
    } catch (_) {}
  }

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

  Map<String, String?> _extractRoomAndKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return {'roomId': '', 'e2eeKey': null};

    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && (parsed.hasScheme || trimmed.contains('?room=') || trimmed.contains('/'))) {
      String? room = parsed.queryParameters['room'];
      if ((room == null || room.isEmpty) && parsed.pathSegments.isNotEmpty) {
        final segs = parsed.pathSegments;
        if (segs.length >= 2 && ['meeting', 'room', 'join', 'conf'].contains(segs[0])) {
          room = segs[1];
        } else {
          room = segs.last;
        }
      }
      final key = parsed.fragment.isNotEmpty ? parsed.fragment.trim() : null;
      if (room != null && room.isNotEmpty) {
        return {'roomId': room.split('#').first.trim(), 'e2eeKey': key};
      }
    }

    if (trimmed.contains('#')) {
      final parts = trimmed.split('#');
      return {'roomId': parts.first.trim(), 'e2eeKey': parts.sublist(1).join('#').trim()};
    }
    return {'roomId': trimmed, 'e2eeKey': null};
  }

  Future<void> _joinMeetingByRawInput(String rawInput) async {
    final extracted = _extractRoomAndKey(rawInput);
    final code = extracted['roomId'] ?? '';
    final e2eeKey = extracted['e2eeKey'];
    if (code.isEmpty) return;

    if (e2eeKey != null && e2eeKey.isNotEmpty) {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('e2ee_$code', e2eeKey);
      } catch (_) {}
    }

    // Check if the entered room/link is a future scheduled meeting (for invitees / reminder flow)
    final info = await ApiService.fetchPublicMeetingInfo(code);
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (info != null && info['isFutureScheduled'] == true && info['scheduledTimeTs'] != null) {
      final ts = int.tryParse(info['scheduledTimeTs'].toString()) ?? 0;
      if (ts > 0) {
        final schedDt = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toLocal();
        final existingRem = info['myReminder'] is Map ? (info['myReminder']['reminderMinutes'] as int?) : null;
        final bool isPerm = info['isPermanent'] == true || info['meetingType'] == 'permanent';
        await UpcomingMeetingInviteSheet.show(
          context,
          roomId: code,
          e2eeKey: e2eeKey,
          title: info['title']?.toString() ?? 'La-Vie Conference',
          hostName: info['hostName']?.toString() ?? 'La-Vie Host',
          hostId: info['hostId']?.toString() ?? '',
          scheduledTime: schedDt,
          existingReminderMinutes: existingRem,
          isPermanent: isPerm,
        );
        return;
      }
    }

    final displayName = user?.displayName ?? 'Premium User';
    final prefs = await showPreJoinDialog(context);
    if (prefs == null || !mounted) return;

    bool isHost = info != null && user != null && info['hostId'] == user.uid;
    String? meetingTitle = info?['title']?.toString();

    if (user != null && info == null) {
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
          roomName: (e2eeKey != null && e2eeKey.isNotEmpty) ? '$code#$e2eeKey' : code,
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
        hostName: displayName,
        scheduledTime: DateTime.now(),
        status: 'active',
        meetingType: 'instant',
        requireApproval: prefs['requireApproval'] == true,
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
                  const SizedBox(height: 12),

                  // Option 4: Create Permanent Room (Always Open)
                  _buildMeetingOptionTile(
                    icon: Icons.all_inclusive_rounded,
                    iconColor: const Color(0xFFFFB300),
                    title: 'Create a permanent room',
                    subtitle: 'Always open evergreen link • No countdown timers',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showCreatePermanentRoomDialog();
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
    ScheduleMeetingDialog.show(context);
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
      hostName: displayName,
      scheduledTime: DateTime.now(),
      status: 'scheduled',
      meetingType: 'scheduled',
      notified: true,
    );
    await FirebaseFirestore.instance.collection('meetings').doc(roomId).set(meeting.toFirestore(), SetOptions(merge: true));

    final meetingLink = CalendarHelper.buildInviteLink(roomId, e2eeKey: e2eeKey);

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

  // ==========================================
  // CREATE PERMANENT ROOM DIALOG
  // ==========================================
  void _showCreatePermanentRoomDialog() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Premium User';
    final nameCtrl = TextEditingController(text: '$displayName\'s Permanent Room');
    bool requireApproval = false;

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
                      border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.4), width: 1.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB300).withOpacity(0.18),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.all_inclusive_rounded, color: Color(0xFFFFB300), size: 24),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Create Permanent Room',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Always open • Reusable evergreen link',
                                    style: TextStyle(
                                      color: Color(0xFFFFB300),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Room Name',
                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'e.g. Weekly Sync Room',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.06),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFFFB300)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.shield_outlined, color: Colors.white70, size: 20),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Require Host Approval',
                                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      'Guests must be admitted by host',
                                      style: TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: requireApproval,
                                activeColor: const Color(0xFFFFB300),
                                onChanged: (val) {
                                  setDialogState(() {
                                    requireApproval = val;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(dialogCtx),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Cancel', style: TextStyle(color: Colors.white54, fontSize: 14)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final roomTitle = nameCtrl.text.trim().isNotEmpty
                                      ? nameCtrl.text.trim()
                                      : '$displayName\'s Permanent Room';
                                  Navigator.pop(dialogCtx);
                                  await _createAndShowPermanentRoom(
                                    title: roomTitle,
                                    requireApproval: requireApproval,
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFB300),
                                  foregroundColor: const Color(0xFF070B19),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text(
                                  'Create Room',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
      },
    );
  }

  Future<void> _createAndShowPermanentRoom({
    required String title,
    required bool requireApproval,
  }) async {
    final rawCode = _generateRoomCode();
    final roomId = 'perm-$rawCode';
    final e2eeKey = _generateE2EEKey();
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Premium User';
    final hostId = user?.uid ?? '';

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('e2ee_$roomId', e2eeKey);

      final meeting = Meeting(
        id: roomId,
        title: title,
        roomId: roomId,
        hostId: hostId,
        hostName: displayName,
        scheduledTime: DateTime.now(),
        status: 'active',
        meetingType: 'permanent',
        isPermanent: true,
        requireApproval: requireApproval,
        notified: true,
      );
      await FirebaseFirestore.instance.collection('meetings').doc(roomId).set(
        meeting.toFirestore(),
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error saving permanent room: $e');
    }

    final meetingLink = CalendarHelper.buildInviteLink(roomId, e2eeKey: e2eeKey);

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
                  border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.4), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB300).withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.all_inclusive_rounded, color: Color(0xFFFFB300), size: 30),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Permanent Room Ready!',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: const TextStyle(color: Color(0xFFFFB300), fontSize: 14, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This evergreen room is always open and never expires. Anyone with this link or code can join anytime until you delete the room.',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, height: 1.4),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Room Code: $roomId',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  meetingLink,
                                  style: const TextStyle(color: Color(0xFFFFB300), fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, color: Color(0xFFFFB300), size: 20),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: meetingLink));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Permanent link copied to clipboard!'),
                                  backgroundColor: Color(0xFFFFB300),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Share.share('Join my permanent meeting room on La-Vie Conference:\n$meetingLink\n\nRoom ID: $roomId\n(Always open • Join anytime)');
                            },
                            icon: const Icon(Icons.share, size: 16),
                            label: const Text('Share'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white.withOpacity(0.2)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(dialogCtx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => VideoRoomScreen(
                                    roomName: roomId,
                                    meetingTitle: title,
                                    participantName: displayName,
                                    initialAudioOn: true,
                                    initialVideoOn: true,
                                    isHost: true,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.login, size: 16),
                            label: const Text('Enter Room Now', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFB300),
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
                            onPressed: () {
                              final raw = _codeController.text.trim();
                              if (raw.isNotEmpty) {
                                Navigator.pop(dialogContext);
                                _joinMeetingByRawInput(raw);
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
                            child: ClipOval(
                              child: Builder(
                                builder: (context) {
                                  final user = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;
                                  final avatarUrl = _cachedAvatarUrl ?? _normalizeAvatarUrl(user?.photoURL);
                                  final initialWidget = Center(
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  );
                                  if (avatarUrl == null || avatarUrl.isEmpty) {
                                    return initialWidget;
                                  }
                                  return Image.network(
                                    avatarUrl,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => initialWidget,
                                  );
                                },
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
                            
                            // StreamBuilder for Upcoming & Invited Meetings
                            StreamBuilder<List<Meeting>>(
                              stream: Meeting.streamUserMeetings(FirebaseAuth.instance.currentUser?.uid),
                              builder: (context, snapshot) {
                                if (snapshot.hasError) {
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

                                final allMeetings = snapshot.data ?? [];
                                final topMeetings = allMeetings.take(3).toList();
                                if (topMeetings.isEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    child: Text(
                                      'No upcoming meetings.',
                                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                                    ),
                                  );
                                }

                                final currentUid = FirebaseAuth.instance.currentUser?.uid;
                                return Column(
                                  children: topMeetings.map((meeting) {
                                    final formattedTime = DateFormat('MMM d, yyyy • h:mm a').format(meeting.scheduledTime);
                                    final bool isHost = meeting.hostId == currentUid || meeting.role == 'host';
                                    final bool isFuture = meeting.scheduledTime.isAfter(DateTime.now());
                                    final displayHost = meeting.hostName.isNotEmpty
                                        ? meeting.hostName
                                        : (isHost ? (FirebaseAuth.instance.currentUser?.displayName ?? 'You') : 'La-Vie Host');

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
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        meeting.title,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: isHost
                                                            ? const Color(0xFF00E5FF).withOpacity(0.14)
                                                            : const Color(0xFF00FFA3).withOpacity(0.14),
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: Text(
                                                        isHost ? 'HOST' : 'INVITED',
                                                        style: TextStyle(
                                                          color: isHost ? const Color(0xFF00E5FF) : const Color(0xFF00FFA3),
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  if (isFuture || meeting.isPermanent)
                                                    InkWell(
                                                      onTap: () async {
                                                        final sp = await SharedPreferences.getInstance();
                                                        final key = sp.getString('e2ee_${meeting.roomId}');
                                                        if (context.mounted) {
                                                          UpcomingMeetingInviteSheet.show(
                                                            context,
                                                            roomId: meeting.roomId,
                                                            e2eeKey: key,
                                                            title: meeting.title,
                                                            hostName: displayHost,
                                                            hostId: meeting.hostId,
                                                            scheduledTime: meeting.scheduledTime,
                                                            existingReminderMinutes: meeting.hostReminderMinutes,
                                                            isPermanent: meeting.isPermanent,
                                                          );
                                                        }
                                                      },
                                                      child: Padding(
                                                        padding: const EdgeInsets.all(4.0),
                                                        child: Icon(
                                                          meeting.isPermanent ? Icons.all_inclusive_rounded : Icons.notifications_active_outlined,
                                                          color: meeting.isPermanent ? const Color(0xFFFFB300) : const Color(0xFF00FFA3),
                                                          size: 20,
                                                        ),
                                                      ),
                                                    ),
                                                  if (!meeting.isPermanent) ...[
                                                    const SizedBox(width: 6),
                                                    InkWell(
                                                      onTap: () async {
                                                        final sp = await SharedPreferences.getInstance();
                                                        final key = sp.getString('e2ee_${meeting.roomId}');
                                                        await CalendarHelper.addMeetingToGoogleCalendar(
                                                          title: meeting.title,
                                                          startTime: meeting.scheduledTime,
                                                          roomId: meeting.roomId,
                                                          e2eeKey: key,
                                                          hostName: displayHost,
                                                          reminderMinutes: meeting.hostReminderMinutes,
                                                          allowInteractiveFallback: true,
                                                        );
                                                      },
                                                      child: Padding(
                                                        padding: const EdgeInsets.all(4.0),
                                                        child: Icon(Icons.calendar_today, color: Colors.white.withOpacity(0.75), size: 18),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              )
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          if (meeting.isPermanent)
                                            const Row(
                                              children: [
                                                Icon(Icons.all_inclusive_rounded, color: Color(0xFFFFB300), size: 14),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Permanent Room • Always Open',
                                                  style: TextStyle(
                                                    color: Color(0xFFFFB300),
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            )
                                          else
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
                                                  InkWell(
                                                    onTap: () async {
                                                      final sp = await SharedPreferences.getInstance();
                                                      final key = sp.getString('e2ee_${meeting.roomId}');
                                                      final url = CalendarHelper.buildInviteLink(meeting.roomId, e2eeKey: key);
                                                      Share.share('Join "${meeting.title}" on La-Vie Conference ($formattedTime):\n$url');
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white.withOpacity(0.1),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: const Icon(Icons.share, color: Colors.white, size: 18),
                                                    ),
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
                                                            isHost: isHost,
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
