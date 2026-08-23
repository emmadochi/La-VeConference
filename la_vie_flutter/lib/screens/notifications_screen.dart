import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Notes for "$roomId" are available in your Dashboard.'),
          backgroundColor: const Color(0xFF00E5FF),
        ),
      );
    }
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
