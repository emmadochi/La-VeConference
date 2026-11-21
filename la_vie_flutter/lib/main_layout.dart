import 'dart:ui';
import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'screens/meetings_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/profile_screen.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'screens/video_room_screen.dart';
import 'screens/notifications_screen.dart';
import 'widgets/post_meeting_feedback_sheet.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/notification_service.dart';
import 'services/lcm_bridge.dart';
import 'api_service.dart';
import 'widgets/upcoming_meeting_invite_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({Key? key}) : super(key: key);

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initFCM();
    _initDeepLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LcmBridge.checkForUpdates(
        context,
        packageName: 'org.lifechangerstouch.lavie',
        currentVersion: '1.0.1',
      );
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _initDeepLinks() {
    _appLinks = AppLinks();

    // Handle incoming links when the app is already open
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });

    // Handle initial link if the app was opened via link
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    String? roomId = uri.queryParameters['room'];

    // Also support paths like /meeting/la-vie-123 or /room/la-vie-123 or /join/la-vie-123
    if (roomId == null || roomId.isEmpty) {
      final segments = uri.pathSegments;
      if (segments.length >= 2 && ['meeting', 'room', 'join', 'conf'].contains(segments[0])) {
        roomId = segments[1];
      }
    }

    if (roomId != null && roomId.isNotEmpty) {
      String cleanRoomId = roomId.split('#').first.trim();
      String? e2eeKey = uri.fragment.isNotEmpty
          ? uri.fragment.trim()
          : (roomId.contains('#') ? roomId.split('#').last.trim() : null);

      if (e2eeKey != null && e2eeKey.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('e2ee_$cleanRoomId', e2eeKey);
        } catch (_) {}
      }

      final info = await ApiService.fetchPublicMeetingInfo(cleanRoomId);
      if (!mounted) return;

      if (info != null && info['isFutureScheduled'] == true && info['scheduledTimeTs'] != null) {
        final ts = int.tryParse(info['scheduledTimeTs'].toString()) ?? 0;
        if (ts > 0) {
          final schedDt = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toLocal();
          final existingRem = info['myReminder'] is Map ? (info['myReminder']['reminderMinutes'] as int?) : null;
          await UpcomingMeetingInviteSheet.show(
            context,
            roomId: cleanRoomId,
            e2eeKey: e2eeKey,
            title: info['title']?.toString() ?? 'La-Vie Conference',
            hostName: info['hostName']?.toString() ?? 'La-Vie Host',
            hostId: info['hostId']?.toString() ?? '',
            scheduledTime: schedDt,
            existingReminderMinutes: existingRem,
          );
          return;
        }
      }

      String fullRoomIdentifier = cleanRoomId;
      if (e2eeKey != null && e2eeKey.isNotEmpty) {
        fullRoomIdentifier = '$cleanRoomId#$e2eeKey';
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      final userName = currentUser?.displayName ?? 'Guest';
      final isHost = info != null && currentUser != null && info['hostId'] == currentUser.uid;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoRoomScreen(
            roomName: fullRoomIdentifier,
            meetingTitle: info?['title']?.toString(),
            participantName: userName,
            isHost: isHost,
          ),
        ),
      );
    }
  }

  Future<void> _initFCM() async {
    if (Firebase.apps.isEmpty) return;
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await messaging.getToken();
        if (token != null) {
          final user = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;
          if (user != null) {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
              {'fcmToken': token},
              SetOptions(merge: true),
            );
          }
        }

        // Foreground push display
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final notif = message.notification;
          if (notif != null) {
            final action = message.data['action']?.toString() ?? '';
            final roomId = message.data['roomId']?.toString() ?? '';
            String? payload;
            if (action == 'open_room' && roomId.isNotEmpty) {
              payload = 'open_room:$roomId';
            } else if (action == 'open_notes') {
              payload = 'open_notes';
            }
            NotificationService().showImmediateNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: notif.title ?? 'La-Vie Alert',
              body: notif.body ?? '',
              payload: payload,
            );
          }
        });

        void handleNotificationData(Map<String, dynamic> data) {
          final action = data['action'];
          final roomId = data['roomId'];
          if (action == 'open_room' && roomId != null && roomId.toString().isNotEmpty) {
            final user = FirebaseAuth.instance.currentUser;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoRoomScreen(
                  roomName: roomId.toString(),
                  participantName: user?.displayName ?? 'Participant',
                ),
              ),
            );
          } else if (action == 'open_notes') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NotificationsScreen(),
              ),
            );
          } else if (action == 'open_feedback' && roomId != null && roomId.toString().isNotEmpty) {
            PostMeetingFeedbackSheet.show(
              context,
              roomId: roomId.toString(),
              meetingTitle: data['title'] ?? 'Meeting ${roomId.toString()}',
            );
          }
        }

        // Background/Quit push tap routing
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          handleNotificationData(message.data);
        });

        // Terminated state push tap check
        FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
          if (message != null) {
            handleNotificationData(message.data);
          }
        });
      }
    } catch (e) {
      debugPrint("FCM initialization skipped: $e");
    }
  }

  final List<Widget> _screens = [
    const DashboardScreen(),
    const MeetingsScreen(),
    const CalendarScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final user = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFF070B19),
        body: Row(
          children: [
            // Desktop Glassmorphic Sidebar Navigation
            Container(
              width: 250,
              decoration: BoxDecoration(
                color: const Color(0xFF0B1021),
                border: Border(
                  right: BorderSide(
                    color: Colors.white.withOpacity(0.08),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  // Logo & App Name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/logoI.png',
                          width: 36,
                          height: 36,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.videocam, color: Colors.black, size: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'La-Vie',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Nav Links
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        _buildNavItem(0, Icons.home_rounded, 'Home'),
                        _buildNavItem(1, Icons.videocam_rounded, 'Meetings'),
                        _buildNavItem(2, Icons.calendar_month_rounded, 'Calendar'),
                        _buildNavItem(3, Icons.person_rounded, 'Profile'),
                      ],
                    ),
                  ),
                  // User Profile Bar
                  Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF00E5FF),
                          child: Text(
                            (user?.displayName?.isNotEmpty == true)
                                ? user!.displayName![0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.displayName ?? 'Guest User',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                user?.email ?? 'Logged In',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Right Content Area
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF070B19).withOpacity(0.85),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.05),
                  width: 1,
                ),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              backgroundColor: Colors.transparent,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: const Color(0xFF00E5FF),
              unselectedItemColor: Colors.white38,
              elevation: 0,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_filled),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.videocam_outlined),
                  label: 'Meetings',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.calendar_today_outlined),
                  label: 'Calendar',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.account_circle_outlined),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = _currentIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: () => setState(() => _currentIndex = index),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00E5FF).withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: isSelected
                ? Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4), width: 1)
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF00E5FF) : Colors.white60,
                size: 22,
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
