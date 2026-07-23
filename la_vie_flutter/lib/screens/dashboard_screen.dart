import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/meeting.dart';
import 'package:intl/intl.dart';
import 'video_room_screen.dart';
import 'pre_join_dialog.dart';
import 'notifications_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _generateRoomCode() {
    return 'la-vie-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
  }

  void _startNewMeeting() async {
    final roomId = _generateRoomCode();
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Premium User';
    
    final prefs = await showPreJoinDialog(context);
    if (prefs == null) return;

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoRoomScreen(
          roomName: roomId,
          participantName: displayName,
          initialAudioOn: prefs['audio'] ?? true,
          initialVideoOn: prefs['video'] ?? true,
          isHost: true,
        ),
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
                                if (user != null) {
                                  try {
                                    final query = await FirebaseFirestore.instance.collection('meetings').where('roomId', isEqualTo: code).limit(1).get();
                                    if (query.docs.isNotEmpty) {
                                      isHost = query.docs.first.data()['hostId'] == user.uid;
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
                if (FirebaseAuth.instance.currentUser != null)
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
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => VideoRoomScreen(
                                          roomName: activeRoom,
                                          participantName: FirebaseAuth.instance.currentUser?.displayName ?? 'User',
                                          initialAudioOn: prefs['audio'] ?? true,
                                          initialVideoOn: prefs['video'] ?? true,
                                          isHost: false, // Assume guest for rejoin
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
                
                // Hero Text
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFFE0FFFF), Color(0xFF00E5FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: const Text(
                          'PREMIUM\nVIDEO\nMEETINGS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Experience seamless, high-definition\nvisual communication with unparalleled\nprivacy and luxury.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),

                // Meeting Action Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    children: [
                      // New Meeting Button
                      GestureDetector(
                        onTap: _startNewMeeting,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF5C00FF), Color(0xFF00E5FF)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E5FF).withOpacity(0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'NEW MEETING',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.videocam, color: Colors.white, size: 20),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Join Meeting Button
                      GestureDetector(
                        onTap: _showJoinMeetingDialog,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: Colors.white.withOpacity(0.05),
                            border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5), width: 1.5),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'JOIN WITH CODE',
                                style: TextStyle(
                                  color: Color(0xFF00E5FF),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.keyboard_alt_outlined, color: Color(0xFF00E5FF), size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Main Interactive Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                        ),
                        child: Column(
                          children: [
                            // User Info Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFF1E1E30),
                                        border: Border.all(color: const Color(0xFF00E5FF), width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF00E5FF).withOpacity(0.5),
                                            blurRadius: 12,
                                            spreadRadius: 2,
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
                                    const SizedBox(width: 16),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Good Morning,',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.7),
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          greetingName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      const Icon(Icons.notifications_none, color: Colors.white, size: 20),
                                      Positioned(
                                        top: -2,
                                        right: 2,
                                        child: Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFF2E93),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 24),
                            
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
