import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/meeting.dart';
import '../api_service.dart';
import '../services/calendar_helper.dart';
import '../widgets/schedule_meeting_dialog.dart';
import '../widgets/upcoming_meeting_invite_sheet.dart';
import 'video_room_screen.dart';
import 'pre_join_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import 'package:share_plus/share_plus.dart';

class MeetingsScreen extends StatelessWidget {
  const MeetingsScreen({Key? key}) : super(key: key);

  void _showScheduleMeetingDialog(BuildContext context) {
    ScheduleMeetingDialog.show(context);
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
                                    'scheduledTime': scheduledDateTime.toUtc().toIso8601String(),
                                    'status': 'scheduled',
                                    'meetingType': 'scheduled',
                                    'notified': false,
                                  });

                                  final notificationId = meeting.roomId.hashCode;
                                  await NotificationService().cancelNotification(notificationId + 1);

                                  final leadMins = meeting.hostReminderMinutes;
                                  final reminderTime = scheduledDateTime.subtract(Duration(minutes: leadMins));
                                  NotificationService().scheduleMeetingReminder(
                                    id: notificationId + 1,
                                    title: 'Upcoming Meeting: $title',
                                    body: leadMins == 0 ? 'Starts now' : 'Starts in $leadMins minutes',
                                    scheduledDate: reminderTime,
                                    payload: 'open_room:${meeting.roomId}',
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
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
          
          StreamBuilder<List<Meeting>>(
            stream: Meeting.streamUserMeetings(uid),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
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

              final meetings = snapshot.data ?? [];
              if (meetings.isEmpty) {
                return const Center(
                  child: Text(
                    'No upcoming meetings.',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: meetings.length,
                itemBuilder: (context, index) {
                  return _buildMeetingCard(context, meetings[index]);
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
    final isFutureScheduled = meeting.scheduledTime.isAfter(now);
    final isLive = meeting.scheduledTime.isBefore(now.add(const Duration(minutes: 15))) &&
        meeting.scheduledTime.isAfter(now.subtract(const Duration(minutes: 60)));

    final formattedDate = DateFormat('MMM d, yyyy').format(meeting.scheduledTime);
    final formattedTime = DateFormat('h:mm a').format(meeting.scheduledTime);
    final color = isLive ? const Color(0xFF00E5FF) : const Color(0xFF5C00FF);

    final user = FirebaseAuth.instance.currentUser;
    final bool isHost = meeting.hostId == user?.uid || meeting.role == 'host';
    final displayHost = meeting.hostName.isNotEmpty
        ? meeting.hostName
        : (isHost ? (user?.displayName ?? 'You') : 'La-Vie Host');

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
                    Row(
                      children: [
                        if (meeting.isPermanent) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB300).withOpacity(0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.4)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.all_inclusive_rounded, color: Color(0xFFFFB300), size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'PERMANENT ROOM',
                                  style: TextStyle(
                                    color: Color(0xFFFFB300),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
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
                        ],
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isHost
                                ? const Color(0xFF00E5FF).withOpacity(0.14)
                                : const Color(0xFF00FFA3).withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isHost ? 'HOST' : 'INVITED',
                            style: TextStyle(
                              color: isHost ? const Color(0xFF00E5FF) : const Color(0xFF00FFA3),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white54),
                      color: const Color(0xFF1E243A),
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'share',
                          child: ListTile(
                            leading: Icon(Icons.share, color: Colors.white70),
                            title: Text('Share Invite Link', style: TextStyle(color: Colors.white)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'calendar',
                          child: ListTile(
                            leading: Icon(Icons.calendar_month, color: Color(0xFF00E5FF)),
                            title: Text('Add to Google Calendar', style: TextStyle(color: Colors.white)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'reminder',
                          child: ListTile(
                            leading: Icon(Icons.notifications_active_outlined, color: Color(0xFF00FFA3)),
                            title: Text('Push Reminder Settings', style: TextStyle(color: Colors.white)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (isHost) ...[
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
                        ] else
                          const PopupMenuItem<String>(
                            value: 'remove_saved',
                            child: ListTile(
                              leading: Icon(Icons.bookmark_remove, color: Colors.redAccent),
                              title: Text('Remove Reminder', style: TextStyle(color: Colors.redAccent)),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                      onSelected: (String value) async {
                        if (value == 'delete') {
                          _deleteMeeting(context, meeting);
                        } else if (value == 'edit') {
                          _showEditMeetingDialog(context, meeting);
                        } else if (value == 'remove_saved') {
                          await ApiService.unsubscribeMeetingReminder(meeting.roomId);
                          await NotificationService().cancelNotification('${meeting.roomId}_invitee'.hashCode);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Removed reminder from your schedule.')),
                            );
                          }
                        } else if (value == 'calendar') {
                          final prefs = await SharedPreferences.getInstance();
                          final key = prefs.getString('e2ee_${meeting.roomId}');
                          await CalendarHelper.addMeetingToGoogleCalendar(
                            title: meeting.title,
                            startTime: meeting.scheduledTime,
                            roomId: meeting.roomId,
                            e2eeKey: key,
                            hostName: displayHost,
                            reminderMinutes: meeting.hostReminderMinutes,
                            allowInteractiveFallback: true,
                          );
                        } else if (value == 'reminder') {
                          final prefs = await SharedPreferences.getInstance();
                          final key = prefs.getString('e2ee_${meeting.roomId}');
                          if (context.mounted) {
                            await UpcomingMeetingInviteSheet.show(
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
                        } else if (value == 'share') {
                          final prefs = await SharedPreferences.getInstance();
                          final key = prefs.getString('e2ee_${meeting.roomId}');
                          final url = CalendarHelper.buildInviteLink(meeting.roomId, e2eeKey: key);
                          Share.share('Join "${meeting.title}" on La-Vie Conference ($formattedDate at $formattedTime):\n$url');
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
                if (meeting.isPermanent)
                  const Row(
                    children: [
                      Icon(Icons.all_inclusive_rounded, color: Color(0xFFFFB300), size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Always Open • No countdown',
                        style: TextStyle(color: Color(0xFFFFB300), fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  )
                else
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
                          backgroundColor: meeting.isPermanent ? const Color(0xFFFFB300).withOpacity(0.2) : color.withOpacity(0.2),
                          child: Text(
                            displayHost.isNotEmpty ? displayHost.substring(0, 1).toUpperCase() : 'U',
                            style: TextStyle(
                              color: meeting.isPermanent ? const Color(0xFFFFB300) : color,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Host', style: TextStyle(color: Colors.white38, fontSize: 10)),
                            Text(displayHost, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (isFutureScheduled || meeting.isPermanent)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: IconButton(
                              tooltip: meeting.isPermanent ? 'Permanent Room Info & Link' : 'Reminders & Calendar',
                              onPressed: () async {
                                final prefs = await SharedPreferences.getInstance();
                                final key = prefs.getString('e2ee_${meeting.roomId}');
                                if (context.mounted) {
                                  await UpcomingMeetingInviteSheet.show(
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
                              icon: Icon(
                                meeting.isPermanent ? Icons.all_inclusive_rounded : Icons.notifications_active_outlined,
                                color: meeting.isPermanent ? const Color(0xFFFFB300) : const Color(0xFF00FFA3),
                                size: 22,
                              ),
                            ),
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
                                  isHost: isHost,
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
                          child: const Text(
                            'Join Now',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
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
