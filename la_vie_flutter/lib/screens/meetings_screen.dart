import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/meeting.dart';
import 'video_room_screen.dart';
import 'pre_join_dialog.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import 'package:share_plus/share_plus.dart';

class MeetingsScreen extends StatelessWidget {
  const MeetingsScreen({Key? key}) : super(key: key);

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
          'description': 'Join La-Vie Conference:\\n$meetingLink\\n\\nThis meeting is End-to-End Encrypted.',
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

  void _showScheduleMeetingDialog(BuildContext context) {
    final TextEditingController titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
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
                        const Icon(Icons.event_available, color: Color(0xFF00E5FF), size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Schedule Meeting',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: titleController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Meeting Title',
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
                        const SizedBox(height: 16),
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
                                  if (pickedDate != null && pickedDate != selectedDate) {
                                    setState(() {
                                      selectedDate = pickedDate;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.calendar_today, size: 18),
                                label: Text(DateFormat('MMM d').format(selectedDate)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(0.1),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final TimeOfDay? pickedTime = await showTimePicker(
                                    context: context,
                                    initialTime: selectedTime,
                                  );
                                  if (pickedTime != null && pickedTime != selectedTime) {
                                    setState(() {
                                      selectedTime = pickedTime;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.access_time, size: 18),
                                label: Text(selectedTime.format(context)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(0.1),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(context),
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
                                  
                                  // Save key locally
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

                                  final reminderTime = scheduledDateTime.subtract(const Duration(minutes: 10));
                                  NotificationService().scheduleMeetingReminder(
                                    id: notificationId + 1,
                                    title: 'Upcoming Meeting: $title',
                                    body: 'Starts in 10 minutes',
                                    scheduledDate: reminderTime,
                                  );

                                  // Attempt to add to calendar
                                  final success = await _createGoogleCalendarEvent(title, scheduledDateTime, roomId, e2eeKey);
                                  
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(success ? 'Scheduled & added to Google Calendar' : 'Meeting scheduled')),
                                    );
                                  }

                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E5FF),
                                  foregroundColor: const Color(0xFF070B19),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 0,
                                ),
                                child: const Text('Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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

  Future<void> _deleteMeeting(BuildContext context, Meeting meeting) async {
    final bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF070B19),
        title: const Text('Delete Meeting', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this meeting?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      try {
        await FirebaseFirestore.instance.collection('meetings').doc(meeting.id).delete();
        await NotificationService().cancelNotification(meeting.roomId.hashCode);
        await NotificationService().cancelNotification(meeting.roomId.hashCode + 1);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meeting deleted.')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  void _showEditMeetingDialog(BuildContext context, Meeting meeting) {
    final TextEditingController titleController = TextEditingController(text: meeting.title);
    DateTime selectedDate = meeting.scheduledTime;
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(meeting.scheduledTime);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
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
                        const Icon(Icons.edit, color: Color(0xFF00E5FF), size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Edit Meeting',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: titleController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Meeting Title',
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
                        const SizedBox(height: 16),
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
                                  if (pickedDate != null && pickedDate != selectedDate) {
                                    setState(() {
                                      selectedDate = pickedDate;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.calendar_today, size: 18),
                                label: Text(DateFormat('MMM d').format(selectedDate)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(0.1),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final TimeOfDay? pickedTime = await showTimePicker(
                                    context: context,
                                    initialTime: selectedTime,
                                  );
                                  if (pickedTime != null && pickedTime != selectedTime) {
                                    setState(() {
                                      selectedTime = pickedTime;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.access_time, size: 18),
                                label: Text(selectedTime.format(context)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(0.1),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(context),
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
                                  final title = titleController.text.trim();
                                  if (title.isEmpty) return;

                                  final scheduledDateTime = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    selectedTime.hour,
                                    selectedTime.minute,
                                  );

                                  await FirebaseFirestore.instance.collection('meetings').doc(meeting.id).update({
                                    'title': title,
                                    'scheduledTime': scheduledDateTime.toIso8601String(),
                                  });

                                  final notificationId = meeting.roomId.hashCode;
                                  
                                  await NotificationService().cancelNotification(notificationId + 1);

                                  final reminderTime = scheduledDateTime.subtract(const Duration(minutes: 10));
                                  NotificationService().scheduleMeetingReminder(
                                    id: notificationId + 1,
                                    title: 'Upcoming Meeting: $title',
                                    body: 'Starts in 10 minutes',
                                    scheduledDate: reminderTime,
                                  );

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meeting updated')));
                                    Navigator.pop(context);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E5FF),
                                  foregroundColor: const Color(0xFF070B19),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 0,
                                ),
                                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Meetings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined, color: Color(0xFF00E5FF)),
            onPressed: () => _showScheduleMeetingDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: 50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
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
          
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('meetings')
                .where('hostId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                .orderBy('scheduledTime')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final errStr = snapshot.error.toString();
                if (errStr.contains('failed-precondition') || errStr.contains('requires an index')) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.0),
                      child: Text(
                        'Database index required. Please check your console logs for the Firebase index creation link.',
                        style: TextStyle(color: Colors.amber, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return const Center(
                  child: Text(
                    'Error loading meetings. Please try again.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 14),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No upcoming meetings.',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final meeting = Meeting.fromFirestore(docs[index]);
                  return _buildMeetingCard(context, meeting);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingCard(BuildContext context, Meeting meeting) {
    final now = DateTime.now();
    final isLive = meeting.scheduledTime.isBefore(now.add(const Duration(minutes: 15))) && 
                   meeting.scheduledTime.isAfter(now.subtract(const Duration(minutes: 60)));
    
    final formattedDate = DateFormat('MMM d, yyyy').format(meeting.scheduledTime);
    final formattedTime = DateFormat('h:mm a').format(meeting.scheduledTime);
    final color = isLive ? const Color(0xFF00E5FF) : const Color(0xFF5C00FF);
    
    final user = FirebaseAuth.instance.currentUser;
    final hostName = user?.displayName ?? 'Premium User';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isLive 
                            ? Colors.redAccent.withOpacity(0.2)
                            : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isLive ? Colors.redAccent : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (isLive) ...[
                            const Icon(Icons.circle, color: Colors.redAccent, size: 8),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            isLive ? 'LIVE NOW' : formattedDate,
                            style: TextStyle(
                              color: isLive ? Colors.redAccent : Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white54),
                      color: const Color(0xFF1E243A),
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'share',
                          child: ListTile(
                            leading: Icon(Icons.share, color: Colors.white70),
                            title: Text('Share', style: TextStyle(color: Colors.white)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit, color: Colors.white70),
                            title: Text('Edit', style: TextStyle(color: Colors.white)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete, color: Colors.redAccent),
                            title: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                      onSelected: (String value) {
                        if (value == 'delete') {
                          _deleteMeeting(context, meeting);
                        } else if (value == 'edit') {
                          _showEditMeetingDialog(context, meeting);
                        } else if (value == 'share') {
                          final url = 'https://la-vie.lifechangerstouch.org/static/index.html?room=${meeting.roomId}';
                          Share.share('Join my La-Vie Premium meeting via this link: $url');
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  meeting.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time, color: color, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      formattedTime,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: color.withOpacity(0.2),
                          child: Text(
                            hostName.isNotEmpty ? hostName.substring(0, 1).toUpperCase() : 'U',
                            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Host', style: TextStyle(color: Colors.white38, fontSize: 10)),
                            Text(hostName, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final prefs = await showPreJoinDialog(context);
                        if (prefs == null) return;
                        if (!context.mounted) return;
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isLive ? color : Colors.white.withOpacity(0.1),
                        foregroundColor: isLive ? const Color(0xFF070B19) : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: Text(
                        'Join Now',
                        style: const TextStyle(fontWeight: FontWeight.bold),
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
  }
}
