import 'dart:ui';
import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) {
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
      ),
      body: Stack(
        children: [
          // Background Glow
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Manage how La-Vie communicates with you.', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 30),
                  _buildToggleOption(
                    title: 'Push Notifications',
                    subtitle: 'Receive alerts when a meeting starts.',
                    value: _pushEnabled,
                    onChanged: (val) => setState(() => _pushEnabled = val),
                    iconColor: const Color(0xFF00E5FF),
                    icon: Icons.notifications_active,
                  ),
                  const SizedBox(height: 16),
                  _buildToggleOption(
                    title: 'Meeting Reminders',
                    subtitle: 'Get reminded 10 minutes before a scheduled meeting.',
                    value: _remindersEnabled,
                    onChanged: (val) => setState(() => _remindersEnabled = val),
                    iconColor: const Color(0xFF5C00FF),
                    icon: Icons.access_alarm,
                  ),
                  const SizedBox(height: 16),
                  _buildToggleOption(
                    title: 'Email Updates',
                    subtitle: 'Receive weekly summaries and tips.',
                    value: _emailEnabled,
                    onChanged: (val) => setState(() => _emailEnabled = val),
                    iconColor: const Color(0xFFB524D3),
                    icon: Icons.email,
                  ),
                ],
              ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
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
        ),
      ),
    );
  }
}
