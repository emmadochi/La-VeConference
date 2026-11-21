import 'dart:ui';
import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> showPreJoinDialog(
  BuildContext context, {
  bool isCreating = false,
  String? title,
  String? actionText,
  String? defaultMeetingTitle,
}) async {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) {
      return PreJoinDialog(
        isCreating: isCreating,
        title: title,
        actionText: actionText,
        defaultMeetingTitle: defaultMeetingTitle,
      );
    },
  );
}

class PreJoinDialog extends StatefulWidget {
  final bool isCreating;
  final String? title;
  final String? actionText;
  final String? defaultMeetingTitle;

  const PreJoinDialog({
    Key? key,
    this.isCreating = false,
    this.title,
    this.actionText,
    this.defaultMeetingTitle,
  }) : super(key: key);

  @override
  State<PreJoinDialog> createState() => _PreJoinDialogState();
}

class _PreJoinDialogState extends State<PreJoinDialog> {
  bool _audioOn = true;
  bool _videoOn = true;
  bool _requireApproval = false;
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.defaultMeetingTitle ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String displayTitle = widget.title ?? (widget.isCreating ? 'Create Meeting' : 'Ready to Join?');
    final String displayAction = widget.actionText ?? (widget.isCreating ? 'Start Meeting' : 'Join Now');

    return Center(
      child: Material(
        color: Colors.transparent,
        child: SingleChildScrollView(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.88,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF070B19).withOpacity(0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.isCreating ? 'Set your meeting name & device preferences' : 'Choose your initial device settings',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Meeting Title input (when creating)
                    if (widget.isCreating) ...[
                      TextField(
                        controller: _titleController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Meeting Topic / Title',
                          labelStyle: const TextStyle(color: Color(0xFF00E5FF), fontSize: 13),
                          hintText: 'e.g. Sunday Service, Strategy Sync',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                          prefixIcon: const Icon(Icons.edit_calendar_rounded, color: Color(0xFF00E5FF), size: 20),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    
                    // Audio Toggle
                    _buildToggleRow(
                      icon: _audioOn ? Icons.mic : Icons.mic_off,
                      title: 'Microphone',
                      isOn: _audioOn,
                      onChanged: (val) => setState(() => _audioOn = val),
                    ),
                    const SizedBox(height: 12),
                    
                    // Video Toggle
                    _buildToggleRow(
                      icon: _videoOn ? Icons.videocam : Icons.videocam_off,
                      title: 'Camera',
                      isOn: _videoOn,
                      onChanged: (val) => setState(() => _videoOn = val),
                    ),
                    if (widget.isCreating) ...[
                      const SizedBox(height: 12),
                      _buildToggleRow(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Private Waiting Room',
                        isOn: _requireApproval,
                        onChanged: (val) => setState(() => _requireApproval = val),
                      ),
                    ],
                    const SizedBox(height: 28),
                    
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final title = _titleController.text.trim();
                              Navigator.pop(context, {
                                'audio': _audioOn,
                                'video': _videoOn,
                                'requireApproval': _requireApproval,
                                'title': title.isNotEmpty ? title : (widget.defaultMeetingTitle ?? 'Instant Meeting'),
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E5FF),
                              foregroundColor: const Color(0xFF070B19),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 8,
                              shadowColor: const Color(0xFF00E5FF).withOpacity(0.5),
                            ),
                            child: Text(displayAction, style: const TextStyle(fontWeight: FontWeight.bold)),
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
      ),
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String title,
    required bool isOn,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isOn ? const Color(0xFF00E5FF).withOpacity(0.2) : Colors.white10,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isOn ? const Color(0xFF00E5FF) : Colors.white54,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(
            value: isOn,
            onChanged: onChanged,
            activeColor: const Color(0xFF00E5FF),
            inactiveThumbColor: Colors.white54,
            inactiveTrackColor: Colors.white10,
          ),
        ],
      ),
    );
  }
}
