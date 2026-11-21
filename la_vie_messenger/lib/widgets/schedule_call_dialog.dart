import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';

class ScheduleCallDialog extends StatefulWidget {
  final String chatId;
  final String callerId;
  final String callerName;
  final String? callerAvatar;
  final String receiverId;
  final String receiverName;
  final bool isGroup;
  final List<String>? participants;
  final String? initialTopic;
  final DateTime? initialDateTime;
  final bool initialIsVideo;

  const ScheduleCallDialog({
    super.key,
    required this.chatId,
    required this.callerId,
    required this.callerName,
    this.callerAvatar,
    required this.receiverId,
    required this.receiverName,
    this.isGroup = false,
    this.participants,
    this.initialTopic,
    this.initialDateTime,
    this.initialIsVideo = true,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String chatId,
    required String callerId,
    required String callerName,
    String? callerAvatar,
    required String receiverId,
    required String receiverName,
    bool isGroup = false,
    List<String>? participants,
    String? initialTopic,
    DateTime? initialDateTime,
    bool initialIsVideo = true,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ScheduleCallDialog(
        chatId: chatId,
        callerId: callerId,
        callerName: callerName,
        callerAvatar: callerAvatar,
        receiverId: receiverId,
        receiverName: receiverName,
        isGroup: isGroup,
        participants: participants,
        initialTopic: initialTopic,
        initialDateTime: initialDateTime,
        initialIsVideo: initialIsVideo,
      ),
    );
  }

  @override
  State<ScheduleCallDialog> createState() => _ScheduleCallDialogState();
}

class _ScheduleCallDialogState extends State<ScheduleCallDialog> {
  late TextEditingController _topicController;
  late bool _isVideo;
  late DateTime _selectedDateTime;
  int _reminderMinutes = 10;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _topicController = TextEditingController(
      text: widget.initialTopic ?? (widget.isGroup ? "Team Call" : "Call with ${widget.receiverName}"),
    );
    _isVideo = widget.initialIsVideo;
    final now = DateTime.now();
    _selectedDateTime = widget.initialDateTime ?? now.add(const Duration(minutes: 30));
    if (_selectedDateTime.isBefore(now)) {
      _selectedDateTime = now.add(const Duration(minutes: 15));
    }
  }

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary,
              surface: AppTheme.surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDateTime.hour,
          _selectedDateTime.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary,
              surface: AppTheme.surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  void _applyPreset(Duration offset, {int? setHour, int? setMinute}) {
    final now = DateTime.now();
    DateTime target = now.add(offset);
    if (setHour != null) {
      target = DateTime(target.year, target.month, target.day, setHour, setMinute ?? 0);
    }
    setState(() {
      _selectedDateTime = target;
    });
  }

  Future<void> _submitSchedule() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a call topic")),
      );
      return;
    }

    if (_selectedDateTime.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a future date and time")),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final scheduledIso = _selectedDateTime.toUtc().toIso8601String();
      final participantsList = widget.participants ?? [widget.callerId, widget.receiverId];

      final res = await http.post(
        Uri.parse('https://la-vie.lifechangerstouch.org/api/lichat/call/schedule'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chatId': widget.chatId,
          'callerId': widget.callerId,
          'callerName': widget.callerName,
          'callerAvatar': widget.callerAvatar ?? '',
          'receiverId': widget.receiverId,
          'participants': participantsList,
          'topic': topic,
          'isVideo': _isVideo,
          'isGroup': widget.isGroup,
          'scheduledTime': scheduledIso,
          'reminderMinutes': _reminderMinutes,
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          Navigator.pop(context, data);
        }
      } else {
        throw Exception("Server returned ${res.statusCode}: ${res.body}");
      }
    } catch (e) {
      debugPrint("Failed to schedule call: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Scheduling error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.border,
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
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: AppTheme.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Schedule a Call",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.isGroup
                            ? "With group members"
                            : "With ${widget.receiverName}",
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Topic Field
            const Text(
              "Topic / Purpose",
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _topicController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "e.g., Weekly Sync, Project Review",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // Call Type Toggle
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isVideo = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _isVideo ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isVideo ? AppTheme.primary : AppTheme.border,
                          width: _isVideo ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam_rounded, color: _isVideo ? AppTheme.primary : Colors.white60, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            "Video Call",
                            style: TextStyle(
                              color: _isVideo ? Colors.white : Colors.white60,
                              fontWeight: _isVideo ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isVideo = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_isVideo ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !_isVideo ? AppTheme.primary : AppTheme.border,
                          width: !_isVideo ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.call_rounded, color: !_isVideo ? AppTheme.primary : Colors.white60, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            "Voice Call",
                            style: TextStyle(
                              color: !_isVideo ? Colors.white : Colors.white60,
                              fontWeight: !_isVideo ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Date & Time Selectors
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Date", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_rounded, color: AppTheme.primary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dateFormat.format(_selectedDateTime),
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Time", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickTime,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time_rounded, color: AppTheme.primary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  timeFormat.format(_selectedDateTime),
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Smart Quick Time Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildQuickChip("In 30m", () => _applyPreset(const Duration(minutes: 30))),
                  const SizedBox(width: 8),
                  _buildQuickChip("In 1 Hour", () => _applyPreset(const Duration(hours: 1))),
                  const SizedBox(width: 8),
                  _buildQuickChip("Tomorrow 10 AM", () => _applyPreset(const Duration(days: 1), setHour: 10, setMinute: 0)),
                  const SizedBox(width: 8),
                  _buildQuickChip("Tomorrow 3 PM", () => _applyPreset(const Duration(days: 1), setHour: 15, setMinute: 0)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Reminder Offset Dropdown
            const Text(
              "Push Notification Reminder",
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _reminderMinutes,
                  dropdownColor: AppTheme.surface,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                  isExpanded: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text("5 minutes before")),
                    DropdownMenuItem(value: 10, child: Text("10 minutes before (Recommended)")),
                    DropdownMenuItem(value: 15, child: Text("15 minutes before")),
                    DropdownMenuItem(value: 30, child: Text("30 minutes before")),
                    DropdownMenuItem(value: 60, child: Text("1 hour before")),
                    DropdownMenuItem(value: 0, child: Text("At call start time only")),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _reminderMinutes = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitSchedule,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            "Schedule & Send Invite",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

