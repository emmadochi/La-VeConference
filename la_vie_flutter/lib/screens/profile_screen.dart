import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'login_screen.dart';
import 'account_details_screen.dart';
import 'notifications_screen.dart';
import 'privacy_security_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/lcm_bridge.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploading = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadProfilePhoto();
  }

  String? _normalizeAvatarUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('/')) {
      return '${ApiService.baseUrl}$trimmed';
    }
    return trimmed;
  }

  Future<void> _loadProfilePhoto() async {
    final user = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;
    if (user == null) return;

    final authUrl = _normalizeAvatarUrl(user.photoURL);
    if (authUrl != null && mounted) {
      setState(() => _avatarUrl = authUrl);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = _normalizeAvatarUrl(prefs.getString('user_avatar_cache_${user.uid}'));
      if (cached != null && mounted) {
        setState(() => _avatarUrl = cached);
      }

      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final fsUrl = _normalizeAvatarUrl((data['photoURL'] ?? data['avatar'])?.toString());
        if (fsUrl != null) {
          await prefs.setString('user_avatar_cache_${user.uid}', fsUrl);
          if (mounted) {
            setState(() => _avatarUrl = fsUrl);
          }
          if (user.photoURL != fsUrl) {
            try {
              await user.updatePhotoURL(fsUrl);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _logout(BuildContext context) async {
    if (Firebase.apps.isNotEmpty) {
      await FirebaseAuth.instance.signOut();
    }
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  void _showPhotoOptionsSheet() {
    if (_isUploading) return;
    final hasPhoto = _avatarUrl != null && _avatarUrl!.isNotEmpty;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF00E5FF)),
                  title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _pickAndUploadImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF00E5FF)),
                  title: const Text('Take a Photo', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _pickAndUploadImage(ImageSource.camera);
                  },
                ),
                if (hasPhoto)
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: const Text('Remove Photo', style: TextStyle(color: Colors.redAccent)),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _removeProfilePhoto();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _removeProfilePhoto() async {
    final user = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;
    if (user == null) return;
    setState(() => _isUploading = true);
    try {
      await user.updatePhotoURL(null);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'photoURL': '', 'avatar': '', 'updatedAt': DateTime.now().toIso8601String()},
        SetOptions(merge: true),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_avatar_cache_${user.uid}');
      if (mounted) {
        setState(() => _avatarUrl = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo removed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove photo: ${e.toString().replaceFirst("Exception: ", "")}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (image == null) return; // User canceled

      setState(() {
        _isUploading = true;
      });

      final File file = File(image.path);
      final user = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;
      if (user == null) return;

      String downloadUrl;
      try {
        downloadUrl = await ApiService.uploadProfilePhoto(file: file, uid: user.uid);
      } catch (backendErr) {
        // Fallback to Firebase Storage only if backend is unreachable on network
        final errText = backendErr.toString().toLowerCase();
        final isNetworkDown = errText.contains('network error') || errText.contains('socket');
        if (!isNetworkDown) rethrow;

        final storageRef = FirebaseStorage.instance.ref().child('avatars/${user.uid}.jpg');
        await storageRef.putFile(file);
        downloadUrl = await storageRef.getDownloadURL();
      }

      await user.updatePhotoURL(downloadUrl);
      await user.reload();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'photoURL': downloadUrl,
          'avatar': downloadUrl,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_avatar_cache_${user.uid}', downloadUrl);

      if (mounted) {
        setState(() => _avatarUrl = downloadUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated!'),
            backgroundColor: Color(0xFF00C853),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final cleanMsg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $cleanMsg'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // get user again in case of reload
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Premium User';
    final email = user?.email ?? 'user@lavie.com';
    final photoURL = _avatarUrl ?? _normalizeAvatarUrl(user?.photoURL);
    final initial = displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [const Color(0xFF00E5FF).withOpacity(0.15), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // User Avatar
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF00E5FF), Color(0xFF5C00FF)],
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF070B19),
                              shape: BoxShape.circle,
                            ),
                            child: CircleAvatar(
                              radius: 56,
                              backgroundColor: const Color(0xFF00E5FF).withOpacity(0.1),
                              child: _isUploading
                                  ? const CircularProgressIndicator(color: Color(0xFF00E5FF))
                                  : (photoURL != null && photoURL.isNotEmpty
                                      ? ClipOval(
                                          child: Image.network(
                                            photoURL,
                                            width: 112,
                                            height: 112,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Text(
                                                initial,
                                                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 48, fontWeight: FontWeight.bold),
                                              );
                                            },
                                          ),
                                        )
                                      : Text(
                                          initial,
                                          style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 48, fontWeight: FontWeight.bold),
                                        )),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _showPhotoOptionsSheet,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF5C00FF),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF070B19), width: 3),
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    email,
                    style: const TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                  const SizedBox(height: 36),

                  // Account Settings & Support Options
                  _buildSettingOption(Icons.person_outline, 'Account Details', const Color(0xFF00E5FF), () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AccountDetailsScreen()));
                  }),
                  const SizedBox(height: 14),
                  _buildSettingOption(Icons.notifications_none, 'Notifications', const Color(0xFF5C00FF), () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen()));
                  }),
                  const SizedBox(height: 14),
                  _buildSettingOption(Icons.lock_outline, 'Privacy & Security', const Color(0xFFB524D3), () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const PrivacySecurityScreen()));
                  }),
                  const SizedBox(height: 14),
                  _buildSettingOption(Icons.support_agent, 'Help & Support', const Color(0xFF00FFA3), () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const SupportScreen()));
                  }),
                  const SizedBox(height: 14),
                  _buildSettingOption(Icons.settings_outlined, 'App Settings', const Color(0xFFFFB300), () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
                  }),
                  const SizedBox(height: 14),
                  _buildSettingOption(Icons.bug_report_outlined, 'Beta Feedback & Bug Report', const Color(0xFFFF2A6D), () {
                    LcmBridge.showFeedbackDialog(
                      context,
                      packageName: 'org.lifechangerstouch.lavie',
                      appName: 'La-Vie Enterprise',
                      currentVersion: '1.0.1',
                    );
                  }),
                  const SizedBox(height: 14),
                  _buildSettingOption(Icons.privacy_tip_outlined, 'Privacy Policy', const Color(0xFF00E5FF), () async {
                    final url = Uri.parse('https://la-vie.lifechangerstouch.org/privacy');
                    try {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    } catch (e) {
                      debugPrint('Error launching privacy policy: $e');
                    }
                  }),
                  const SizedBox(height: 14),
                  _buildSettingOption(Icons.gavel_outlined, 'Terms of Service', const Color(0xFF7000FF), () async {
                    final url = Uri.parse('https://la-vie.lifechangerstouch.org/terms');
                    try {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    } catch (e) {
                      debugPrint('Error launching terms: $e');
                    }
                  }),
                  const SizedBox(height: 32),

                  // Logout Button
                  GestureDetector(
                    onTap: () => _logout(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout, color: Colors.redAccent),
                          SizedBox(width: 8),
                          Text(
                            'Log Out',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingOption(IconData icon, String title, Color iconColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
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
                  child: Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
