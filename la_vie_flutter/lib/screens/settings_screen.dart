import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support_screen.dart';
import '../services/lcm_bridge.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _dataSaverMode = false;
  bool _muteMicDefault = false;
  bool _offCameraDefault = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dataSaverMode = prefs.getBool('dataSaverMode') ?? false;
      _muteMicDefault = prefs.getBool('muteMicDefault') ?? false;
      _offCameraDefault = prefs.getBool('offCameraDefault') ?? false;
      _isLoading = false;
    });
  }

  Future<void> _savePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
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
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          else
            ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                _buildSectionHeader('Call Preferences'),
                const SizedBox(height: 16),
                _buildSwitchTile(
                  icon: Icons.data_usage,
                  color: const Color(0xFF00E5FF),
                  title: 'Data Saver Mode',
                  subtitle: 'Reduces video quality to save bandwidth',
                  value: _dataSaverMode,
                  onChanged: (val) {
                    setState(() => _dataSaverMode = val);
                    _savePreference('dataSaverMode', val);
                  },
                ),
                const SizedBox(height: 16),
                _buildSwitchTile(
                  icon: Icons.mic_off,
                  color: const Color(0xFF5C00FF),
                  title: 'Mute Microphone by Default',
                  subtitle: 'Start meetings with your microphone muted',
                  value: _muteMicDefault,
                  onChanged: (val) {
                    setState(() => _muteMicDefault = val);
                    _savePreference('muteMicDefault', val);
                  },
                ),
                const SizedBox(height: 16),
                _buildSwitchTile(
                  icon: Icons.videocam_off,
                  color: const Color(0xFFB524D3),
                  title: 'Turn Off Camera by Default',
                  subtitle: 'Start meetings with your camera off',
                  value: _offCameraDefault,
                  onChanged: (val) {
                    setState(() => _offCameraDefault = val);
                    _savePreference('offCameraDefault', val);
                  },
                ),
                
                const SizedBox(height: 40),
                const SizedBox(height: 32),
                _buildSectionHeader('Support & Assistance'),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const SupportScreen()));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FFA3).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00FFA3).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.support_agent, color: Color(0xFF00FFA3)),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Help & Support Center', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text('Submit tickets & troubleshooting guides', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white54),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () {
                    LcmBridge.showFeedbackDialog(
                      context,
                      packageName: 'org.lifechangerstouch.lavie',
                      appName: 'La-Vie Enterprise',
                      currentVersion: '1.0.1',
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF2A6D).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFF2A6D).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF2A6D).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.bug_report_outlined, color: Color(0xFFFF2A6D)),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Beta Feedback & Bug Report', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text('Help us optimize performance & stability', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white54),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),
                _buildSectionHeader('App Information'),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    LcmBridge.checkForUpdates(
                      context,
                      packageName: 'org.lifechangerstouch.lavie',
                      currentVersion: '1.0.1',
                      showToastIfLatest: true,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.system_update_rounded, color: Color(0xFF00E5FF)),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Version & Updates', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text('1.0.1 (Build 2) • Tap to check updates', style: TextStyle(color: Colors.white54, fontSize: 13)),
                            ],
                          ),
                        ),
                        const Icon(Icons.refresh_rounded, color: Color(0xFF00E5FF), size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: color,
            activeTrackColor: color.withOpacity(0.5),
            inactiveThumbColor: Colors.white54,
            inactiveTrackColor: Colors.white.withOpacity(0.1),
          ),
        ],
      ),
    );
  }
}
