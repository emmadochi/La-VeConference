import 'dart:math' as math;
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meeting.dart';
import '../services/calendar_helper.dart';
import '../services/notification_service.dart';

class ScheduleMeetingDialog {
  static String _generateRoomCode() {
    return 'la-vie-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
  }

  static String _generateE2EEKey() {
    final math.Random random = math.Random.secure();
    final List<int> values = List<int>.generate(16, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  static Future<void> show(BuildContext context) async {
    final TextEditingController titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(
      DateTime.now().add(const Duration(minutes: 30)),
    );
    int hostReminderMinutes = 15;
    bool addToGoogleCalendar = true;
    bool requireApproval = false;
    bool isSaving = false;

    const List<Map<String, dynamic>> reminderOptions = [
      {'label': 'At start', 'mins': 0},
      {'label': '10m before', 'mins': 10},
      {'label': '15m before', 'mins': 15},
      {'label': '30m before', 'mins': 30},
      {'label': '1h before', 'mins': 60},
    ];

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
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
                      border: Border.all(
                        color: const Color(0xFF5C00FF).withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF5C00FF).withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.event_available, color: Color(0xFF00E5FF), size: 34),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Schedule Meeting',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 18),
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
                                      context: ctx,
                                      initialDate: selectedDate,
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime(2101),
                                    );
                                    if (pickedDate != null) {
                                      setDialogState(() => selectedDate = pickedDate);
                                    }
                                  },
                                  icon: const Icon(Icons.calendar_today, size: 16),
                                  label: Text(
                                    DateFormat('MMM d, yyyy').format(selectedDate),
                                    style: const TextStyle(fontSize: 12),
                                  ),
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
                                      context: ctx,
                                      initialTime: selectedTime,
                                    );
                                    if (pickedTime != null) {
                                      setDialogState(() => selectedTime = pickedTime);
                                    }
                                  },
                                  icon: const Icon(Icons.access_time, size: 16),
                                  label: Text(selectedTime.format(ctx), style: const TextStyle(fontSize: 12)),
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
                          const SizedBox(height: 16),
                          const Text(
                            'Host Push Reminder',
                            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: reminderOptions.map((opt) {
                              final mins = opt['mins'] as int;
                              final isSelected = hostReminderMinutes == mins;
                              return ChoiceChip(
                                label: Text(opt['label'] as String),
                                selected: isSelected,
                                onSelected: (_) => setDialogState(() => hostReminderMinutes = mins),
                                selectedColor: const Color(0xFF00E5FF),
                                backgroundColor: Colors.white.withOpacity(0.06),
                                labelStyle: TextStyle(
                                  color: isSelected ? const Color(0xFF070B19) : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeColor: const Color(0xFF00FFA3),
                            title: const Text(
                              'Add to Google Calendar',
                              style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Syncs event & invite link to your calendar',
                              style: TextStyle(color: Colors.white54, fontSize: 11.5),
                            ),
                            value: addToGoogleCalendar,
                            onChanged: (val) => setDialogState(() => addToGoogleCalendar = val),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeColor: const Color(0xFF00E5FF),
                            title: const Text(
                              'Private Waiting Room',
                              style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Host must approve guests before they enter',
                              style: TextStyle(color: Colors.white54, fontSize: 11.5),
                            ),
                            value: requireApproval,
                            onChanged: (val) => setDialogState(() => requireApproval = val),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  onPressed: isSaving
                                      ? null
                                      : () async {
                                          final title = titleController.text.trim();
                                          if (title.isEmpty) return;

                                          setDialogState(() => isSaving = true);

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

                                          final user = FirebaseAuth.instance.currentUser;
                                          final hostId = user?.uid ?? '';
                                          final hostName = user?.displayName ?? 'La-Vie Host';

                                          final meeting = Meeting(
                                            id: roomId,
                                            title: title,
                                            roomId: roomId,
                                            hostId: hostId,
                                            hostName: hostName,
                                            scheduledTime: scheduledDateTime,
                                            status: 'scheduled',
                                            meetingType: 'scheduled',
                                            notified: false,
                                            hostReminderMinutes: hostReminderMinutes,
                                            requireApproval: requireApproval,
                                          );

                                          await FirebaseFirestore.instance
                                              .collection('meetings')
                                              .doc(roomId)
                                              .set(meeting.toFirestore(), SetOptions(merge: true));

                                          final notificationId = roomId.hashCode;
                                          NotificationService().showImmediateNotification(
                                            id: notificationId,
                                            title: 'Meeting Scheduled',
                                            body: '$title is set for ${DateFormat('MMM d, h:mm a').format(scheduledDateTime)}',
                                            payload: 'open_room:$roomId#$e2eeKey',
                                          );

                                          final reminderTime = scheduledDateTime
                                              .subtract(Duration(minutes: hostReminderMinutes));
                                          final leadText = hostReminderMinutes == 0
                                              ? 'now'
                                              : (hostReminderMinutes == 60
                                                  ? 'in 1 hour'
                                                  : 'in $hostReminderMinutes minutes');

                                          NotificationService().scheduleMeetingReminder(
                                            id: notificationId + 1,
                                            title: 'Upcoming Meeting: $title',
                                            body: 'Starts $leadText • Tap to enter stage',
                                            scheduledDate: reminderTime,
                                            payload: 'open_room:$roomId#$e2eeKey',
                                          );

                                          CalendarSyncStatus calStatus = CalendarSyncStatus.failed;
                                          if (addToGoogleCalendar) {
                                            calStatus = await CalendarHelper.addMeetingToGoogleCalendar(
                                              title: title,
                                              startTime: scheduledDateTime,
                                              roomId: roomId,
                                              e2eeKey: e2eeKey,
                                              hostName: hostName,
                                              reminderMinutes: hostReminderMinutes,
                                              allowInteractiveFallback: true,
                                            );
                                          }

                                          if (context.mounted) {
                                            String statusMsg = 'Meeting scheduled & push alert armed!';
                                            if (calStatus == CalendarSyncStatus.addedViaApi) {
                                              statusMsg = 'Meeting scheduled & synced to Google Calendar!';
                                            } else if (calStatus == CalendarSyncStatus.openedTemplateIntent) {
                                              statusMsg = 'Meeting scheduled • Opening Google Calendar...';
                                            }
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                backgroundColor: const Color(0xFF00FFA3),
                                                content: Text(
                                                  statusMsg,
                                                  style: const TextStyle(
                                                    color: Color(0xFF070B19),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            );
                                          }

                                          if (dialogCtx.mounted) {
                                            Navigator.pop(dialogCtx);
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00E5FF),
                                    foregroundColor: const Color(0xFF070B19),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  child: isSaving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF070B19),
                                          ),
                                        )
                                      : const Text(
                                          'Schedule',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
              ),
            );
          },
        );
      },
    );
  }
}

