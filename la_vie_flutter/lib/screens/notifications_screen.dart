import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../api_service.dart';
import 'video_room_screen.dart';
import 'account_details_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _pushEnabled = true;
  bool _emailEnabled = false;
  bool _remindersEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _pushEnabled = prefs.getBool('pushEnabled') ?? true;
        _emailEnabled = prefs.getBool('emailEnabled') ?? false;
        _remindersEnabled = prefs.getBool('remindersEnabled') ?? true;
      });
    }
  }

  Future<void> _savePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  String _formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return 'Recently';
    DateTime dt;
    if (timestamp is Timestamp) {
      dt = timestamp.toDate();
    } else if (timestamp is String) {
      try {
        dt = DateTime.parse(timestamp);
      } catch (_) {
        return 'Recently';
      }
    } else {
      return 'Recently';
    }

    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _handleNotificationAction(Map<String, dynamic> data) {
    final action = data['action'] ?? '';
    final roomId = data['roomId'] ?? '';
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName ?? 'Participant';

    if (action == 'open_room' && roomId.toString().isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoRoomScreen(
            roomName: roomId.toString(),
            participantName: userName,
          ),
        ),
      );
    } else if (action == 'open_upgrade') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const AccountDetailsScreen(),
        ),
      );
    } else if (action == 'open_notes') {
      _showMeetingRecapDialog(roomId.toString(), data);
    }
  }

  void _showMeetingRecapDialog(String roomId, Map<String, dynamic> notifData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF070B19),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return _MeetingRecapSheet(
          roomId: roomId,
          notifData: notifData,
        );
      },
    );
  }

  Future<void> _markAllAsRead(String uid) async {
    try {
      final notifs = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in notifs.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read'),
            backgroundColor: Color(0xFF00E5FF),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  void _showPreferencesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFF0D1117),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: Color(0xFF00E5FF), width: 1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Notification Settings',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Customize alert channels and reminder timings.',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  _buildToggleOption(
                    title: 'Push Notifications',
                    subtitle: 'Receive alerts when broadcasts & meetings start.',
                    value: _pushEnabled,
                    onChanged: (val) {
                      setSheetState(() => _pushEnabled = val);
                      setState(() => _pushEnabled = val);
                      _savePreference('pushEnabled', val);
                    },
                    iconColor: const Color(0xFF00E5FF),
                    icon: Icons.notifications_active_rounded,
                  ),
                  const SizedBox(height: 14),
                  _buildToggleOption(
                    title: '15-Minute Reminders',
                    subtitle: 'Get notified before your scheduled meetings start.',
                    value: _remindersEnabled,
                    onChanged: (val) {
                      setSheetState(() => _remindersEnabled = val);
                      setState(() => _remindersEnabled = val);
                      _savePreference('remindersEnabled', val);
                    },
                    iconColor: const Color(0xFF5C00FF),
                    icon: Icons.access_alarm_rounded,
                  ),
                  const SizedBox(height: 14),
                  _buildToggleOption(
                    title: 'Email Updates',
                    subtitle: 'Receive weekly ministry digests and invitations.',
                    value: _emailEnabled,
                    onChanged: (val) {
                      setSheetState(() => _emailEnabled = val);
                      setState(() => _emailEnabled = val);
                      _savePreference('emailEnabled', val);
                    },
                    iconColor: const Color(0xFFB524D3),
                    icon: Icons.email_rounded,
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Notifications', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (uid != null)
            IconButton(
              icon: const Icon(Icons.done_all_rounded, color: Color(0xFF00E5FF)),
              tooltip: 'Mark All as Read',
              onPressed: () => _markAllAsRead(uid),
            ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Colors.white70),
            tooltip: 'Notification Preferences',
            onPressed: _showPreferencesSheet,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [const Color(0xFF5C00FF).withOpacity(0.15), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [const Color(0xFF00E5FF).withOpacity(0.1), Colors.transparent],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: uid == null
                ? const Center(
                    child: Text('Sign in to view your notifications.', style: TextStyle(color: Colors.white54)),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('notifications')
                        .orderBy('createdAt', descending: true)
                        .limit(50)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.04),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                                ),
                                child: const Icon(Icons.notifications_none_rounded, size: 54, color: Color(0xFF00E5FF)),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                "You're All Caught Up!",
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Meeting alerts and follow-up notes will appear here.',
                                style: TextStyle(color: Colors.white54, fontSize: 14),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        itemCount: docs.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final title = data['title'] ?? 'Notification';
                          final body = data['body'] ?? '';
                          final isRead = data['read'] == true;
                          final type = data['type'] ?? 'general';
                          final action = data['action'] ?? '';
                          final timeStr = _formatTimeAgo(data['createdAt']);

                          Color iconBg;
                          IconData iconData;
                          String? actionLabel;

                          if (type == 'meeting_reminder') {
                            iconBg = const Color(0xFF00E5FF);
                            iconData = Icons.videocam_rounded;
                            actionLabel = 'Join Room';
                          } else if (type == 'meeting_followup') {
                            iconBg = const Color(0xFF9B51E0);
                            iconData = Icons.description_rounded;
                            actionLabel = 'View Notes';
                          } else if (type == 'upgrade_offer') {
                            iconBg = const Color(0xFFFFB800);
                            iconData = Icons.workspace_premium_rounded;
                            actionLabel = 'Upgrade Plan';
                          } else if (type == 'announcement') {
                            iconBg = const Color(0xFFFF2E93);
                            iconData = Icons.campaign_rounded;
                            actionLabel = action == 'open_room' ? 'Join Now' : null;
                          } else {
                            iconBg = const Color(0xFF00E5FF);
                            iconData = Icons.notifications_rounded;
                          }

                          return Dismissible(
                            key: Key(doc.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            ),
                            onDismissed: (_) {
                              doc.reference.delete();
                            },
                            child: GestureDetector(
                              onTap: () {
                                if (!isRead) {
                                  doc.reference.update({'read': true});
                                }
                                _handleNotificationAction(data);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isRead ? Colors.white.withOpacity(0.03) : const Color(0xFF00E5FF).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isRead ? Colors.white.withOpacity(0.08) : const Color(0xFF00E5FF).withOpacity(0.3),
                                        width: isRead ? 1 : 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: iconBg.withOpacity(0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(iconData, color: iconBg, size: 20),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      title,
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 15,
                                                        fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    timeStr,
                                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                body,
                                                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                                              ),
                                              if (actionLabel != null) ...[
                                                const SizedBox(height: 10),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: iconBg.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: iconBg.withOpacity(0.4)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        actionLabel,
                                                        style: TextStyle(color: iconBg, fontSize: 12, fontWeight: FontWeight.bold),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Icon(Icons.arrow_forward_rounded, color: iconBg, size: 14),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (!isRead) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            width: 8,
                                            height: 8,
                                            margin: const EdgeInsets.only(top: 6),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF00E5FF),
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(color: Color(0xFF00E5FF), blurRadius: 6, spreadRadius: 1),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
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
  }

  Widget _buildToggleOption({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color iconColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF00E5FF),
            activeTrackColor: const Color(0xFF00E5FF).withOpacity(0.5),
            inactiveThumbColor: Colors.white54,
            inactiveTrackColor: Colors.white12,
          ),
        ],
      ),
    );
  }
}

class _MeetingRecapSheet extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic> notifData;

  const _MeetingRecapSheet({
    Key? key,
    required this.roomId,
    required this.notifData,
  }) : super(key: key);

  @override
  State<_MeetingRecapSheet> createState() => _MeetingRecapSheetState();
}

class _MeetingRecapSheetState extends State<_MeetingRecapSheet> {
  int _selectedTab = 0; // 0: Executive Summary, 1: Key Takeaways, 2: Action Items, 3: Transcript
  bool _isLoading = false;
  Map<String, dynamic>? _aiSummary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    if (widget.notifData['ai_summary'] is Map) {
      setState(() {
        _aiSummary = Map<String, dynamic>.from(widget.notifData['ai_summary']);
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('meetings').doc(widget.roomId).get();
      if (doc.exists && doc.data()?['ai_summary'] is Map) {
        if (mounted) {
          setState(() {
            _aiSummary = Map<String, dynamic>.from(doc.data()!['ai_summary']);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _generateSummary({String? customNotes}) async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.generateMeetingSummary(
        roomId: widget.roomId,
        title: widget.notifData['title'] ?? 'Meeting ${widget.roomId}',
        transcriptText: customNotes,
      );
      if (mounted && res['summary'] is Map) {
        setState(() {
          _aiSummary = Map<String, dynamic>.from(res['summary']);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI Generation Notice: $e'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCustomNotesPrompt() async {
    final controller = TextEditingController();
    final customNotes = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
        ),
        title: Row(
          children: const [
            Icon(Icons.auto_awesome, color: Color(0xFF00FFA3), size: 22),
            SizedBox(width: 8),
            Text('Expand Bullet Points', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Jot down any quick bullet points or decisions from your meeting. Gemini will expand them into executive minutes & action items.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. Budget approved, launch set for Dec, Sarah to finalize design by Friday...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            icon: const Icon(Icons.bolt, size: 16),
            label: const Text('Generate with AI', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FFA3),
              foregroundColor: const Color(0xFF070B19),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (customNotes != null && customNotes.isNotEmpty) {
      _generateSummary(customNotes: customNotes);
    }
  }

  String _buildMarkdownMinutes() {
    final exec = _aiSummary?['executive_summary'] ?? widget.notifData['body'] ?? '';
    final points = (_aiSummary?['key_points'] as List?)?.map((e) => '- $e').join('\n') ?? '';
    final actions = (_aiSummary?['action_items'] as List?)?.map((e) => '- [ ] $e').join('\n') ?? '';
    final transcript = _aiSummary?['transcript'] ?? '';

    return '''# La-Vie Meeting Minutes & Summary
Room: ${widget.roomId}
Generated: ${DateTime.now().toLocal().toString().split('.')[0]}

## 📝 Executive Summary
$exec

## 💡 Key Discussion Takeaways
${points.isNotEmpty ? points : 'N/A'}

## 🎯 Action Items & Next Steps
${actions.isNotEmpty ? actions : 'N/A'}

## 📄 Discussion Notes & Transcript
${transcript.isNotEmpty ? transcript : 'N/A'}

---
*Generated with La-Vie Premium Conference*
Host your next meeting with HD audio, video, and automated AI summary notes: https://la-vie.lifechangerstouch.org
''';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.notifData['title'] ?? 'Meeting Concluded';
    final fallbackBody = widget.notifData['body'] ?? 'Thank you for attending!';
    
    final execSummary = _aiSummary?['executive_summary'] as String? ?? fallbackBody;
    final keyPoints = (_aiSummary?['key_points'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final actionItems = (_aiSummary?['action_items'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final transcript = _aiSummary?['transcript'] as String? ?? '';

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9B51E0), Color(0xFF00E5FF)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'AI Meeting Summary',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                            ),
                            child: const Text('GEMINI AI', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('$title • Room: ${widget.roomId}', style: const TextStyle(color: Colors.white60, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Segmented Tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTabPill(0, 'Summary', Icons.description_outlined),
                  const SizedBox(width: 8),
                  _buildTabPill(1, 'Takeaways', Icons.lightbulb_outline),
                  const SizedBox(width: 8),
                  _buildTabPill(2, 'Action Items', Icons.check_circle_outline),
                  const SizedBox(width: 8),
                  _buildTabPill(3, 'Transcript', Icons.notes_rounded),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Tab Content Box
            Flexible(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: SingleChildScrollView(
                  child: _buildSelectedTabContent(
                    execSummary: execSummary,
                    keyPoints: keyPoints,
                    actionItems: actionItems,
                    transcript: transcript,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Actions
            if (_aiSummary == null) ...[
              SizedBox(
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9B51E0), Color(0xFF00E5FF)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ElevatedButton.icon(
                    icon: _isLoading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                    label: Text(
                      _isLoading ? 'Generating Summary with Gemini...' : 'Generate AI Minutes (Auto)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _isLoading ? null : () => _generateSummary(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Expand My Bullet Points with AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00FFA3),
                    side: const BorderSide(color: Color(0xFF00FFA3)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _isLoading ? null : _showCustomNotesPrompt,
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.copy_rounded, color: Colors.black, size: 18),
                    label: const Text('Copy Minutes', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _buildMarkdownMinutes()));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✨ Full formatted AI meeting minutes copied!'),
                          backgroundColor: Color(0xFF00C853),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share_rounded, color: Color(0xFF00E5FF), size: 18),
                    label: const Text('Share Recap', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Share.share(
                        _buildMarkdownMinutes(),
                        subject: 'La-Vie Meeting Minutes: ${widget.roomId}',
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPill(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00E5FF) : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.black : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTabContent({
    required String execSummary,
    required List<String> keyPoints,
    required List<String> actionItems,
    required String transcript,
  }) {
    switch (_selectedTab) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.description_rounded, color: Color(0xFF00E5FF), size: 18),
                SizedBox(width: 8),
                Text('Executive Summary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              execSummary,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
            ),
          ],
        );
      case 1:
        if (keyPoints.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No discussion takeaways extracted yet. Tap Generate AI Minutes below.', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb_rounded, color: Color(0xFFFFB300), size: 18),
                SizedBox(width: 8),
                Text('Key Takeaways & Decisions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            ...keyPoints.map((point) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          point,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        );
      case 2:
        if (actionItems.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No assigned action items extracted yet.', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.task_alt_rounded, color: Color(0xFF00FFA3), size: 18),
                SizedBox(width: 8),
                Text('Action Items & Next Steps', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            ...actionItems.map((action) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FFA3).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_box_outlined, color: Color(0xFF00FFA3), size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            action,
                            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        );
      case 3:
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notes_rounded, color: Color(0xFF9B51E0), size: 18),
                SizedBox(width: 8),
                Text('Transcript & Minutes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              transcript.isNotEmpty ? transcript : 'Session transcript archived.',
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.6, fontFamily: 'monospace'),
            ),
          ],
        );
    }
  }
}
